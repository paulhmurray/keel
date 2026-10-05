import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/llm/context_builder.dart';
import '../../../core/llm/llm_client.dart';
import '../../../core/llm/llm_client_factory.dart';
import '../../../core/plan/plan_gaps.dart';
import '../../../core/plan/replan.dart' show replanMonthLabel;
import '../../../core/plan/variance_links.dart';
import '../../../core/raid/dependency_plan_link.dart';
import '../../../providers/settings_provider.dart';
import '../../../shared/theme/keel_colors.dart';
import '../../../shared/widgets/plan_activity_picker.dart';

/// "Pull in from the registers": open actions, pending decisions, open
/// dependencies and live risks that no plan row knows about, each with
/// a proposed home — an existing activity, or a new row. The engine
/// guesses from dates; the model (optional) chooses by meaning. The PM
/// can change the target on every card. Accept writes the link the
/// rest of Keel already understands: an action's plan activity, a
/// decision's or dependency's gated activity plus its arrow, a risk as
/// a schedule driver on the activity it threatens.
class PlanGapsDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;

  /// Tests pass a fake that answers with canned JSON.
  final LLMClient? client;

  const PlanGapsDialog({
    super.key,
    required this.db,
    required this.projectId,
    this.client,
  });

  @override
  State<PlanGapsDialog> createState() => _PlanGapsDialogState();
}

enum _Phase { loading, scope, placing, review, done }

class _PlanGapsDialogState extends State<PlanGapsDialog> {
  _Phase _phase = _Phase.loading;
  List<PlanGap> _gaps = const [];
  List<TimelineActivity> _acts = const [];
  List<TimelineWorkPackage> _wps = const [];
  ProgrammeHeader? _header;
  DateTime? _month0;
  final Map<String, GapPlacement> _placements = {};
  final Map<String, String> _errors = {};
  int _placed = 0;
  bool _cancelled = false;
  int _index = 0;
  int _accepted = 0, _skipped = 0;
  bool _applying = false;
  bool _wrote = false;

  // "New activity" editor on the current card.
  final _newNameCtrl = TextEditingController();
  // The "or a new row" fields stay folded until asked for, or until the
  // placement already is a new row.
  bool _newRowOpen = false;

  bool get _aiAvailable =>
      widget.client != null || context.watch<SettingsProvider>().hasApiKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancelled = true;
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = widget.db;
    final pid = widget.projectId;
    _header = await db.programmeGanttDao.getHeader(pid);
    _acts = await db.programmeGanttDao.getActivitiesForProject(pid);
    _wps = await db.programmeGanttDao.getWorkPackages(pid);
    final gaps = collectPlanGaps(
      actions: await db.actionsDao.getActionsForProject(pid),
      decisions: await db.decisionsDao.getDecisionsForProject(pid),
      dependencies: await db.raidDao.getDependenciesForProject(pid),
      risks: await db.raidDao.getRisksForProject(pid),
      activities: _acts,
      month0Date: _header?.month0Date,
    );
    if (!mounted) return;
    setState(() {
      _month0 = _header?.month0Date != null
          ? DateTime.tryParse(_header!.month0Date!)
          : null;
      _gaps = gaps;
      for (final g in gaps) {
        final p = placeGapDeterministically(
          g,
          activities: _acts,
          workPackages: _wps,
          month0: _month0,
        );
        if (p != null) _placements[g.id] = p;
      }
      _phase = _Phase.scope;
    });
  }

  PlanGap get _current => _gaps[_index];
  GapPlacement? get _placement => _placements[_current.id];

  /// Open, top-level activities the model may choose from, nearest the
  /// due month first and capped so the prompt fits a local model.
  List<TimelineActivity> _candidates(PlanGap g) {
    final list = _acts
        .where(
          (a) =>
              a.sourceProjectId == null &&
              a.parentActivityId == null &&
              a.status != 'complete',
        )
        .toList();
    final due = g.dueMonth;
    if (due != null) {
      int dist(TimelineActivity a) {
        final s = a.startMonth;
        if (s == null) return 1000;
        final e = a.endMonth ?? s;
        return due < s ? s - due : (due > e ? due - e : 0);
      }

      list.sort((x, y) => dist(x).compareTo(dist(y)));
    }
    return list.take(80).toList();
  }

  Future<void> _place() async {
    final settings = context.read<SettingsProvider>().settings;
    final client = widget.client ?? LLMClientFactory.fromSettings(settings);
    setState(() {
      _placed = 0;
      _phase = _Phase.placing;
    });
    String projectContext = '';
    try {
      projectContext = await ContextBuilder(widget.db).buildSystemPrompt(
        widget.projectId,
        quarterAnchorMonth: settings.quarterAnchorMonth,
      );
    } catch (_) {}
    final actIds = _acts.map((a) => a.id).toSet();
    final wpIds = _wps.map((w) => w.id).toSet();
    for (final g in _gaps) {
      if (_cancelled || !mounted) return;
      try {
        final prompt = gapAssistPrompt(
          gap: g,
          activities: _candidates(g),
          workPackages: _wps,
          month0: _month0,
          engine: _placements[g.id],
          projectContext: projectContext,
        );
        final raw = await client.complete(
          systemPrompt: prompt.system,
          userMessage: prompt.user,
          maxTokens: 300,
        );
        final p = parseGapPlacement(
          raw,
          activityIds: actIds,
          workPackageIds: wpIds,
          month0: _month0,
        );
        if (p == null) {
          _errors[g.id] = 'No usable answer';
        } else {
          _placements[g.id] = p;
        }
      } catch (e) {
        _errors[g.id] = '$e';
      }
      if (!mounted) return;
      setState(() => _placed++);
    }
    if (!mounted) return;
    _start();
  }

  void _start() {
    setState(() {
      _index = 0;
      _phase = _gaps.isEmpty ? _Phase.done : _Phase.review;
      _loadCard();
    });
  }

  void _loadCard() {
    if (_index >= _gaps.length) return;
    _newNameCtrl.text = _placement?.newName ?? _current.display;
    _newRowOpen = _placement?.isNew ?? false;
  }

  void _advance() {
    _index++;
    setState(() {
      if (_index >= _gaps.length) {
        _phase = _Phase.done;
      } else {
        _loadCard();
      }
    });
  }

  void _skip() {
    _skipped++;
    _advance();
  }

  // ── Writes ───────────────────────────────────────────────────────────

  Future<void> _accept() async {
    if (_applying) return;
    final p = _placement;
    if (p == null || p.isEmpty) return;
    setState(() => _applying = true);
    final g = _current;
    final db = widget.db;
    final pid = widget.projectId;
    final now = DateTime.now();

    String activityId;
    if (p.isNew) {
      activityId = const Uuid().v4();
      final siblings = _acts
          .where((a) => a.workPackageId == p.newWorkPackageId)
          .length;
      final name = _newNameCtrl.text.trim().isEmpty
          ? (p.newName ?? g.display)
          : _newNameCtrl.text.trim();
      await db.programmeGanttDao.upsertActivity(
        TimelineActivitiesCompanion(
          id: Value(activityId),
          workPackageId: Value(p.newWorkPackageId!),
          projectId: Value(pid),
          name: Value(name),
          activityType: Value(p.newType),
          startMonth: Value(p.newMonth ?? g.dueMonth),
          endMonth: Value(p.newMonth ?? g.dueMonth),
          sortOrder: Value(siblings),
          notes: Value(
            'Added from the ${g.kind.label.toLowerCase()} register '
            '${_iso(now)}: ${g.display}.',
          ),
          updatedAt: Value(now),
        ),
      );
      final fresh = await db.programmeGanttDao.getActivityById(activityId);
      if (fresh != null) _acts = [..._acts, fresh];
    } else {
      activityId = p.activityId!;
    }

    switch (g.kind) {
      case GapKind.action:
        final a = await db.actionsDao.getActionById(g.id);
        if (a != null) {
          await db.actionsDao.upsertAction(
            ProjectActionsCompanion(
              id: Value(a.id),
              projectId: Value(a.projectId),
              description: Value(a.description),
              planActivityId: Value(activityId),
              updatedAt: Value(now),
            ),
          );
        }
      case GapKind.decision:
        final d = await db.decisionsDao.getDecisionById(g.id);
        if (d != null) {
          await db.decisionsDao.upsertDecision(
            DecisionsCompanion(
              id: Value(d.id),
              projectId: Value(d.projectId),
              description: Value(d.description),
              planActivityId: Value(activityId),
              updatedAt: Value(now),
            ),
          );
          await DependencyPlanLink.sync(
            db,
            projectId: pid,
            dependencyId: d.id,
            ref: d.ref,
            description: d.description,
            dependencyType: 'inbound',
            activityId: activityId,
            show: true,
            kind: PlanLinkKind.decision,
          );
        }
      case GapKind.dependency:
        final d = await db.raidDao.getDependencyById(g.id);
        if (d != null) {
          await db.raidDao.upsertDependency(
            ProgramDependenciesCompanion(
              id: Value(d.id),
              projectId: Value(d.projectId),
              description: Value(d.description),
              planActivityId: Value(activityId),
              updatedAt: Value(now),
            ),
          );
          await DependencyPlanLink.sync(
            db,
            projectId: pid,
            dependencyId: d.id,
            ref: d.ref,
            description: d.description,
            dependencyType: d.dependencyType,
            activityId: activityId,
            show: true,
          );
        }
      case GapKind.risk:
        final act = await db.programmeGanttDao.getActivityById(activityId);
        if (act != null) {
          final links = effectiveVarianceLinks(
            linksJson: act.varianceRaidLinksJson,
            legacyType: act.varianceRaidType,
            legacyId: act.varianceRaidId,
          );
          if (links.length < kMaxVarianceLinks &&
              !links.any((l) => l.type == 'risk' && l.id == g.id)) {
            final next = [...links, (type: 'risk', id: g.id)];
            await db.programmeGanttDao.patchActivity(
              act.id,
              TimelineActivitiesCompanion(
                varianceRaidLinksJson: Value(encodeVarianceLinks(next)),
                varianceRaidType: Value(next.first.type),
                varianceRaidId: Value(next.first.id),
                updatedAt: Value(now),
              ),
            );
          }
        }
    }
    _accepted++;
    _wrote = true;
    if (!mounted) return;
    setState(() => _applying = false);
    _advance();
  }

  static String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Row(
        children: [
          const Icon(
            Icons.move_to_inbox_outlined,
            size: 16,
            color: KColors.amber,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Pull in from the registers',
              style: TextStyle(color: KColors.text, fontSize: 14),
            ),
          ),
          if (_phase == _Phase.review)
            Text(
              '${_index + 1} of ${_gaps.length}',
              style: const TextStyle(color: KColors.textMuted, fontSize: 11),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: KColors.textMuted),
            tooltip: _phase == _Phase.review
                ? 'Stop — what you accepted stays'
                : 'Close',
            onPressed: () => Navigator.of(context).pop(_wrote),
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        child: switch (_phase) {
          _Phase.loading => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
          ),
          _Phase.scope => _scopeStep(),
          _Phase.placing => _placingStep(),
          _Phase.review => _reviewStep(),
          _Phase.done => _doneStep(),
        },
      ),
      actions: switch (_phase) {
        _Phase.loading => const [],
        _Phase.scope => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          if (_aiAvailable && _gaps.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _place,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: const Text('Ask AI where each belongs'),
            ),
          ElevatedButton.icon(
            onPressed: _gaps.isEmpty ? null : _start,
            icon: const Icon(Icons.rule, size: 14),
            label: Text(
              _gaps.length == 1
                  ? 'Review the item'
                  : 'Review ${_gaps.length} items',
            ),
          ),
        ],
        _Phase.placing => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
        _Phase.review => [
          TextButton(
            onPressed: _applying ? null : _skip,
            child: const Text('Skip'),
          ),
          ElevatedButton.icon(
            onPressed: _applying || (_placement?.isEmpty ?? true)
                ? null
                : _accept,
            icon: const Icon(Icons.check, size: 14),
            label: Text(
              (_placement?.isNew ?? false)
                  ? 'Create ${_placement!.newType} and link'
                  : 'Link',
            ),
          ),
        ],
        _Phase.done => [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_wrote),
            child: const Text('Done'),
          ),
        ],
      },
    );
  }

  Widget _scopeStep() {
    final counts = <GapKind, int>{};
    for (final g in _gaps) {
      counts[g.kind] = (counts[g.kind] ?? 0) + 1;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Open actions with a due date, pending decisions, open inbound '
          'dependencies and live risks that no plan activity knows about. '
          'Each gets a proposed home: the activity it belongs with, or a new '
          'row when nothing fits. You can change the target on every card. '
          'Nothing is written until you accept. Linking writes what Keel '
          'already understands: an action\'s activity, the activity a '
          'decision or dependency gates (with its arrow), a risk as a '
          'schedule driver.',
          style: TextStyle(color: KColors.textDim, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        if (_gaps.isEmpty)
          const Text(
            'Nothing is missing. Every dated register item is on the plan.',
            style: TextStyle(color: KColors.phosphor, fontSize: 13),
          )
        else ...[
          for (final k in GapKind.values)
            if ((counts[k] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(_iconFor(k), size: 14, color: KColors.amber),
                    const SizedBox(width: 8),
                    Text(
                      '${counts[k]} ${k.label.toLowerCase()}${counts[k] == 1 ? '' : 's'} '
                      'not on the plan',
                      style: const TextStyle(color: KColors.text, fontSize: 13),
                    ),
                  ],
                ),
              ),
          if (_month0 == null) ...[
            const SizedBox(height: 8),
            const Text(
              'The plan has no month-0 anchor, so due dates cannot be placed '
              'by month; proposals fall back to the first open activity.',
              style: TextStyle(color: KColors.amber, fontSize: 11),
            ),
          ],
        ],
      ],
    );
  }

  Widget _placingStep() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 12),
      LinearProgressIndicator(
        value: _gaps.isEmpty ? 0 : _placed / _gaps.length,
        color: KColors.phosphor,
        backgroundColor: KColors.surface2,
      ),
      const SizedBox(height: 12),
      Text(
        'Placing $_placed of ${_gaps.length}…',
        style: const TextStyle(color: KColors.textDim, fontSize: 12),
      ),
      if (_errors.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${_errors.length} could not be placed by the model; those '
            'cards keep the engine\'s guess.',
            style: const TextStyle(color: KColors.amber, fontSize: 11),
          ),
        ),
      const SizedBox(height: 12),
    ],
  );

  Widget _reviewStep() {
    final g = _current;
    final p = _placement;
    final err = _errors[g.id];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _chip(g.kind.label, KColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    g.display,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                g.status,
                if ((g.owner ?? '').isNotEmpty) 'owner ${g.owner}',
                if (g.dueIso != null) 'due ${g.dueIso}',
              ].join(' · '),
              style: const TextStyle(color: KColors.textMuted, fontSize: 11),
            ),
            if ((g.detail ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                g.detail!.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KColors.surface2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: KColors.amber.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${g.kind.linkVerb.toUpperCase()} …',
                        style: const TextStyle(
                          color: KColors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (p != null)
                        _chip(
                          switch (p.source) {
                            'ai' => 'AI placed',
                            'you' => 'your choice',
                            _ => 'engine guess',
                          },
                          p.source == 'ai'
                              ? KColors.phosphor
                              : KColors.textMuted,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PlanActivityPicker(
                    value: p?.activityId,
                    workPackages: _wps,
                    activities: _acts
                        .where((a) => a.parentActivityId == null)
                        .toList(),
                    label: 'Existing activity',
                    onChanged: (v) => setState(() {
                      _placements[g.id] = (p ?? const GapPlacement()).copyWith(
                        activityId: v,
                        clearActivity: v == null,
                        clearNew: v != null,
                        source: 'you',
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => setState(() => _newRowOpen = !_newRowOpen),
                    child: Row(
                      children: [
                        const Expanded(child: Divider(color: KColors.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _newRowOpen
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 14,
                                color: KColors.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _newRowOpen
                                    ? 'or a new row'
                                    : 'or a new row instead…',
                                style: const TextStyle(
                                  color: KColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Expanded(child: Divider(color: KColors.border)),
                      ],
                    ),
                  ),
                  if (_newRowOpen) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _newNameCtrl,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              labelText: 'New row name',
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() {
                              if (p?.isNew ?? false) {
                                _placements[g.id] = p!.copyWith(
                                  newName: v,
                                  source: 'you',
                                );
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: p?.isNew ?? false
                                ? p!.newWorkPackageId
                                : null,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'In work package',
                              isDense: true,
                            ),
                            items: [
                              for (final w in _wps)
                                DropdownMenuItem(
                                  value: w.id,
                                  child: Text(
                                    w.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              if (v == null) return;
                              _placements[g.id] = (p ?? const GapPlacement())
                                  .copyWith(
                                    newWorkPackageId: v,
                                    newName: _newNameCtrl.text.trim().isEmpty
                                        ? g.display
                                        : _newNameCtrl.text.trim(),
                                    newMonth: p?.newMonth ?? g.dueMonth,
                                    clearActivity: true,
                                    source: 'you',
                                  );
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: p?.newType ?? 'activity',
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'As a',
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'activity',
                                child: Text(
                                  'Activity',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'milestone',
                                child: Text(
                                  'Milestone',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'gate',
                                child: Text(
                                  'Gate',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              if (v == null) return;
                              _placements[g.id] = (p ?? const GapPlacement())
                                  .copyWith(
                                    newType: v,
                                    source: p?.isNew ?? false
                                        ? 'you'
                                        : p?.source,
                                  );
                            }),
                          ),
                        ),
                      ],
                    ),
                    if ((p?.isNew ?? false) && _month0 != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          p!.newMonth == null
                              ? 'No month: the row will be unscheduled until you place it.'
                              : 'A new ${p.newType} in ${replanMonthLabel(p.newMonth!, _month0!)}. '
                                    'The existing-activity choice above is cleared.',
                          style: const TextStyle(
                            color: KColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                  if (p != null && p.rationale.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      p.rationale,
                      style: const TextStyle(
                        color: KColors.textDim,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'The model could not place this one: $err',
                        style: const TextStyle(
                          color: KColors.amber,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneStep() {
    final total = _gaps.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total == 0
              ? 'Nothing to pull in.'
              : '$_accepted of $total linked${_skipped > 0 ? ', $_skipped skipped' : ''}.',
          style: const TextStyle(color: KColors.text, fontSize: 13),
        ),
        if (_accepted > 0) ...[
          const SizedBox(height: 8),
          const Text(
            'Linked items now show on their activity: actions underneath it, '
            'decisions and dependencies as arrows into it, risks as schedule '
            'drivers. The Gantt reloads when you close this.',
            style: TextStyle(
              color: KColors.textMuted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  static IconData _iconFor(GapKind k) => switch (k) {
    GapKind.action => Icons.task_alt_outlined,
    GapKind.decision => Icons.gavel_outlined,
    GapKind.dependency => Icons.link_outlined,
    GapKind.risk => Icons.warning_amber_outlined,
  };

  Widget _chip(String text, Color colour) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: colour.withValues(alpha: 0.4), width: 0.5),
    ),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: colour,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}
