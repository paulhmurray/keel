import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/database/database.dart';
import '../../core/helm/day_plan_logic.dart';
import '../../shared/theme/keel_colors.dart';

// ---------------------------------------------------------------------------
// Helm quarter view — the seasonal layer of the planner.
//
// Cal Newport's quarterly plan is a handful of goals WITH THEIR WHY and
// a mission per month — never a schedule. Delivery timelines live in
// the Plan view; goals link to work rather than re-declaring dates.
// Weekly planning draws from here (spawn objectives from goals), and
// met objectives fill each goal's progress automatically — the top of
// the block → objective → goal cascade.
// ---------------------------------------------------------------------------

String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class HelmQuarterView extends StatefulWidget {
  final AppDatabase db;
  final DateTime date; // any date inside the target quarter
  final int anchorMonth;
  final void Function(DateTime weekMonday)? onOpenWeek;

  const HelmQuarterView({
    super.key,
    required this.db,
    required this.date,
    required this.anchorMonth,
    this.onOpenWeek,
  });

  @override
  State<HelmQuarterView> createState() => _HelmQuarterViewState();
}

class _HelmQuarterViewState extends State<HelmQuarterView> {
  // Memoized streams — same rule as the day/week views: never create a
  // stream in build, or rebuilds make the StreamBuilders blink.
  String? _startIso;
  Stream<QuarterPlan?>? _planStream;
  Stream<List<QuarterObjectiveRow>>? _objectivesStream;
  Stream<List<WeekBlockRow>>? _blocksStream;
  Stream<List<QuarterGoal>>? _goalsStream;
  String? _goalsPlanId;

  DateTime get _quarterStart =>
      quarterStartOf(widget.date, widget.anchorMonth);
  DateTime get _quarterEnd => DateTime(
      _quarterStart.year, _quarterStart.month + 3, 0); // last day

  void _anchorStreams() {
    final startIso = _isoDate(_quarterStart);
    if (_startIso == startIso) return;
    _startIso = startIso;
    final endIso = _isoDate(_quarterEnd);
    _planStream = widget.db.quarterPlanDao.watchPlanForQuarter(startIso);
    _objectivesStream = widget.db.quarterPlanDao
        .watchObjectivesForQuarter(startIso, endIso);
    // Day blocks across the whole quarter — powers objectiveMet so goal
    // progress honours block targets, not just manual ticks.
    _blocksStream =
        widget.db.weekPlanDao.watchBlocksForWeek(startIso, endIso);
    _goalsPlanId = null;
    _goalsStream = null;
  }

  Stream<List<QuarterGoal>> _goalsFor(String planId) {
    if (_goalsPlanId != planId) {
      _goalsPlanId = planId;
      _goalsStream = widget.db.quarterPlanDao.watchGoalsForPlan(planId);
    }
    return _goalsStream!;
  }

  @override
  Widget build(BuildContext context) {
    _anchorStreams();
    return StreamBuilder<QuarterPlan?>(
      stream: _planStream,
      builder: (context, planSnap) {
        if (planSnap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(strokeWidth: 1.5));
        }
        final plan = planSnap.data;
        if (plan == null) return _emptyQuarter();
        return StreamBuilder<List<QuarterObjectiveRow>>(
          stream: _objectivesStream,
          builder: (context, objSnap) {
            return StreamBuilder<List<WeekBlockRow>>(
              stream: _blocksStream,
              builder: (context, blockSnap) {
                return _quarterBody(
                  plan,
                  objSnap.data ?? const [],
                  blockSnap.data ?? const [],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _emptyQuarter() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.landscape_outlined,
              size: 48, color: KColors.textMuted),
          const SizedBox(height: 16),
          Text(
            'Chart this quarter',
            style: GoogleFonts.syne(
              color: KColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 420,
            child: Text(
              'A handful of goals — each with its why — and a mission '
              'per month. Weekly planning draws from here; delivery '
              'dates stay in the Plan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: KColors.textDim, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => widget.db.quarterPlanDao
                .getOrCreatePlanForQuarter(_isoDate(_quarterStart)),
            icon: const Icon(Icons.landscape_outlined, size: 16),
            label: const Text('Plan this quarter'),
          ),
        ],
      ),
    );
  }

  Widget _quarterBody(QuarterPlan plan,
      List<QuarterObjectiveRow> objectiveRows, List<WeekBlockRow> blockRows) {
    final missions = parseDayMissions(plan.monthMissionsJson);
    final startsByPlanId = {
      for (final r in blockRows)
        r.plan.id: parseRevisionStarts(r.plan.revisionStartsJson),
    };
    final quarterBlocks = blockRows.map((r) => r.block).toList();
    bool isMet(WeekPlanObjective o) =>
        objectiveMet(o, quarterBlocks, startsByPlanId);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Month missions ────────────────────────────────────
              for (var m = 0; m < 3; m++)
                _MonthCard(
                  month: DateTime(
                      _quarterStart.year, _quarterStart.month + m, 1),
                  mission: missions[m],
                  onEdit: () => _editMission(plan, m, missions[m]),
                ),
              const SizedBox(height: 8),
              // ── Week strip — the readout, never an editor ─────────
              const Padding(
                padding: EdgeInsets.fromLTRB(2, 8, 2, 6),
                child: Text(
                  'WEEKS',
                  style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              for (final monday in _mondaysInQuarter())
                _WeekStripRow(
                  monday: monday,
                  isThisWeek: _isoDate(mondayOf(DateTime.now())) ==
                      _isoDate(monday),
                  objectives: objectiveRows
                      .where((r) =>
                          r.weekPlan.weekStartDate == _isoDate(monday))
                      .map((r) => r.objective)
                      .toList(),
                  isMet: isMet,
                  onOpen: widget.onOpenWeek == null
                      ? null
                      : () => widget.onOpenWeek!(monday),
                ),
            ],
          ),
        ),
        Container(width: 1, color: KColors.border),
        SizedBox(
          width: 300,
          child: StreamBuilder<List<QuarterGoal>>(
            stream: _goalsFor(plan.id),
            builder: (context, goalSnap) {
              return _GoalsPanel(
                db: widget.db,
                plan: plan,
                goals: goalSnap.data ?? const [],
                objectives:
                    objectiveRows.map((r) => r.objective).toList(),
                isMet: isMet,
              );
            },
          ),
        ),
      ],
    );
  }

  /// Mondays whose week belongs to this quarter (week ownership = the
  /// quarter containing its Monday).
  List<DateTime> _mondaysInQuarter() {
    final mondays = <DateTime>[];
    var m = mondayOf(_quarterStart);
    if (m.isBefore(_quarterStart)) m = m.add(const Duration(days: 7));
    while (!m.isAfter(_quarterEnd)) {
      mondays.add(m);
      m = m.add(const Duration(days: 7));
    }
    return mondays;
  }

  Future<void> _editMission(
      QuarterPlan plan, int monthIndex, String? current) async {
    final month = DateTime(
        _quarterStart.year, _quarterStart.month + monthIndex, 1);
    final ctrl = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_monthNames[month.month - 1]} mission'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'What is this month for?',
              hintText: 'e.g. Discovery — map the platform landscape',
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await widget.db.quarterPlanDao
        .setMonthMission(plan.id, monthIndex, result);
  }
}

// ---------------------------------------------------------------------------
// Month card
// ---------------------------------------------------------------------------

class _MonthCard extends StatelessWidget {
  final DateTime month;
  final String? mission;
  final VoidCallback onEdit;

  const _MonthCard({
    required this.month,
    required this.mission,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = month.year == DateTime.now().year &&
        month.month == DateTime.now().month;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrent ? KColors.surface2 : KColors.surface,
        border: Border.all(
            color: isCurrent ? KColors.amber : KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  '${_monthNames[month.month - 1]} ${month.year}'
                      .toUpperCase(),
                  maxLines: 2,
                  style: GoogleFonts.jetBrainsMono(
                    color: isCurrent ? KColors.amber : KColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.flag_outlined,
                  size: 13,
                  color:
                      mission != null ? KColors.amber : KColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  mission ?? 'Set a mission for this month…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        mission != null ? KColors.text : KColors.textMuted,
                    fontSize: 12,
                    fontStyle: mission == null
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Week strip row
// ---------------------------------------------------------------------------

class _WeekStripRow extends StatelessWidget {
  final DateTime monday;
  final bool isThisWeek;
  final List<WeekPlanObjective> objectives;
  final bool Function(WeekPlanObjective) isMet;
  final VoidCallback? onOpen;

  const _WeekStripRow({
    required this.monday,
    required this.isThisWeek,
    required this.objectives,
    required this.isMet,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final met = objectives.where(isMet).length;
    final isPast = monday
        .add(const Duration(days: 7))
        .isBefore(DateTime.now());
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isThisWeek
              ? KColors.amber.withValues(alpha: 0.08)
              : Colors.transparent,
          border: const Border(
              bottom: BorderSide(color: KColors.border, width: 1)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(
                'Wk of ${monday.day} ${_monthShort[monday.month - 1]}',
                style: GoogleFonts.jetBrainsMono(
                  color: isThisWeek
                      ? KColors.amber
                      : isPast
                          ? KColors.textMuted
                          : KColors.textDim,
                  fontSize: 11,
                  fontWeight:
                      isThisWeek ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Objective dots — met filled green, open hollow.
            Expanded(
              child: objectives.isEmpty
                  ? Text(
                      isPast ? 'no objectives' : '—',
                      style: const TextStyle(
                          color: KColors.textMuted, fontSize: 10),
                    )
                  : Row(
                      children: [
                        for (final o in objectives.take(8))
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message: o.label,
                              child: Icon(
                                isMet(o)
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 11,
                                color: isMet(o)
                                    ? KColors.phosphor
                                    : KColors.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            if (objectives.isNotEmpty)
              Text(
                '$met/${objectives.length}',
                style: GoogleFonts.jetBrainsMono(
                  color: met == objectives.length
                      ? KColors.phosphor
                      : KColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 13, color: KColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goals panel — the quarter's big rocks + their why
// ---------------------------------------------------------------------------

class _GoalsPanel extends StatelessWidget {
  final AppDatabase db;
  final QuarterPlan plan;
  final List<QuarterGoal> goals;
  final List<WeekPlanObjective> objectives;
  final bool Function(WeekPlanObjective) isMet;

  const _GoalsPanel({
    required this.db,
    required this.plan,
    required this.goals,
    required this.objectives,
    required this.isMet,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => _railLabel(d.data) != null,
      onAcceptWithDetails: (d) {
        final label = _railLabel(d.data);
        if (label != null) {
          db.quarterPlanDao.insertGoal(
            planId: plan.id,
            label: label,
            projectId: _railField(d.data, #projectId),
            linkedActionId: _railField(d.data, #linkedActionId),
          );
        }
      },
      builder: (context, candidates, _) {
        return Container(
          color: candidates.isNotEmpty
              ? KColors.amber.withValues(alpha: 0.06)
              : KColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 4),
                child: Row(
                  children: [
                    const Icon(Icons.landscape,
                        size: 13, color: KColors.amber),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'THIS QUARTER — GOALS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: KColors.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add,
                          size: 16, color: KColors.amber),
                      tooltip: 'Add goal',
                      onPressed: () => _editGoal(context, null),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  '3–5 goals with their why. Weekly objectives spawned '
                  'from a goal fill its progress when they\'re met.',
                  style: TextStyle(color: KColors.textMuted, fontSize: 10),
                ),
              ),
              Expanded(
                child: goals.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No goals yet — add one, or drag an item '
                            'from a project here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: KColors.textMuted, fontSize: 11),
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final g in goals)
                            _GoalRow(
                              goal: g,
                              metCount: goalMetObjectives(
                                  g.id, objectives, isMet),
                              onToggleDone: () => db.quarterPlanDao
                                  .setGoalDone(plan.id, g.id, !g.done),
                              onTap: () => _editGoal(context, g),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Rail drag payloads are private to helm_view — duck-type the fields.
  String? _railLabel(Object data) {
    try {
      return (data as dynamic).label as String?;
    } catch (_) {
      return null;
    }
  }

  String? _railField(Object data, Symbol field) {
    try {
      final d = data as dynamic;
      return field == #projectId
          ? d.projectId as String?
          : d.linkedActionId as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _editGoal(
      BuildContext context, QuarterGoal? existing) async {
    final result = await showDialog<_GoalDialogResult>(
      context: context,
      builder: (_) => _GoalDialog(existing: existing),
    );
    if (result == null) return;
    if (result.deleted && existing != null) {
      await db.quarterPlanDao.deleteGoal(plan.id, existing.id);
      return;
    }
    if (existing == null) {
      await db.quarterPlanDao.insertGoal(
        planId: plan.id,
        label: result.label,
        why: result.why,
        targetObjectives: result.targetObjectives,
      );
    } else {
      await db.quarterPlanDao.updateGoal(
        plan.id,
        QuarterGoalsCompanion(
          id: Value(existing.id),
          label: Value(result.label),
          why: Value(result.why),
          targetObjectives: Value(result.targetObjectives),
        ),
      );
    }
  }
}

class _GoalRow extends StatelessWidget {
  final QuarterGoal goal;
  final int metCount;
  final VoidCallback onToggleDone;
  final VoidCallback onTap;

  const _GoalRow({
    required this.goal,
    required this.metCount,
    required this.onToggleDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final target = goal.targetObjectives;
    final met = goal.done || (target != null && metCount >= target);
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: KColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onToggleDone,
                  child: Icon(
                    met
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: met ? KColors.phosphor : KColors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    goal.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: met ? KColors.textDim : KColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      decoration:
                          goal.done ? TextDecoration.lineThrough : null,
                      decorationColor: KColors.textMuted,
                    ),
                  ),
                ),
                if (target != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: met ? KColors.phosDim : KColors.surface2,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                          color:
                              met ? KColors.phosphor : KColors.border2),
                    ),
                    child: Text(
                      '$metCount/$target',
                      style: GoogleFonts.jetBrainsMono(
                        color:
                            met ? KColors.phosphor : KColors.textDim,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (goal.why != null && goal.why!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 3),
                child: Text(
                  goal.why!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KColors.textMuted,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GoalDialogResult {
  final String label;
  final String? why;
  final int? targetObjectives;
  final bool deleted;
  const _GoalDialogResult({
    required this.label,
    this.why,
    this.targetObjectives,
    this.deleted = false,
  });
}

class _GoalDialog extends StatefulWidget {
  final QuarterGoal? existing;
  const _GoalDialog({this.existing});

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _whyCtrl;
  int? _target;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.existing?.label ?? '');
    _whyCtrl = TextEditingController(text: widget.existing?.why ?? '');
    _target = widget.existing?.targetObjectives;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _whyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) return;
    final why = _whyCtrl.text.trim();
    Navigator.of(context).pop(_GoalDialogResult(
      label: label,
      why: why.isEmpty ? null : why,
      targetObjectives: _target,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.existing == null ? 'New goal' : 'Edit goal'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Goal for this quarter',
                hintText: 'e.g. Land the platform enablement re-plan',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _whyCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Why (what makes this worth a quarter?)',
                hintText: 'The motivation you\'ll re-read mid-quarter',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: _target,
              decoration: const InputDecoration(
                labelText: 'Target (weekly objectives this quarter)',
              ),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('No target')),
                for (var n = 1; n <= 20; n++)
                  DropdownMenuItem(
                      value: n,
                      child: Text('$n objective${n == 1 ? '' : 's'}')),
              ],
              onChanged: (v) => setState(() => _target = v),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
                const _GoalDialogResult(label: '', deleted: true)),
            child:
                const Text('Delete', style: TextStyle(color: KColors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
