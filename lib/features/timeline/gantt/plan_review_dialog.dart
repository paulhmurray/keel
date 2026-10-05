import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/llm/context_builder.dart';
import '../../../core/llm/llm_client.dart';
import '../../../core/llm/llm_client_factory.dart';
import '../../../core/plan/plan_review.dart';
import '../../../core/plan/replan.dart' show replanMonthLabel;
import '../../../providers/settings_provider.dart';
import '../../../shared/theme/keel_colors.dart';

/// "Review my plan": the graph checks as a list, then, with AI, one
/// card per suggestion. Accepting a reorder adds the arrow (Re-plan then
/// enforces it); accepting a missing step or milestone creates the row
/// in the named work package, just after what it follows, with arrows
/// to its neighbours. Nothing is written until accepted.
class PlanReviewDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;

  /// Tests pass a fake that answers with canned JSON.
  final LLMClient? client;

  const PlanReviewDialog({
    super.key,
    required this.db,
    required this.projectId,
    this.client,
  });

  @override
  State<PlanReviewDialog> createState() => _PlanReviewDialogState();
}

enum _Phase { loading, findings, asking, cards, done }

class _PlanReviewDialogState extends State<PlanReviewDialog> {
  _Phase _phase = _Phase.loading;
  List<TimelineActivity> _acts = const [];
  List<TimelineDependency> _deps = const [];
  List<TimelineWorkPackage> _wps = const [];
  ProgrammeHeader? _header;
  DateTime? _month0;
  List<PlanFinding> _findings = const [];
  List<PlanSuggestion> _suggestions = const [];
  String? _askError;
  int _index = 0;
  int _accepted = 0, _skipped = 0;
  bool _applying = false;
  bool _wrote = false;

  bool get _aiAvailable =>
      widget.client != null || context.watch<SettingsProvider>().hasApiKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dao = widget.db.programmeGanttDao;
    final pid = widget.projectId;
    _header = await dao.getHeader(pid);
    _acts = await dao.getActivitiesForProject(pid);
    _deps = await dao.getDependencies(pid);
    _wps = await dao.getWorkPackages(pid);
    if (!mounted) return;
    setState(() {
      _month0 = _header?.month0Date != null
          ? DateTime.tryParse(_header!.month0Date!)
          : null;
      _findings = checkPlan(
        activities: _acts,
        dependencies: _deps,
        workPackages: _wps,
        month0Date: _header?.month0Date,
        hardDeadlineDate: _header?.hardDeadlineDate,
      );
      _phase = _Phase.findings;
    });
  }

  Future<void> _ask() async {
    final settings = context.read<SettingsProvider>().settings;
    final client = widget.client ?? LLMClientFactory.fromSettings(settings);
    setState(() {
      _phase = _Phase.asking;
      _askError = null;
    });
    String projectContext = '';
    try {
      projectContext = await ContextBuilder(widget.db).buildSystemPrompt(
        widget.projectId,
        quarterAnchorMonth: settings.quarterAnchorMonth,
      );
    } catch (_) {}
    try {
      final prompt = planReviewPrompt(
        activities: _acts,
        dependencies: _deps,
        workPackages: _wps,
        month0: _month0,
        findings: _findings,
        projectContext: projectContext,
      );
      final raw = await client.complete(
        systemPrompt: prompt.system,
        userMessage: prompt.user,
        maxTokens: 1200,
      );
      final ids = _acts.map((a) => a.id).toSet();
      _suggestions = parsePlanSuggestions(
        raw,
        activityIds: ids,
        workPackageIds: _wps.map((w) => w.id).toSet(),
        dependencies: _deps,
      );
      if (!mounted) return;
      setState(() {
        _index = 0;
        _phase = _suggestions.isEmpty ? _Phase.done : _Phase.cards;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _askError = '$e';
        _phase = _Phase.findings;
      });
    }
  }

  PlanSuggestion get _current => _suggestions[_index];
  Map<String, TimelineActivity> get _byId => {for (final a in _acts) a.id: a};

  void _advance() {
    _index++;
    setState(() {
      if (_index >= _suggestions.length) _phase = _Phase.done;
    });
  }

  void _skip() {
    _skipped++;
    _advance();
  }

  Future<void> _accept() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      await _acceptInner();
    } finally {
      // A failure must never leave the buttons dead.
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _acceptInner() async {
    final s = _current;
    final dao = widget.db.programmeGanttDao;
    final pid = widget.projectId;
    final now = DateTime.now();
    const uuid = Uuid();

    Future<void> arrow(String from, String to) async {
      if (_deps.any((d) => d.fromActivityId == from && d.toActivityId == to))
        return;
      final id = uuid.v4();
      await dao.upsertDependency(
        TimelineDependenciesCompanion(
          id: Value(id),
          projectId: Value(pid),
          fromActivityId: Value(from),
          toActivityId: Value(to),
          dependencyType: const Value('finish_to_start'),
          notes: const Value('Added on plan review'),
        ),
      );
      _deps = [
        ..._deps,
        TimelineDependency(
          id: id,
          projectId: pid,
          fromActivityId: from,
          toActivityId: to,
          dependencyType: 'finish_to_start',
          notes: 'Added on plan review',
          createdAt: now,
        ),
      ];
    }

    if (s.kind == SuggestionKind.reorder) {
      // An arrow already pointing the other way is the usual reason the
      // order was flagged; keeping both would make a cycle.
      final reversed = _deps
          .where(
            (d) =>
                d.fromActivityId == s.beforeId && d.toActivityId == s.afterId,
          )
          .toList();
      for (final d in reversed) {
        await dao.deleteDependency(d.id);
      }
      _deps = _deps.where((d) => !reversed.contains(d)).toList();
      await arrow(s.afterId!, s.beforeId!);
    } else {
      final id = uuid.v4();
      final byId = _byId;
      final month = suggestedMonth(s, byId);
      final after = s.afterId != null ? byId[s.afterId!] : null;
      final siblings =
          _acts.where((a) => a.workPackageId == s.workPackageId).toList()
            ..sort((x, y) => x.sortOrder.compareTo(y.sortOrder));
      // Slot it just after what it follows when that row is in the same
      // package; otherwise at the end. Positions, not sortOrder values:
      // sort orders can have gaps, so an index built from them can fall
      // outside the list.
      var order = siblings.length;
      if (after != null && after.workPackageId == s.workPackageId) {
        final at = siblings.indexWhere((a) => a.id == after.id);
        if (at >= 0) order = at + 1;
      }
      await dao.upsertActivity(
        TimelineActivitiesCompanion(
          id: Value(id),
          workPackageId: Value(s.workPackageId!),
          projectId: Value(pid),
          name: Value(s.name!),
          activityType: Value(s.type),
          startMonth: Value(month),
          endMonth: Value(month),
          sortOrder: Value(order),
          notes: Value(
            'Added on plan review ${now.toIso8601String().substring(0, 10)}: ${s.message}',
          ),
          updatedAt: Value(now),
        ),
      );
      if (after != null && after.workPackageId == s.workPackageId) {
        final ordered = siblings.map((a) => a.id).toList()..insert(order, id);
        await dao.reorderActivitiesWithinWp(s.workPackageId!, ordered);
      }
      // Reordering renumbers siblings, so refresh rather than append.
      _acts = await dao.getActivitiesForProject(pid);
      if (s.afterId != null) await arrow(s.afterId!, id);
      if (s.beforeId != null) await arrow(id, s.beforeId!);
    }
    _accepted++;
    _wrote = true;
    if (!mounted) return;
    _advance();
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Row(
        children: [
          const Icon(Icons.fact_check_outlined, size: 16, color: KColors.amber),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Review my plan',
              style: TextStyle(color: KColors.text, fontSize: 14),
            ),
          ),
          if (_phase == _Phase.cards)
            Text(
              '${_index + 1} of ${_suggestions.length}',
              style: const TextStyle(color: KColors.textMuted, fontSize: 11),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: KColors.textMuted),
            tooltip: _phase == _Phase.cards
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
          _Phase.findings => _findingsStep(),
          _Phase.asking => _askingStep(),
          _Phase.cards => _cardStep(),
          _Phase.done => _doneStep(),
        },
      ),
      actions: switch (_phase) {
        _Phase.loading || _Phase.asking => const [],
        _Phase.findings => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_wrote),
            child: const Text('Close'),
          ),
          if (_aiAvailable && _acts.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _ask,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: const Text('Ask AI to review the whole plan'),
            ),
        ],
        _Phase.cards => [
          TextButton(
            onPressed: _applying ? null : _skip,
            child: const Text('Skip'),
          ),
          ElevatedButton.icon(
            onPressed: _applying ? null : _accept,
            icon: const Icon(Icons.check, size: 14),
            label: Text(
              _current.kind == SuggestionKind.reorder
                  ? 'Add the arrow'
                  : _current.kind == SuggestionKind.point
                  ? 'Add the ${_current.type}'
                  : 'Add the activity',
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

  Widget _findingsStep() {
    final warns = _findings
        .where((f) => f.severity == FindingSeverity.warn)
        .length;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'First the facts the plan itself gives away: arrows pointing '
              'backwards in time, work nothing connects to, milestones '
              'nothing leads to, work packages with no end point. Then, if '
              'you ask, the model reads the whole breakdown and says what it '
              'would reorder, add or mark as a milestone — each as a card '
              'you accept or skip.',
              style: TextStyle(
                color: KColors.textDim,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            if (_findings.isEmpty)
              const Text(
                'Nothing to flag. Arrows run forward, every milestone '
                'has work leading to it, every package has an end point.',
                style: TextStyle(color: KColors.phosphor, fontSize: 13),
              )
            else ...[
              Text(
                '${_findings.length} ${_findings.length == 1 ? 'finding' : 'findings'}'
                '${warns > 0 ? ', $warns worth fixing' : ''}',
                style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              for (final f in _findings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        f.severity == FindingSeverity.warn
                            ? Icons.warning_amber_outlined
                            : Icons.info_outline,
                        size: 14,
                        color: f.severity == FindingSeverity.warn
                            ? KColors.red
                            : KColors.textDim,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.message,
                          style: TextStyle(
                            color: f.severity == FindingSeverity.warn
                                ? KColors.text
                                : KColors.textDim,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (_askError != null) ...[
              const SizedBox(height: 10),
              Text(
                'The model could not review the plan: $_askError',
                style: const TextStyle(color: KColors.amber, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _askingStep() => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(height: 12),
      LinearProgressIndicator(
        color: KColors.phosphor,
        backgroundColor: KColors.surface2,
      ),
      SizedBox(height: 12),
      Text(
        'Reading the whole plan… one call, so this takes as long as the '
        'model takes.',
        style: TextStyle(color: KColors.textDim, fontSize: 12),
      ),
      SizedBox(height: 12),
    ],
  );

  Widget _cardStep() {
    final s = _current;
    final byId = _byId;
    final after = s.afterId != null ? byId[s.afterId!] : null;
    final before = s.beforeId != null ? byId[s.beforeId!] : null;
    final wp = s.workPackageId != null
        ? _wps.where((w) => w.id == s.workPackageId).firstOrNull
        : null;
    final month = s.createsRow ? suggestedMonth(s, byId) : null;
    final (label, colour) = switch (s.kind) {
      SuggestionKind.reorder => ('ORDER', KColors.amber),
      SuggestionKind.missing => ('MISSING STEP', KColors.blue),
      SuggestionKind.point => ('MILESTONE', KColors.phosphor),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _chip(label, colour),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.kind == SuggestionKind.reorder
                    ? '${after?.name ?? '?'} should finish before ${before?.name ?? '?'} starts'
                    : s.name!,
                style: const TextStyle(
                  color: KColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          s.message,
          style: const TextStyle(
            color: KColors.text,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KColors.surface2,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: KColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ACCEPTING DOES THIS',
                style: TextStyle(
                  color: KColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              if (s.kind == SuggestionKind.reorder)
                Text(
                  'Adds a finish → start arrow from ${after?.name ?? '?'} to '
                  '${before?.name ?? '?'}'
                  '${_deps.any((d) => d.fromActivityId == s.beforeId && d.toActivityId == s.afterId) ? ', replacing the arrow that currently points the other way' : ''}. '
                  'Dates do not change now; Re-plan will push '
                  '${before?.name ?? 'it'} if the arrow is violated.',
                  style: const TextStyle(
                    color: KColors.textDim,
                    fontSize: 12,
                    height: 1.4,
                  ),
                )
              else
                Text(
                  'Creates "${s.name}" as ${s.type == 'activity' ? 'an activity' : 'a ${s.type}'} '
                  'in ${wp?.name ?? 'the work package'}'
                  '${month != null && _month0 != null ? ', in ${replanMonthLabel(month, _month0!)}' : ', unscheduled'}'
                  '${after != null ? ', after ${after.name}' : ''}'
                  '${before != null ? ', before ${before.name}' : ''}'
                  '${after != null || before != null ? ', with the arrows to match' : ''}.',
                  style: const TextStyle(
                    color: KColors.textDim,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _doneStep() {
    final total = _suggestions.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total == 0
              ? 'The model had nothing to add. The plan reads as sound.'
              : '$_accepted of $total applied${_skipped > 0 ? ', $_skipped skipped' : ''}.',
          style: const TextStyle(color: KColors.text, fontSize: 13),
        ),
        if (_accepted > 0) ...[
          const SizedBox(height: 8),
          const Text(
            'New rows carry a note saying why they were added. Run Re-plan '
            'to settle the dates around any new arrows. The Gantt reloads '
            'when you close this.',
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

  Widget _chip(String text, Color colour) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: colour.withValues(alpha: 0.4), width: 0.5),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: colour,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}
