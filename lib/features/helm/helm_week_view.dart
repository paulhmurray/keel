import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/database/database.dart';
import '../../core/helm/day_plan_logic.dart';
import '../../shared/theme/keel_colors.dart';
import 'helm_view.dart' show blockKindColor;

// ---------------------------------------------------------------------------
// Helm week view — the weekly layer of the planner.
//
// Deliberately NOT a bigger time grid: Cal Newport's weekly plan is an
// allocation of intent. Big rocks (objectives) for the week, a one-line
// mission per day, and a readout of how each day's actual plan went.
// Hours belong to the day view's morning ritual, which draws from this.
// ---------------------------------------------------------------------------

String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Drag payload accepted by the objectives panel (mirrors the rail's
/// payload shape without importing the private class).
typedef HelmObjectiveDrop = ({
  String label,
  String? projectId,
  String? linkedActionId,
});

class HelmWeekView extends StatefulWidget {
  final AppDatabase db;
  final DateTime date; // any date inside the target week
  final int anchorMonth; // quarter anchor — locates "this quarter"
  final void Function(DateTime day)? onOpenDay;

  const HelmWeekView({
    super.key,
    required this.db,
    required this.date,
    this.anchorMonth = 1,
    this.onOpenDay,
  });

  @override
  State<HelmWeekView> createState() => _HelmWeekViewState();
}

class _HelmWeekViewState extends State<HelmWeekView> {
  // Memoized streams (see helm_view.dart — recreating streams in build
  // makes StreamBuilders blink). Re-anchored when the week changes.
  String? _mondayIso;
  Stream<WeekPlan?>? _planStream;
  Stream<List<DayPlan>>? _dayPlansStream;
  Stream<List<WeekBlockRow>>? _blocksStream;
  Stream<List<WeekPlanObjective>>? _objectivesStream;
  String? _objectivesPlanId;
  // The surrounding quarter's goals — objectives can be spawned from them.
  Stream<QuarterPlan?>? _quarterPlanStream;
  String? _quarterStartIso;
  Stream<List<QuarterGoal>>? _goalsStream;
  String? _goalsPlanId;

  DateTime get _monday => mondayOf(widget.date);

  void _anchorStreams() {
    final mondayIso = _isoDate(_monday);
    if (_mondayIso == mondayIso) return;
    _mondayIso = mondayIso;
    final sundayIso = _isoDate(_monday.add(const Duration(days: 6)));
    final dao = widget.db.weekPlanDao;
    _planStream = dao.watchPlanForWeek(mondayIso);
    _dayPlansStream = dao.watchDayPlansForWeek(mondayIso, sundayIso);
    _blocksStream = dao.watchBlocksForWeek(mondayIso, sundayIso);
    _objectivesPlanId = null;
    _objectivesStream = null;
    final quarterIso =
        _isoDate(quarterStartOf(widget.date, widget.anchorMonth));
    if (_quarterStartIso != quarterIso) {
      _quarterStartIso = quarterIso;
      _quarterPlanStream =
          widget.db.quarterPlanDao.watchPlanForQuarter(quarterIso);
      _goalsPlanId = null;
      _goalsStream = null;
    }
  }

  Stream<List<QuarterGoal>> _goalsFor(String planId) {
    if (_goalsPlanId != planId) {
      _goalsPlanId = planId;
      _goalsStream = widget.db.quarterPlanDao.watchGoalsForPlan(planId);
    }
    return _goalsStream!;
  }

  Stream<List<WeekPlanObjective>> _objectivesFor(String planId) {
    if (_objectivesPlanId != planId) {
      _objectivesPlanId = planId;
      _objectivesStream =
          widget.db.weekPlanDao.watchObjectivesForPlan(planId);
    }
    return _objectivesStream!;
  }

  @override
  Widget build(BuildContext context) {
    _anchorStreams();
    return StreamBuilder<WeekPlan?>(
      stream: _planStream,
      builder: (context, planSnap) {
        if (planSnap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(strokeWidth: 1.5));
        }
        final plan = planSnap.data;
        if (plan == null) return _emptyWeek();
        return StreamBuilder<List<DayPlan>>(
          stream: _dayPlansStream,
          builder: (context, dayPlansSnap) {
            return StreamBuilder<List<WeekBlockRow>>(
              stream: _blocksStream,
              builder: (context, blocksSnap) {
                return _weekBody(
                  plan,
                  dayPlansSnap.data ?? const [],
                  blocksSnap.data ?? const [],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _emptyWeek() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.view_week_outlined,
              size: 48, color: KColors.textMuted),
          const SizedBox(height: 16),
          Text(
            'Chart this week',
            style: GoogleFonts.syne(
              color: KColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 400,
            child: Text(
              'Pick the week\'s big rocks and give each day a mission. '
              'The morning ritual draws from here — hours stay in the '
              'day view.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: KColors.textDim, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => widget.db.weekPlanDao
                .getOrCreatePlanForWeek(_isoDate(_monday)),
            icon: const Icon(Icons.view_week_outlined, size: 16),
            label: const Text('Plan this week'),
          ),
        ],
      ),
    );
  }

  Widget _weekBody(WeekPlan plan, List<DayPlan> dayPlans,
      List<WeekBlockRow> blockRows) {
    final missions = parseDayMissions(plan.dayMissionsJson);
    final planByDate = {for (final p in dayPlans) p.planDate: p};
    final blocksByDate = <String, List<DayPlanBlock>>{};
    for (final r in blockRows) {
      blocksByDate.putIfAbsent(r.plan.planDate, () => []).add(r.block);
    }
    final revisionStartsByPlanId = {
      for (final p in dayPlans)
        p.id: parseRevisionStarts(p.revisionStartsJson),
    };
    final todayIso = _isoDate(DateTime.now());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Day list ──────────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (var i = 0; i < 7; i++)
                _DayRow(
                  date: _monday.add(Duration(days: i)),
                  isToday:
                      _isoDate(_monday.add(Duration(days: i))) == todayIso,
                  mission: missions[i],
                  dayPlan: planByDate[
                      _isoDate(_monday.add(Duration(days: i)))],
                  blocks: blocksByDate[
                          _isoDate(_monday.add(Duration(days: i)))] ??
                      const [],
                  onOpen: widget.onOpenDay == null
                      ? null
                      : () => widget.onOpenDay!(
                          _monday.add(Duration(days: i))),
                  onEditMission: () => _editMission(plan, i, missions[i]),
                ),
            ],
          ),
        ),
        Container(width: 1, color: KColors.border),
        // ── Objectives panel ──────────────────────────────────────────
        SizedBox(
          width: 300,
          child: StreamBuilder<List<WeekPlanObjective>>(
            stream: _objectivesFor(plan.id),
            builder: (context, objSnap) {
              return StreamBuilder<QuarterPlan?>(
                stream: _quarterPlanStream,
                builder: (context, qSnap) {
                  final quarterPlan = qSnap.data;
                  if (quarterPlan == null) {
                    return _ObjectivesPanel(
                      db: widget.db,
                      plan: plan,
                      objectives: objSnap.data ?? const [],
                      blockRows: blockRows,
                      revisionStartsByPlanId: revisionStartsByPlanId,
                      quarterGoals: const [],
                    );
                  }
                  return StreamBuilder<List<QuarterGoal>>(
                    stream: _goalsFor(quarterPlan.id),
                    builder: (context, goalsSnap) {
                      return _ObjectivesPanel(
                        db: widget.db,
                        plan: plan,
                        objectives: objSnap.data ?? const [],
                        blockRows: blockRows,
                        revisionStartsByPlanId: revisionStartsByPlanId,
                        quarterGoals: goalsSnap.data ?? const [],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editMission(
      WeekPlan plan, int weekday, String? current) async {
    final ctrl = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            '${_weekdayNames[weekday]} mission'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'What is this day for?',
              hintText: 'e.g. Deep work on platform — no meetings',
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
    await widget.db.weekPlanDao.setDayMission(plan.id, weekday, result);
  }
}

// ---------------------------------------------------------------------------
// Day row — one card per day: date, mission, mini readout of the plan
// ---------------------------------------------------------------------------

class _DayRow extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final String? mission;
  final DayPlan? dayPlan;
  final List<DayPlanBlock> blocks;
  final VoidCallback? onOpen;
  final VoidCallback onEditMission;

  const _DayRow({
    required this.date,
    required this.isToday,
    required this.mission,
    required this.dayPlan,
    required this.blocks,
    this.onOpen,
    required this.onEditMission,
  });

  @override
  Widget build(BuildContext context) {
    final starts = dayPlan == null
        ? const <int>[]
        : parseRevisionStarts(dayPlan!.revisionStartsJson);
    final schedule = effectiveSchedule(blocks, starts);
    final focusMinutes = schedule
        .where((b) => b.kind == 'focus')
        .fold<int>(0, (s, b) => s + (b.endMinute - b.startMinute));
    final isPast = date.isBefore(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isToday ? KColors.surface2 : KColors.surface,
        border: Border.all(
            color: isToday ? KColors.amber : KColors.border,
            width: isToday ? 1 : 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      '${_weekdayNames[date.weekday - 1]} ${date.day} ${_monthNames[date.month - 1]}',
                      style: GoogleFonts.jetBrainsMono(
                        color: isToday ? KColors.amber : KColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isToday) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: KColors.amber,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        'TODAY',
                        style: GoogleFonts.jetBrainsMono(
                          color: KColors.bg,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  if (focusMinutes > 0)
                    Text(
                      'Focus ${focusMinutes ~/ 60}h${focusMinutes % 60 == 0 ? '' : '${focusMinutes % 60}m'}',
                      style: GoogleFonts.jetBrainsMono(
                          color: KColors.textDim, fontSize: 10),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Mission line — tap to edit without opening the day.
              InkWell(
                onTap: onEditMission,
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.flag_outlined,
                          size: 12,
                          color: mission != null
                              ? KColors.amber
                              : KColors.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          mission ?? 'Set a mission for this day…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mission != null
                                ? KColors.text
                                : KColors.textMuted,
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
              if (schedule.isNotEmpty) ...[
                const SizedBox(height: 6),
                _BlockSlivers(schedule: schedule, dimDone: isPast),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The day's effective blocks as proportional colored slivers — a
/// readout, not an editor.
class _BlockSlivers extends StatelessWidget {
  final List<DayPlanBlock> schedule;
  final bool dimDone;

  const _BlockSlivers({required this.schedule, required this.dimDone});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final b in schedule)
          Flexible(
            flex: (b.endMinute - b.startMinute).clamp(15, 480),
            child: Tooltip(
              message:
                  '${formatMinute(b.startMinute)}–${formatMinute(b.endMinute)}  ${b.label}${b.done ? '  ✓' : ''}',
              child: Container(
                height: 8,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: blockKindColor(b.kind)
                      .withValues(alpha: b.done ? 0.45 : 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Objectives panel — the week's big rocks
// ---------------------------------------------------------------------------

class _ObjectivesPanel extends StatelessWidget {
  final AppDatabase db;
  final WeekPlan plan;
  final List<WeekPlanObjective> objectives;
  final List<WeekBlockRow> blockRows;
  final Map<String, List<int>> revisionStartsByPlanId;
  final List<QuarterGoal> quarterGoals;

  const _ObjectivesPanel({
    required this.db,
    required this.plan,
    required this.objectives,
    required this.blockRows,
    required this.revisionStartsByPlanId,
    this.quarterGoals = const [],
  });

  @override
  Widget build(BuildContext context) {
    final weekBlocks = blockRows.map((r) => r.block).toList();
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) {
        final data = d.data;
        // The rail's drag payload exposes these fields via toString-free
        // duck typing — accept anything carrying a label.
        return data is HelmObjectiveDrop || _railLabel(data) != null;
      },
      onAcceptWithDetails: (d) {
        final data = d.data;
        if (data is HelmObjectiveDrop) {
          db.weekPlanDao.insertObjective(
            planId: plan.id,
            label: data.label,
            projectId: data.projectId,
            linkedActionId: data.linkedActionId,
          );
        } else {
          final label = _railLabel(data);
          if (label != null) {
            db.weekPlanDao.insertObjective(
              planId: plan.id,
              label: label,
              projectId: _railProjectId(data),
              linkedActionId: _railActionId(data),
            );
          }
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
                    const Icon(Icons.flag,
                        size: 13, color: KColors.amber),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'THIS WEEK — BIG ROCKS',
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
                      tooltip: 'Add objective',
                      onPressed: () => _editObjective(context, null),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  '3–5 rocks. Drag onto the day grid each morning; done '
                  'blocks count toward each rock\'s target.',
                  style: TextStyle(color: KColors.textMuted, fontSize: 10),
                ),
              ),
              // ── Spawn from a quarterly goal — the downward link that
              // makes the quarter feed the week.
              if (quarterGoals.any((g) => !g.done)) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 2, 14, 4),
                  child: Text(
                    'FROM THE QUARTER',
                    style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in quarterGoals.where((g) => !g.done))
                        Tooltip(
                          message:
                              'Add a weekly objective for this goal',
                          child: InkWell(
                            onTap: () => db.weekPlanDao.insertObjective(
                              planId: plan.id,
                              label: g.label,
                              projectId: g.projectId,
                              linkedActionId: g.linkedActionId,
                              goalId: g.id,
                            ),
                            borderRadius: BorderRadius.circular(3),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: KColors.surface2,
                                border:
                                    Border.all(color: KColors.border2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.landscape,
                                      size: 10, color: KColors.amber),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        maxWidth: 200),
                                    child: Text(
                                      g.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: KColors.textDim,
                                          fontSize: 10),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.add,
                                      size: 10, color: KColors.amber),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: objectives.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No objectives yet — add one, or drag an item '
                            'from a project here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: KColors.textMuted, fontSize: 11),
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final o in objectives)
                            _ObjectiveRow(
                              objective: o,
                              doneBlocks: objectiveDoneBlocks(o.id,
                                  weekBlocks, revisionStartsByPlanId),
                              onToggleDone: () => db.weekPlanDao
                                  .setObjectiveDone(
                                      plan.id, o.id, !o.done),
                              onTap: () => _editObjective(context, o),
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

  // The rail's private payload can't be imported here; read its fields
  // dynamically. Wrong-shaped objects simply return null and are ignored.
  String? _railLabel(Object data) {
    try {
      return (data as dynamic).label as String?;
    } catch (_) {
      return null;
    }
  }

  String? _railProjectId(Object data) {
    try {
      return (data as dynamic).projectId as String?;
    } catch (_) {
      return null;
    }
  }

  String? _railActionId(Object data) {
    try {
      return (data as dynamic).linkedActionId as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _editObjective(
      BuildContext context, WeekPlanObjective? existing) async {
    final result = await showDialog<_ObjectiveDialogResult>(
      context: context,
      builder: (_) => _ObjectiveDialog(existing: existing),
    );
    if (result == null) return;
    if (result.deleted && existing != null) {
      await db.weekPlanDao.deleteObjective(plan.id, existing.id);
      return;
    }
    if (existing == null) {
      await db.weekPlanDao.insertObjective(
        planId: plan.id,
        label: result.label,
        targetBlocks: result.targetBlocks,
      );
    } else {
      await db.weekPlanDao.updateObjective(
        plan.id,
        WeekPlanObjectivesCompanion(
          id: Value(existing.id),
          label: Value(result.label),
          targetBlocks: Value(result.targetBlocks),
        ),
      );
    }
  }
}

class _ObjectiveRow extends StatelessWidget {
  final WeekPlanObjective objective;
  final int doneBlocks;
  final VoidCallback onToggleDone;
  final VoidCallback onTap;

  const _ObjectiveRow({
    required this.objective,
    required this.doneBlocks,
    required this.onToggleDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final target = objective.targetBlocks;
    final met = objective.done || (target != null && doneBlocks >= target);
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: KColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggleDone,
              child: Icon(
                met ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: met ? KColors.phosphor : KColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            if (objective.goalId != null) ...[
              const Tooltip(
                message: 'Linked to a quarterly goal',
                child: Icon(Icons.landscape,
                    size: 11, color: KColors.amber),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                objective.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: met ? KColors.textDim : KColors.text,
                  fontSize: 12,
                  decoration:
                      objective.done ? TextDecoration.lineThrough : null,
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
                      color: met ? KColors.phosphor : KColors.border2),
                ),
                child: Text(
                  '$doneBlocks/$target',
                  style: GoogleFonts.jetBrainsMono(
                    color: met ? KColors.phosphor : KColors.textDim,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ObjectiveDialogResult {
  final String label;
  final int? targetBlocks;
  final bool deleted;
  const _ObjectiveDialogResult({
    required this.label,
    this.targetBlocks,
    this.deleted = false,
  });
}

class _ObjectiveDialog extends StatefulWidget {
  final WeekPlanObjective? existing;
  const _ObjectiveDialog({this.existing});

  @override
  State<_ObjectiveDialog> createState() => _ObjectiveDialogState();
}

class _ObjectiveDialogState extends State<_ObjectiveDialog> {
  late final TextEditingController _labelCtrl;
  int? _target;

  @override
  void initState() {
    super.initState();
    _labelCtrl =
        TextEditingController(text: widget.existing?.label ?? '');
    _target = widget.existing?.targetBlocks;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) return;
    Navigator.of(context).pop(
        _ObjectiveDialogResult(label: label, targetBlocks: _target));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'New objective'
          : 'Edit objective'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Big rock for this week',
                hintText: 'e.g. Re-plan AWS and platform enablement',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: _target,
              decoration: const InputDecoration(
                labelText: 'Target (focus blocks this week)',
              ),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('No target')),
                for (var n = 1; n <= 10; n++)
                  DropdownMenuItem(
                      value: n, child: Text('$n block${n == 1 ? '' : 's'}')),
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
                const _ObjectiveDialogResult(label: '', deleted: true)),
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
