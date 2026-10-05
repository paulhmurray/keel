import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/llm/context_builder.dart';
import '../../../core/llm/llm_client.dart';
import '../../../core/llm/llm_client_factory.dart';
import '../../../core/plan/replan.dart';
import '../../../core/plan/replan_assist.dart';
import '../../../core/plan/variance_links.dart';
import '../../../providers/settings_provider.dart';
import '../../../shared/theme/keel_colors.dart';
import '../../../shared/widgets/date_picker_field.dart';

/// "Re-plan slipped work": every not-started activity whose start has
/// passed is slid forward to today, the consequences pushed through the
/// dependency arrows, and the PM walks the moves one card at a time —
/// current span on the left, proposed on the right, the reasons and any
/// collisions underneath. Accept writes that row (months, dates, a
/// history note); Skip leaves it. Stopping halfway keeps what was
/// accepted. The arithmetic lives in core/plan/replan.dart; the optional
/// AI pass (core/plan/replan_assist.dart) only judges duration and
/// writes the rationale — an accepted extension re-runs the engine so
/// the successors move with it.
class ReplanDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;

  /// The model to ask. Defaults to the one configured in Settings; tests
  /// pass a fake that answers with canned JSON.
  final LLMClient? client;

  const ReplanDialog({
    super.key,
    required this.db,
    required this.projectId,
    this.client,
  });

  @override
  State<ReplanDialog> createState() => _ReplanDialogState();
}

enum _Phase { loading, scope, advising, review, done }

class _ReplanDialogState extends State<ReplanDialog> {
  _Phase _phase = _Phase.loading;
  ReplanProposal? _proposal;
  DateTime? _month0;
  bool _hasBaseline = false;
  bool _setBaselineFirst = true;
  int _index = 0;
  int _accepted = 0, _skipped = 0;
  final _skippedIds = <String>{};
  bool _applying = false;
  bool _wrote = false;

  // Inputs kept so the proposal can be rebuilt after an accepted
  // extension without another round trip.
  List<TimelineActivity> _acts = const [];
  List<TimelineDependency> _deps = const [];
  ProgrammeHeader? _header;
  final Map<String, ReplanExtension> _extensions = {};
  final Map<String, ReplanOverride> _overrides = {};

  // Inline editor for the proposed span on the current card.
  bool _editing = false;
  int? _editStartMonth, _editEndMonth;
  String? _editStartDate, _editEndDate;

  // AI pass.
  final Map<String, ReplanAdvice> _advice = {};
  final Map<String, String> _adviceErrors = {};
  int _advised = 0, _toAdvise = 0;
  bool _cancelled = false;
  bool _useExtension = false;

  // Sub-task suggestions for the current card.
  List<SuggestedTask> _subtasks = const [];
  final Set<int> _subtaskPicked = {};
  bool _subtasksLoading = false;
  String? _subtaskError;
  Set<String> _parentsWithTasks = const {};
  int _tasksAdded = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _load() async {
    final dao = widget.db.programmeGanttDao;
    final pid = widget.projectId;
    _header = await dao.getHeader(pid);
    _acts = await dao.getActivitiesForProject(pid);
    _deps = await dao.getDependencies(pid);
    if (!mounted) return;
    setState(() {
      _proposal = _build();
      _month0 = _header?.month0Date != null
          ? DateTime.tryParse(_header!.month0Date!)
          : null;
      _hasBaseline = _acts.any((a) => a.isBaseline);
      _setBaselineFirst = !_hasBaseline;
      _parentsWithTasks = {
        for (final a in _acts)
          if (a.parentActivityId != null) a.parentActivityId!,
      };
      _phase = _Phase.scope;
    });
  }

  /// Sub-tasks are offered for a top-level activity with none yet (the
  /// WBS stops at activity → task), never for milestones or gates.
  bool _canSuggestSubtasks(ReplanChange c) =>
      c.activity.parentActivityId == null &&
      !c.isSinglePoint &&
      !_parentsWithTasks.contains(c.id);

  Future<void> _suggestSubtasks() async {
    final c = _current;
    final settings = context.read<SettingsProvider>().settings;
    final client = widget.client ?? LLMClientFactory.fromSettings(settings);
    setState(() {
      _subtasksLoading = true;
      _subtaskError = null;
    });
    try {
      final wps = await widget.db.programmeGanttDao.getWorkPackages(
        widget.projectId,
      );
      final wpName = {for (final w in wps) w.id: w.name};
      String projectContext = '';
      try {
        projectContext = await ContextBuilder(widget.db).buildSystemPrompt(
          widget.projectId,
          quarterAnchorMonth: settings.quarterAnchorMonth,
        );
      } catch (_) {}
      final prompt = replanSubtaskPrompt(
        change: c,
        month0: _month0!,
        workPackageName: wpName[c.activity.workPackageId],
        linkedItems: await _linkedItems(c.activity),
        projectContext: projectContext,
      );
      final raw = await client.complete(
        systemPrompt: prompt.system,
        userMessage: prompt.user,
        maxTokens: 500,
      );
      final tasks = parseReplanSubtasks(raw);
      if (!mounted) return;
      setState(() {
        _subtasks = tasks;
        _subtaskPicked
          ..clear()
          ..addAll(List.generate(tasks.length, (i) => i));
        _subtaskError = tasks.isEmpty ? 'No usable breakdown came back.' : null;
      });
    } catch (e) {
      if (mounted) setState(() => _subtaskError = '$e');
    } finally {
      if (mounted) setState(() => _subtasksLoading = false);
    }
  }

  /// The slices the picked tasks would get, over the card's proposed
  /// window (with the AI extension if it is switched on).
  List<TaskSpan> _subtaskSpans(ReplanChange c) {
    final picked = [
      for (var i = 0; i < _subtasks.length; i++)
        if (_subtaskPicked.contains(i)) _subtasks[i].weight,
    ];
    var endMonth = c.toEndMonth;
    var endDate = c.toEndDate;
    final advice = _advice[c.id];
    if (_useExtension && advice != null && !advice.agrees) {
      // Preview with the extension applied, same as accept would.
      final preview = buildReplanProposal(
        activities: _acts,
        dependencies: _deps,
        month0Date: _header?.month0Date,
        hardDeadlineDate: _header?.hardDeadlineDate,
        extensions: {..._extensions, c.id: advice.extension},
        overrides: _overrides,
      ).changeFor(c.id);
      endMonth = preview?.toEndMonth ?? endMonth;
      endDate = preview?.toEndDate ?? endDate;
    }
    return partitionSpan(
      startMonth: c.toStartMonth,
      endMonth: endMonth,
      startDate: c.toStartDate,
      endDate: endDate,
      weights: picked,
      month0: _month0!,
    );
  }

  ReplanProposal _build() => buildReplanProposal(
    activities: _acts,
    dependencies: _deps,
    month0Date: _header?.month0Date,
    hardDeadlineDate: _header?.hardDeadlineDate,
    extensions: _extensions,
    overrides: _overrides,
  );

  // ── AI pass ──────────────────────────────────────────────────────────

  /// Asks the model about each slipped row (pushed rows are mechanical).
  /// Failures degrade to engine-only cards; nothing here writes.
  Future<void> _advise() async {
    final settings = context.read<SettingsProvider>().settings;
    final client = widget.client ?? LLMClientFactory.fromSettings(settings);
    final slipped = _changes.where((c) => c.slipped).toList();
    setState(() {
      _toAdvise = slipped.length;
      _advised = 0;
      _phase = _Phase.advising;
    });
    final wps = await widget.db.programmeGanttDao.getWorkPackages(
      widget.projectId,
    );
    final wpName = {for (final w in wps) w.id: w.name};
    final actName = {for (final a in _acts) a.id: a.name};
    String projectContext = '';
    try {
      projectContext = await ContextBuilder(widget.db).buildSystemPrompt(
        widget.projectId,
        quarterAnchorMonth: settings.quarterAnchorMonth,
      );
    } catch (_) {}
    for (final c in slipped) {
      if (_cancelled || !mounted) return;
      try {
        final prompt = replanAssistPrompt(
          change: c,
          month0: _month0!,
          workPackageName: wpName[c.activity.workPackageId],
          predecessors: [
            for (final d in _deps)
              if (d.toActivityId == c.id)
                '${d.dependencyType == 'external' ? (d.externalLabel ?? 'external') : (actName[d.fromActivityId] ?? '?')} (${d.dependencyType.replaceAll('_', ' ')})',
          ],
          successors: [
            for (final d in _deps)
              if (d.fromActivityId == c.id)
                '${actName[d.toActivityId] ?? '?'} (${d.dependencyType.replaceAll('_', ' ')})',
          ],
          linkedItems: await _linkedItems(c.activity),
          openActions: (await widget.db.actionsDao.getActionsForActivity(
            c.id,
          )).where((a) => a.status != 'closed').length,
          projectContext: projectContext,
        );
        final raw = await client.complete(
          systemPrompt: prompt.system,
          userMessage: prompt.user,
          maxTokens: 400,
        );
        final advice = parseReplanAdvice(raw, dated: c.toEndDate != null);
        if (advice == null) {
          _adviceErrors[c.id] = 'No usable answer';
        } else {
          _advice[c.id] = advice;
        }
      } catch (e) {
        _adviceErrors[c.id] = '$e';
      }
      if (!mounted) return;
      setState(() => _advised++);
    }
    if (!mounted) return;
    _start();
  }

  /// "R3 Vendor slips — open" for each RAID item tied to the row's
  /// schedule variance.
  Future<List<String>> _linkedItems(TimelineActivity a) async {
    final links = effectiveVarianceLinks(
      linksJson: a.varianceRaidLinksJson,
      legacyType: a.varianceRaidType,
      legacyId: a.varianceRaidId,
    );
    final dao = widget.db.raidDao;
    final out = <String>[];
    for (final l in links) {
      String? line;
      switch (l.type) {
        case 'risk':
          final r = await dao.getRiskById(l.id);
          if (r != null) {
            line =
                '${r.ref ?? 'Risk'} ${r.title ?? r.description} — ${r.status}, ${r.likelihood}/${r.impact}';
          }
        case 'issue':
          final i = await dao.getIssueById(l.id);
          if (i != null) {
            line =
                '${i.ref ?? 'Issue'} ${i.title ?? i.description} — ${i.status}';
          }
        case 'assumption':
          final x = await dao.getAssumptionById(l.id);
          if (x != null) {
            line = '${x.ref ?? 'Assumption'} ${x.description} — ${x.status}';
          }
        case 'dependency':
          final d = await dao.getDependencyById(l.id);
          if (d != null) {
            line = '${d.ref ?? 'Dependency'} ${d.description} — ${d.status}';
          }
      }
      if (line != null) out.add(line);
    }
    return out;
  }

  /// A supplied client is usable by definition; otherwise it depends on
  /// what Settings has configured.
  bool get _aiAvailable =>
      widget.client != null || context.watch<SettingsProvider>().hasApiKey;

  List<ReplanChange> get _changes => _proposal?.changes ?? const [];
  ReplanChange get _current => _changes[_index];

  List<ReplanWarning> _warningsFor(String id) =>
      (_proposal?.warnings ?? const [])
          .where((w) => w.activityId == id)
          .toList();

  void _start() {
    setState(() {
      _index = 0;
      _phase = _changes.isEmpty ? _Phase.done : _Phase.review;
      _loadCard();
    });
  }

  /// The extension toggle defaults on when the model is at least fairly
  /// sure; a low-confidence suggestion is shown but left to the PM.
  void _loadCard() {
    if (_index >= _changes.length) return;
    final a = _advice[_current.id];
    _useExtension = a != null && !a.agrees && a.confidence != 'low';
    _subtasks = const [];
    _subtaskPicked.clear();
    _subtaskError = null;
    _editing = false;
  }

  void _beginEdit(ReplanChange c) {
    setState(() {
      _editing = true;
      _editStartMonth = c.toStartMonth;
      _editEndMonth = c.toEndMonth;
      _editStartDate = c.toStartDate;
      _editEndDate = c.toEndDate;
    });
  }

  /// Pins the row at the edited span and rebuilds so later cards follow.
  void _commitEdit(ReplanChange c) {
    final dated = c.toStartDate != null;
    if (dated) {
      if (_editStartDate == null) return;
      if (_editEndDate != null &&
          _editEndDate!.compareTo(_editStartDate!) < 0) {
        _editEndDate = _editStartDate;
      }
      _overrides[c.id] = ReplanOverride(
        startDate: _editStartDate,
        endDate: _editEndDate,
        endMonth: _editEndDate == null ? c.toEndMonth : null,
      );
    } else {
      if (_editStartMonth == null) return;
      var end = _editEndMonth ?? _editStartMonth!;
      if (end < _editStartMonth!) end = _editStartMonth!;
      _overrides[c.id] = ReplanOverride(
        startMonth: _editStartMonth,
        endMonth: end,
      );
    }
    setState(() {
      _editing = false;
      _proposal = _build();
      final i = _changes.indexWhere((x) => x.id == c.id);
      if (i >= 0) _index = i;
    });
  }

  void _clearEdit(ReplanChange c) {
    setState(() {
      _editing = false;
      _overrides.remove(c.id);
      _proposal = _build();
      final i = _changes.indexWhere((x) => x.id == c.id);
      if (i >= 0) _index = i;
    });
  }

  /// Month choices around the proposal: a year back, three ahead.
  List<DropdownMenuItem<int>> _monthItems(int around) => [
    for (var m = around - 12; m <= around + 36; m++)
      DropdownMenuItem(
        value: m,
        child: Text(
          replanMonthLabel(m, _month0!),
          style: const TextStyle(fontSize: 12),
        ),
      ),
  ];

  Widget _proposedBox(ReplanChange c, String to) {
    if (!_editing) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KColors.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.pinned ? KColors.amber : KColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  c.pinned ? 'PROPOSED · SET BY YOU' : 'PROPOSED',
                  style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 20,
                  width: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    tooltip: 'Edit the proposed dates',
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: KColors.textDim,
                    ),
                    onPressed: () => _beginEdit(c),
                  ),
                ),
                if (c.pinned)
                  SizedBox(
                    height: 20,
                    width: 24,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      tooltip: "Back to the engine's proposal",
                      icon: const Icon(Icons.undo, color: KColors.textDim),
                      onPressed: () => _clearEdit(c),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              to,
              style: const TextStyle(
                color: KColors.amber,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    final dated = c.toStartDate != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColors.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KColors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PROPOSED · EDITING',
            style: TextStyle(
              color: KColors.amber,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          if (dated) ...[
            DatePickerField(
              label: 'Start',
              isoValue: _editStartDate,
              required: true,
              onChanged: (v) => setState(() => _editStartDate = v),
            ),
            const SizedBox(height: 6),
            DatePickerField(
              label: 'End',
              isoValue: _editEndDate,
              onChanged: (v) => setState(() => _editEndDate = v),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _editStartMonth,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Start',
                      isDense: true,
                    ),
                    items: _monthItems(c.toStartMonth ?? 0),
                    onChanged: (v) => setState(() => _editStartMonth = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _editEndMonth,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'End',
                      isDense: true,
                    ),
                    items: _monthItems(c.toEndMonth ?? c.toStartMonth ?? 0),
                    onChanged: (v) => setState(() => _editEndMonth = v),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _editing = false),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: () => _commitEdit(c),
                child: const Text(
                  'Use these dates',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Snapshots the baseline once, just before the first write, so a
  /// cancelled review leaves no empty baseline behind.
  Future<void> _baselineIfAsked() async {
    if (!_setBaselineFirst || _hasBaseline) return;
    await widget.db.programmeGanttDao.setBaseline(widget.projectId);
    _hasBaseline = true;
    _wrote = true;
  }

  void _advance() {
    _index++;
    setState(() {
      if (_index >= _changes.length) {
        _phase = _Phase.done;
      } else {
        _loadCard();
      }
    });
  }

  /// Folds an accepted extension into the engine and rebuilds. Changes
  /// are in dependency order, so only rows after the current one can
  /// differ; the current row is re-found by id.
  void _applyExtension(ReplanChange c, ReplanExtension e) {
    _extensions[c.id] = e;
    _proposal = _build();
    final i = _changes.indexWhere((x) => x.id == c.id);
    if (i >= 0) _index = i;
  }

  ReplanWrite _writeFor(ReplanChange c) {
    final a = _advice[c.id];
    final aiView = a == null || a.rationale.isEmpty
        ? null
        : 'AI view (${a.confidence} confidence): ${a.rationale}'
              '${a.watch.isEmpty ? '' : ' Watch: ${a.watch.join('; ')}.'}';
    return ReplanWrite(
      id: c.id,
      startMonth: c.toStartMonth,
      endMonth: c.toEndMonth,
      startDate: c.toStartDate,
      endDate: c.toEndDate,
      note: _month0 == null ? null : replanNote(c, _month0!, aiView: aiView),
    );
  }

  /// Writes the current card exactly as shown: the move (with the AI
  /// extension if switched on) and any ticked sub-tasks.
  Future<void> _writeCurrent() async {
    final advice = _advice[_current.id];
    if (_useExtension && advice != null && !advice.agrees) {
      _applyExtension(_current, advice.extension);
    }
    await _baselineIfAsked();
    await widget.db.programmeGanttDao.applyReplan([_writeFor(_current)]);
    _accepted++;
    _wrote = true;
    if (_subtasks.isNotEmpty && _subtaskPicked.isNotEmpty) {
      final c = _current;
      final spans = _subtaskSpans(c);
      final picked = [
        for (var i = 0; i < _subtasks.length; i++)
          if (_subtaskPicked.contains(i)) _subtasks[i],
      ];
      const uuid = Uuid();
      final planned = [
        for (var i = 0; i < picked.length; i++)
          PlannedTask(
            id: uuid.v4(),
            name: picked[i].name,
            startMonth: spans[i].startMonth,
            endMonth: spans[i].endMonth,
            startDate: spans[i].startDate,
            endDate: spans[i].endDate,
          ),
      ];
      await widget.db.programmeGanttDao.addPlannedTasks(c.id, planned);
      _tasksAdded += planned.length;
      _parentsWithTasks = {..._parentsWithTasks, c.id};
    }
  }

  Future<void> _accept() async {
    if (_applying) return;
    setState(() => _applying = true);
    await _writeCurrent();
    if (!mounted) return;
    setState(() => _applying = false);
    _advance();
  }

  /// The current card goes through the same path as Accept, so its
  /// extension toggle and ticked sub-tasks are honoured; the rest are
  /// written as the engine proposes.
  Future<void> _acceptRemaining() async {
    if (_applying) return;
    setState(() => _applying = true);
    await _writeCurrent();
    final rest = _changes.sublist(_index + 1);
    if (rest.isNotEmpty) {
      await widget.db.programmeGanttDao.applyReplan(
        rest.map(_writeFor).toList(),
      );
      _accepted += rest.length;
    }
    if (!mounted) return;
    setState(() {
      _applying = false;
      _index = _changes.length;
      _phase = _Phase.done;
    });
  }

  void _skip() {
    _skipped++;
    _skippedIds.add(_current.id);
    _advance();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Row(
        children: [
          const Icon(Icons.update, size: 16, color: KColors.amber),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Re-plan slipped work',
              style: TextStyle(color: KColors.text, fontSize: 14),
            ),
          ),
          if (_phase == _Phase.review)
            Text(
              '${_index + 1} of ${_changes.length}',
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
          _Phase.advising => _advisingStep(),
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
          if (_aiAvailable && _proposal != null && _proposal!.slippedCount > 0)
            OutlinedButton.icon(
              onPressed: _advise,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: const Text('Ask AI, then review'),
            ),
          ElevatedButton.icon(
            onPressed: _changes.isEmpty ? null : _start,
            icon: const Icon(Icons.rule, size: 14),
            label: Text(
              _changes.length == 1
                  ? 'Review the move'
                  : 'Review ${_changes.length} moves',
            ),
          ),
        ],
        _Phase.advising => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
        _Phase.review => [
          if (_changes.length - _index > 1)
            TextButton(
              onPressed: _applying ? null : _acceptRemaining,
              child: Text('Accept all ${_changes.length - _index}'),
            ),
          TextButton(
            onPressed: _applying ? null : _skip,
            child: const Text('Skip'),
          ),
          ElevatedButton.icon(
            onPressed: _applying ? null : _accept,
            icon: const Icon(Icons.check, size: 14),
            label: Text(
              _subtaskPicked.isEmpty
                  ? 'Accept'
                  : 'Accept + ${_subtaskPicked.length} '
                        '${_subtaskPicked.length == 1 ? 'task' : 'tasks'}',
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

  // ── Steps ────────────────────────────────────────────────────────────

  Widget _scopeStep() {
    final p = _proposal!;
    final general = p.warnings.where((w) => w.activityId.isEmpty).toList();
    final collisions = p.warnings
        .where((w) => w.activityId.isNotEmpty)
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Work that has not started but whose start date has passed is '
          'slid forward to today, keeping its duration. Anything it gates '
          'through a dependency arrow moves with it. Started and complete '
          'work never moves; a clash with it is reported instead. You '
          'review each move and nothing is written until you accept it. '
          'Each accepted row keeps a note of what it was and why it moved. '
          'With AI on, the model is asked whether each slipped activity '
          'still fits its duration — it never sets dates itself.',
          style: TextStyle(color: KColors.textDim, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        if (general.isNotEmpty)
          for (final w in general) _warningLine(w.message, KColors.red)
        else if (p.isEmpty)
          const Text(
            'Nothing has slipped. Every not-started activity still '
            'starts this month or later.',
            style: TextStyle(color: KColors.phosphor, fontSize: 13),
          )
        else ...[
          _countLine(
            Icons.history,
            '${p.slippedCount} '
            '${p.slippedCount == 1 ? 'activity has' : 'activities have'} '
            'slipped past today.',
          ),
          if (p.pushedCount > 0)
            _countLine(
              Icons.arrow_forward,
              '${p.pushedCount} more ${p.pushedCount == 1 ? 'is' : 'are'} '
              'pushed by them through dependencies.',
            ),
          if (collisions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${collisions.length} ${collisions.length == 1 ? 'thing' : 'things'} to watch',
              style: const TextStyle(
                color: KColors.red,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final w in collisions)
                    _warningLine(w.message, KColors.red),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (!_hasBaseline)
            CheckboxListTile(
              value: _setBaselineFirst,
              onChanged: (v) => setState(() => _setBaselineFirst = v ?? true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Set a baseline first so the Gantt shows what moved',
                style: TextStyle(color: KColors.text, fontSize: 13),
              ),
              subtitle: const Text(
                'Snapshots the plan as it is now. Ghost bars then show the '
                'original dates beside the re-planned ones.',
                style: TextStyle(color: KColors.textMuted, fontSize: 11),
              ),
            )
          else
            const Text(
              'The existing baseline is kept, so the Gantt will show the '
              'variance these moves create.',
              style: TextStyle(color: KColors.textMuted, fontSize: 11),
            ),
        ],
      ],
    );
  }

  Widget _advisingStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: _toAdvise == 0 ? 0 : _advised / _toAdvise,
          color: KColors.phosphor,
          backgroundColor: KColors.surface2,
        ),
        const SizedBox(height: 12),
        Text(
          'Asking about $_advised of $_toAdvise slipped '
          '${_toAdvise == 1 ? 'activity' : 'activities'}…',
          style: const TextStyle(color: KColors.textDim, fontSize: 12),
        ),
        if (_adviceErrors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_adviceErrors.length} could not be judged; those cards '
              'show the engine\'s move only.',
              style: const TextStyle(color: KColors.amber, fontSize: 11),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _subtaskPanel(ReplanChange c) {
    if (!_canSuggestSubtasks(c) || !_aiAvailable) {
      return const SizedBox.shrink();
    }
    if (_subtasks.isEmpty && !_subtasksLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: _suggestSubtasks,
              icon: const Icon(Icons.account_tree_outlined, size: 14),
              label: const Text('Suggest sub-tasks'),
            ),
            if (_subtaskError != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _subtaskError!,
                  style: const TextStyle(color: KColors.amber, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      );
    }
    if (_subtasksLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            SizedBox(width: 10),
            Text(
              'Breaking the activity down…',
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
          ],
        ),
      );
    }
    final spans = _subtaskSpans(c);
    var spanIdx = 0;
    return Container(
      margin: const EdgeInsets.only(top: 12),
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
            'SUGGESTED SUB-TASKS',
            style: TextStyle(
              color: KColors.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ticked tasks are created under this activity when you accept, '
            'sliced across its new window in this order.',
            style: TextStyle(color: KColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _subtasks.length; i++)
            Builder(
              builder: (_) {
                final picked = _subtaskPicked.contains(i);
                final span = picked && spanIdx < spans.length
                    ? spans[spanIdx++]
                    : null;
                return CheckboxListTile(
                  value: picked,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _subtaskPicked.add(i);
                    } else {
                      _subtaskPicked.remove(i);
                    }
                  }),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    _subtasks[i].name,
                    style: const TextStyle(color: KColors.text, fontSize: 12),
                  ),
                  subtitle: span == null
                      ? null
                      : Text(
                          replanSpanLabel(
                            startMonth: span.startMonth,
                            endMonth: span.endMonth,
                            startDate: span.startDate,
                            endDate: span.endDate,
                            month0: _month0!,
                          ),
                          style: const TextStyle(
                            color: KColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _aiPanel(ReplanChange c) {
    final a = _advice[c.id];
    final err = _adviceErrors[c.id];
    if (a == null && err == null) return const SizedBox.shrink();
    final dated = c.toEndDate != null;
    final extraLabel = a == null
        ? ''
        : dated
        ? '${a.extension.days} day${a.extension.days == 1 ? '' : 's'}'
        : '${a.extension.months} month${a.extension.months == 1 ? '' : 's'}';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColors.phosphor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KColors.phosphor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 13, color: KColors.phosphor),
              const SizedBox(width: 6),
              const Text(
                'AI VIEW',
                style: TextStyle(
                  color: KColors.phosphor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              if (a != null) ...[
                const SizedBox(width: 8),
                _chip('${a.confidence} confidence', KColors.textMuted),
                _chip(
                  a.agrees ? 'duration holds' : '+$extraLabel suggested',
                  a.agrees ? KColors.phosphor : KColors.amber,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (err != null)
            Text(
              'Could not judge this one: $err',
              style: const TextStyle(color: KColors.textMuted, fontSize: 11),
            )
          else ...[
            if (a!.rationale.isNotEmpty)
              Text(
                a.rationale,
                style: const TextStyle(
                  color: KColors.text,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            for (final w in a.watch)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '• Watch: $w',
                  style: const TextStyle(color: KColors.textDim, fontSize: 11),
                ),
              ),
            if (!a.agrees)
              CheckboxListTile(
                value: _useExtension,
                onChanged: (v) => setState(() => _useExtension = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Add $extraLabel to the end. Anything this gates moves with it.',
                  style: const TextStyle(color: KColors.text, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final c = _current;
    final m0 = _month0!;
    final from = replanSpanLabel(
      startMonth: c.fromStartMonth,
      endMonth: c.fromEndMonth,
      startDate: c.fromStartDate,
      endDate: c.fromEndDate,
      month0: m0,
    );
    final to = replanSpanLabel(
      startMonth: c.toStartMonth,
      endMonth: c.toEndMonth,
      startDate: c.toStartDate,
      endDate: c.toEndDate,
      month0: m0,
    );
    final warnings = _warningsFor(c.id);
    final skippedPushers = c.pushedBy.where(_skippedIds.contains).toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (c.isSinglePoint)
                  _chip(
                    c.activity.activityType.replaceAll('_', ' '),
                    KColors.red,
                  ),
                if (c.isCritical) _chip('critical path', KColors.red),
                _chip(
                  c.slipped ? 'slipped' : 'pushed',
                  c.slipped ? KColors.amber : KColors.blue,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _spanBox('CURRENT', from, KColors.textDim)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: KColors.textMuted,
                  ),
                ),
                Expanded(child: _proposedBox(c, to)),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'WHY',
              style: TextStyle(
                color: KColors.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            for (final r in c.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '• $r',
                  style: const TextStyle(
                    color: KColors.text,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            if (skippedPushers.isNotEmpty)
              _warningLine(
                'You skipped ${skippedPushers.length == 1 ? 'the activity' : 'activities'} '
                'that pushed this one, so the dependency will stay inconsistent '
                'if you accept this move.',
                KColors.amber,
              ),
            for (final w in warnings) _warningLine(w.message, KColors.red),
            _aiPanel(c),
            _subtaskPanel(c),
            if ((c.activity.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'NOTES',
                style: TextStyle(
                  color: KColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                c.activity.notes!.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _doneStep() {
    final total = _changes.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total == 0
              ? 'Nothing to re-plan.'
              : '$_accepted of $total ${total == 1 ? 'move' : 'moves'} applied'
                    '${_skipped > 0 ? ', $_skipped skipped' : ''}.',
          style: const TextStyle(color: KColors.text, fontSize: 13),
        ),
        if (_tasksAdded > 0) ...[
          const SizedBox(height: 4),
          Text(
            '$_tasksAdded ${_tasksAdded == 1 ? 'sub-task' : 'sub-tasks'} added.',
            style: const TextStyle(color: KColors.text, fontSize: 13),
          ),
        ],
        if (_accepted > 0) ...[
          const SizedBox(height: 8),
          const Text(
            'Each re-planned row carries a note with its old dates and the '
            'reason. The Gantt reloads when you close this.',
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

  // ── Bits ─────────────────────────────────────────────────────────────

  Widget _spanBox(String label, String span, Color colour) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: KColors.surface2,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: KColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colour,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          span,
          style: TextStyle(
            color: colour == KColors.textDim ? KColors.text : colour,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _chip(String text, Color colour) => Container(
    margin: const EdgeInsets.only(left: 6),
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

  Widget _countLine(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(icon, size: 14, color: KColors.amber),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: KColors.text, fontSize: 13),
          ),
        ),
      ],
    ),
  );

  Widget _warningLine(String text, Color colour) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_outlined, size: 14, color: colour),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: colour, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    ),
  );
}
