import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/helm/day_plan_logic.dart';
import '../../core/helm/planning_horizon.dart';
import '../../core/helm/week_ritual.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';

/// "Chart this week": the weekly plan as a sequence of prompts, not a
/// form. Look back at last week, see what is on the plate, put the big
/// rocks on days against real capacity, commit. Everything is held as
/// drafts and written in one go at the end, so Cancel at any step
/// leaves nothing behind. Opening it on a week that already has rocks
/// edits them rather than duplicating.
///
/// [startAtReview] opens on the look-back step (the Friday nudge).
Future<bool?> showWeekRitual(
  BuildContext context, {
  required AppDatabase db,
  required DateTime date,
  bool startAtReview = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        WeekRitualDialog(db: db, date: date, startAtReview: startAtReview),
  );
}

class WeekRitualDialog extends StatefulWidget {
  final AppDatabase db;
  final DateTime date;
  final bool startAtReview;
  const WeekRitualDialog({
    super.key,
    required this.db,
    required this.date,
    this.startAtReview = true,
  });

  @override
  State<WeekRitualDialog> createState() => _WeekRitualDialogState();
}

/// A big rock as the ritual holds it before anything is written.
class _Rock {
  String? id; // existing objective, or null for a new one
  String label;
  String? projectId;
  String? linkedActionId;
  String? goalId;
  String? carriedFromId;
  Map<int, int> alloc;
  bool done;
  _Rock({
    this.id,
    required this.label,
    this.projectId,
    this.linkedActionId,
    this.goalId,
    this.carriedFromId,
    Map<int, int>? alloc,
    this.done = false,
  }) : alloc = {...?alloc};
  int get total => allocatedSlots(alloc);
}

enum _Step { review, plate, days, commit }

const _kDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class _WeekRitualDialogState extends State<WeekRitualDialog> {
  bool _loading = true;
  String? _loadError;
  _Step _step = _Step.review;

  late final DateTime _monday = mondayOf(widget.date);
  late final DateTime _lastMonday = _monday.subtract(const Duration(days: 7));

  WeekPlan? _plan;
  List<WeekPlanObjective> _existing = const [];
  Map<int, String> _existingMissions = const {};
  WeekPlan? _lastPlan;
  List<ReviewRow> _lastRows = const [];
  final Map<String, bool> _carry = {}; // last-week objective id → carry?
  final _noteCtrl = TextEditingController();

  PlanningHorizon? _horizon;
  List<QuarterGoal> _goals = const [];
  String? _monthMission;

  final List<_Rock> _rocks = [];
  final Set<String> _removedExistingIds = {};
  final _newRockCtrl = TextEditingController();

  // Capacity per weekday: configured focus less meetings already planned.
  Map<int, int> _capacity = const {};
  final Map<int, TextEditingController> _missionCtrls = {
    for (var i = 0; i < 7; i++) i: TextEditingController(),
  };
  final Set<int> _missionTouched = {};

  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _newRockCtrl.dispose();
    for (final c in _missionCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _loadInner();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  Future<void> _loadInner() async {
    final db = widget.db;
    final settings = context.read<SettingsProvider>().settings;
    final mondayIso = _iso(_monday);
    final sundayIso = _iso(_monday.add(const Duration(days: 6)));
    final lastMondayIso = _iso(_lastMonday);
    final lastSundayIso = _iso(_lastMonday.add(const Duration(days: 6)));

    _plan = await db.weekPlanDao.getPlanForWeek(mondayIso);
    _existing = _plan == null
        ? const []
        : await db.weekPlanDao.getObjectivesForPlan(_plan!.id);
    _existingMissions = _plan == null
        ? const {}
        : parseDayMissions(_plan!.dayMissionsJson);

    _lastPlan = await db.weekPlanDao.getPlanForWeek(lastMondayIso);
    if (_lastPlan != null) {
      final objs = await db.weekPlanDao.getObjectivesForPlan(_lastPlan!.id);
      final rows = await db.weekPlanDao.getBlocksForWeek(
        lastMondayIso,
        lastSundayIso,
      );
      final plans = await db.weekPlanDao.getDayPlansForWeek(
        lastMondayIso,
        lastSundayIso,
      );
      final starts = {
        for (final p in plans) p.id: parseRevisionStarts(p.revisionStartsJson),
      };
      _lastRows = reviewRows(objs, rows.map((r) => r.block).toList(), starts);
      for (final r in _lastRows) {
        // Already carried into this week? Then it is not offered again.
        final carried = _existing.any((o) => o.carriedFromId == r.objective.id);
        _carry[r.objective.id] = !r.met && !carried;
      }
      _noteCtrl.text = _lastPlan!.reviewNote ?? '';
    }

    // Capacity for this week's days from what is already planned.
    final thisRows = await db.weekPlanDao.getBlocksForWeek(
      mondayIso,
      sundayIso,
    );
    final thisPlans = await db.weekPlanDao.getDayPlansForWeek(
      mondayIso,
      sundayIso,
    );
    final cap = <int, int>{};
    for (var d = 0; d < 7; d++) {
      final iso = _iso(_monday.add(Duration(days: d)));
      final plan = thisPlans.where((p) => p.planDate == iso).firstOrNull;
      final blocks = thisRows
          .where((r) => r.plan.planDate == iso)
          .map((r) => r.block)
          .toList();
      final meetings = plan == null
          ? 0
          : meetingSlots(blocks, parseRevisionStarts(plan.revisionStartsJson));
      cap[d] = d >= 5
          ? 0
          : dayCapacity(
              focusSlotsPerDay: settings.helmFocusSlotsPerDay,
              meetingSlots: meetings,
            );
    }
    _capacity = cap;

    // What's coming: the horizon as seen from this week's Monday. Plain
    // queries, not `.first` on the rail's streams — those never resolve
    // under a widget test's fake clock.
    try {
      final dao = db.dayPlanDao;
      _horizon = buildPlanningHorizon(
        today: _monday,
        actions: await dao.getOpenActionsAllProjects(),
        decisions: await dao.getPendingDecisionsAllProjects(),
        dependencies: await dao.getOpenDependenciesAllProjects(),
        risks: await dao.getOpenRisksAllProjects(),
        issues: await dao.getOpenIssuesAllProjects(),
        activities: await dao.getDatedActivitiesAllProjects(),
      );
    } catch (_) {
      _horizon = null;
    }

    // Look up: the quarter's goals and this month's mission.
    final qStart = quarterStartOf(_monday, settings.quarterAnchorMonth);
    final qPlan = await db.quarterPlanDao.getPlanForQuarter(_iso(qStart));
    if (qPlan != null) {
      _goals = await db.quarterPlanDao.getGoalsForPlan(qPlan.id);
      final idx =
          (_monday.year - qStart.year) * 12 + _monday.month - qStart.month;
      _monthMission = parseDayMissions(qPlan.monthMissionsJson)[idx];
    }

    // Drafts start from what the week already holds.
    for (final o in _existing) {
      _rocks.add(
        _Rock(
          id: o.id,
          label: o.label,
          projectId: o.projectId,
          linkedActionId: o.linkedActionId,
          goalId: o.goalId,
          carriedFromId: o.carriedFromId,
          alloc: parseDayAllocations(o.dayAllocationsJson),
          done: o.done,
        ),
      );
    }
    for (var d = 0; d < 7; d++) {
      _missionCtrls[d]!.text = _existingMissions[d] ?? '';
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = widget.startAtReview && _lastPlan != null
          ? _Step.review
          : _Step.plate;
    });
  }

  // ── Draft helpers ─────────────────────────────────────────────────────

  bool _hasRock({String? actionId, String? goalId, String? label}) =>
      _rocks.any(
        (r) =>
            (actionId != null && r.linkedActionId == actionId) ||
            (goalId != null && r.goalId == goalId) ||
            (label != null &&
                r.label.trim().toLowerCase() == label.trim().toLowerCase()),
      );

  void _toggleItem(PlanningItem it) {
    setState(() {
      final existing = _rocks.indexWhere(
        (r) =>
            (it.linkedActionId != null &&
                r.linkedActionId == it.linkedActionId) ||
            r.label == it.label,
      );
      if (existing >= 0) {
        _removeRock(_rocks[existing]);
      } else {
        _rocks.add(
          _Rock(
            label: it.label,
            projectId: it.projectId,
            linkedActionId: it.linkedActionId,
          ),
        );
      }
    });
  }

  void _toggleGoal(QuarterGoal g) {
    setState(() {
      final existing = _rocks.indexWhere((r) => r.goalId == g.id);
      if (existing >= 0) {
        _removeRock(_rocks[existing]);
      } else {
        _rocks.add(_Rock(label: g.label, projectId: g.projectId, goalId: g.id));
      }
    });
  }

  void _removeRock(_Rock r) {
    if (r.id != null) _removedExistingIds.add(r.id!);
    _rocks.remove(r);
  }

  void _applyCarryChoices() {
    // Carry = a new rock in this week pointing back; drop = nothing.
    for (final row in _lastRows) {
      final want = _carry[row.objective.id] ?? false;
      final idx = _rocks.indexWhere(
        (r) => r.carriedFromId == row.objective.id && r.id == null,
      );
      if (want &&
          idx < 0 &&
          !_existing.any((o) => o.carriedFromId == row.objective.id)) {
        _rocks.add(
          _Rock(
            label: row.objective.label,
            projectId: row.objective.projectId,
            linkedActionId: row.objective.linkedActionId,
            goalId: row.objective.goalId,
            carriedFromId: row.objective.id,
          ),
        );
      } else if (!want && idx >= 0) {
        _rocks.removeAt(idx);
      }
    }
  }

  void _bump(_Rock r, int day) {
    setState(() {
      final cur = r.alloc[day] ?? 0;
      final next = cur >= 6 ? 0 : cur + 1;
      if (next == 0) {
        r.alloc.remove(day);
      } else {
        r.alloc[day] = next;
      }
      _refreshDrafts();
    });
  }

  /// Day missions follow the allocations until the user types one.
  void _refreshDrafts() {
    final rocks = [
      for (final r in _rocks) (label: r.label, allocations: r.alloc),
    ];
    for (var d = 0; d < 7; d++) {
      if (_missionTouched.contains(d)) continue;
      if ((_existingMissions[d] ?? '').isNotEmpty) continue;
      _missionCtrls[d]!.text = draftDayMission(rocks, d) ?? '';
    }
  }

  // ── Navigation and commit ─────────────────────────────────────────────

  void _next() {
    setState(() {
      switch (_step) {
        case _Step.review:
          _applyCarryChoices();
          _step = _Step.plate;
        case _Step.plate:
          _refreshDrafts();
          _step = _Step.days;
        case _Step.days:
          _step = _Step.commit;
        case _Step.commit:
          break;
      }
    });
  }

  void _back() {
    setState(() {
      switch (_step) {
        case _Step.review:
          break;
        case _Step.plate:
          _step = _lastPlan != null ? _Step.review : _Step.plate;
        case _Step.days:
          _step = _Step.plate;
        case _Step.commit:
          _step = _Step.days;
      }
    });
  }

  Future<void> _commit() async {
    if (_committing) return;
    setState(() => _committing = true);
    final dao = widget.db.weekPlanDao;
    final plan = await dao.getOrCreatePlanForWeek(_iso(_monday));
    for (final id in _removedExistingIds) {
      await dao.deleteObjective(plan.id, id);
    }
    for (final r in _rocks) {
      final total = r.total;
      if (r.id != null) {
        await dao.updateObjective(
          plan.id,
          WeekPlanObjectivesCompanion(
            id: Value(r.id!),
            label: Value(r.label),
            targetBlocks: Value(
              total > 0
                  ? total
                  : _existing
                        .where((o) => o.id == r.id)
                        .firstOrNull
                        ?.targetBlocks,
            ),
            dayAllocationsJson: Value(encodeDayAllocations(r.alloc)),
          ),
        );
      } else {
        await dao.insertObjective(
          planId: plan.id,
          label: r.label,
          projectId: r.projectId,
          linkedActionId: r.linkedActionId,
          goalId: r.goalId,
          targetBlocks: total > 0 ? total : null,
          dayAllocationsJson: encodeDayAllocations(r.alloc),
          carriedFromId: r.carriedFromId,
        );
      }
    }
    for (var d = 0; d < 7; d++) {
      final text = _missionCtrls[d]!.text.trim();
      if (text != (_existingMissions[d] ?? '')) {
        await dao.setDayMission(plan.id, d, text);
      }
    }
    await dao.markCharted(plan.id);
    if (_lastPlan != null) {
      await dao.setReview(_lastPlan!.id, note: _noteCtrl.text);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title =
        'Chart the week of ${_monday.day} ${_monthName(_monday.month)}';
    final steps = [
      if (_lastPlan != null) (_Step.review, 'Look back'),
      (_Step.plate, 'On the plate'),
      (_Step.days, 'Rocks on days'),
      (_Step.commit, 'Commit'),
    ];
    return Dialog(
      backgroundColor: KColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: KColors.border),
      ),
      child: SizedBox(
        width: 920,
        height: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.view_week_outlined,
                    size: 16,
                    color: KColors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.syne(
                        color: KColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final (s, label) in steps) ...[
                    _stepChip(label, s == _step, s.index < _step.index),
                    const SizedBox(width: 6),
                  ],
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: KColors.textMuted,
                    ),
                    tooltip: 'Cancel — nothing is written until Commit',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: KColors.border),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : _loadError != null
                  ? Center(
                      child: Text(
                        'Could not load the week: $_loadError',
                        style: const TextStyle(
                          color: KColors.red,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                      child: switch (_step) {
                        _Step.review => _reviewStep(),
                        _Step.plate => _plateStep(),
                        _Step.days => _daysStep(),
                        _Step.commit => _commitStep(),
                      },
                    ),
            ),
            const Divider(height: 1, color: KColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Row(
                children: [
                  if (_step != _Step.review &&
                      !(_step == _Step.plate && _lastPlan == null))
                    TextButton(
                      onPressed: _loading ? null : _back,
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  if (_step == _Step.commit)
                    ElevatedButton.icon(
                      onPressed: _loading || _committing ? null : _commit,
                      icon: const Icon(Icons.check, size: 14),
                      label: const Text('Commit the week'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _next,
                      icon: const Icon(Icons.arrow_forward, size: 14),
                      label: Text(
                        _step == _Step.days ? 'Review and commit' : 'Next',
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

  Widget _stepChip(String label, bool current, bool done) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: current
          ? KColors.amber.withValues(alpha: 0.15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: current
            ? KColors.amber
            : (done ? KColors.phosphor : KColors.border),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: current
            ? KColors.amber
            : (done ? KColors.phosphor : KColors.textMuted),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _h(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: KColors.textDim,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(color: KColors.textDim, fontSize: 12, height: 1.4),
    ),
  );

  // ── Step 1: look back ────────────────────────────────────────────────

  Widget _reviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hint(
          'Last week\'s rocks and what they actually got. Carry what still '
          'matters into this week; drop what doesn\'t. Then one line on what '
          'you learned — it stays with last week\'s plan.',
        ),
        Expanded(
          child: ListView(
            children: [
              if (_lastRows.isEmpty)
                const Text(
                  'Last week had a plan but no rocks.',
                  style: TextStyle(color: KColors.textMuted, fontSize: 12),
                ),
              for (final r in _lastRows)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: KColors.surface2,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: KColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        r.met
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: r.met ? KColors.phosphor : KColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r.objective.label,
                          style: const TextStyle(
                            color: KColors.text,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        r.target != null
                            ? '${r.doneSlots}/${r.target} blocks'
                            : '${r.doneSlots} blocks',
                        style: GoogleFonts.jetBrainsMono(
                          color: r.met ? KColors.phosphor : KColors.textDim,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_existing.any(
                        (o) => o.carriedFromId == r.objective.id,
                      ))
                        const Text(
                          'already carried',
                          style: TextStyle(
                            color: KColors.textMuted,
                            fontSize: 11,
                          ),
                        )
                      else
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              label: Text(
                                'Carry',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text(
                                'Drop',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                          selected: {_carry[r.objective.id] ?? false},
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          onSelectionChanged: (v) =>
                              setState(() => _carry[r.objective.id] = v.first),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'What did last week teach you?',
            hintText: 'e.g. Tuesdays are meeting-heavy — no deep work there',
            isDense: true,
          ),
        ),
      ],
    );
  }

  // ── Step 2: on the plate ─────────────────────────────────────────────

  Widget _plateStep() {
    final h = _horizon;
    final over = _rocks.length > kBigRockSoftCap;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _hint(
                'Everything with a date this week and next, across every '
                'project, plus the quarter\'s goals. Tick what becomes a big '
                'rock. Three to five is the sweet spot.',
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (_monthMission != null) ...[
                      _h('This month\'s mission'),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _monthMission!,
                          style: const TextStyle(
                            color: KColors.text,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                    if (_goals.any((g) => !g.done)) ...[
                      _h('Quarter goals'),
                      for (final g in _goals.where((g) => !g.done))
                        _pick(
                          label: g.label,
                          detail: g.why,
                          selected: _hasRock(goalId: g.id),
                          onTap: () => _toggleGoal(g),
                          icon: Icons.landscape,
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (h == null)
                      const Text(
                        'The horizon could not be loaded.',
                        style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 12,
                        ),
                      )
                    else ...[
                      if (h.overdue.isNotEmpty) ...[
                        _h('Behind'),
                        for (final it in h.overdue) _pickItem(it, KColors.red),
                      ],
                      if (h.today.isNotEmpty) ...[
                        _h('Monday'),
                        for (final it in h.today) _pickItem(it, KColors.amber),
                      ],
                      for (final day in h.restOfWeek) ...[
                        _h(_kDays[day.date.weekday - 1]),
                        for (final it in day.items)
                          _pickItem(it, KColors.amber),
                      ],
                      if (h.nextWeek.isNotEmpty) ...[
                        _h('Next week'),
                        for (final it in h.nextWeek)
                          _pickItem(it, KColors.blue),
                      ],
                      if (h.isEmpty)
                        const Text(
                          'Nothing dated in the next fortnight.',
                          style: TextStyle(
                            color: KColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Container(width: 1, color: KColors.border),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _h('This week\'s rocks · ${_rocks.length}'),
                  const Spacer(),
                  if (over)
                    const Text(
                      'more than five — be honest',
                      style: TextStyle(color: KColors.amber, fontSize: 10),
                    ),
                ],
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (_rocks.isEmpty)
                      const Text(
                        'None yet.',
                        style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    for (final r in _rocks)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              r.carriedFromId != null
                                  ? Icons.replay
                                  : r.goalId != null
                                  ? Icons.landscape
                                  : Icons.flag,
                              size: 13,
                              color: KColors.amber,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                r.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: KColors.text,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 14,
                                color: KColors.textMuted,
                              ),
                              tooltip: 'Not a rock this week',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: () => setState(() => _removeRock(r)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _newRockCtrl,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Add a rock of your own',
                  hintText: 'Enter to add',
                  isDense: true,
                ),
                onSubmitted: (v) {
                  final label = v.trim();
                  if (label.isEmpty || _hasRock(label: label)) return;
                  setState(() {
                    _rocks.add(_Rock(label: label));
                    _newRockCtrl.clear();
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pickItem(PlanningItem it, Color colour) => _pick(
    label: it.label,
    detail: '${it.projectName} · ${it.dateKind} ${it.dueIso}',
    selected: _hasRock(actionId: it.linkedActionId, label: it.label),
    onTap: () => _toggleItem(it),
    barColor: colour,
  );

  Widget _pick({
    required String label,
    String? detail,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? barColor,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            selected ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: selected ? KColors.amber : KColors.textMuted,
          ),
          const SizedBox(width: 8),
          if (barColor != null)
            Container(
              width: 3,
              height: 26,
              color: barColor,
              margin: const EdgeInsets.only(right: 8),
            ),
          if (icon != null) ...[
            Icon(icon, size: 12, color: KColors.amber),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: KColors.text, fontSize: 12),
                ),
                if (detail != null && detail.trim().isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // ── Step 3: rocks on days ────────────────────────────────────────────

  Widget _daysStep() {
    final loads = {
      for (var d = 0; d < 7; d++) d: dayLoad(_rocks.map((r) => r.alloc), d),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hint(
          'Tap a cell to give a rock focus blocks on that day (30 minutes '
          'each; tap again to add, past six wraps to none). The bottom row is '
          'each day\'s room once its meetings are counted. The morning ritual '
          'pre-places these blocks for you.',
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Table(
                  columnWidths: const {0: FlexColumnWidth(3)},
                  defaultColumnWidth: const FixedColumnWidth(64),
                  border: TableBorder.all(color: KColors.border, width: 0.5),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: KColors.surface2),
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'ROCK',
                            style: TextStyle(
                              color: KColors.textDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (var d = 0; d < 7; d++)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              _kDays[d],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: d >= 5
                                    ? KColors.textMuted
                                    : KColors.textDim,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (final r in _rocks)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: KColors.text,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  r.total == 0 ? '' : '${r.total}',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: KColors.textDim,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (var d = 0; d < 7; d++)
                            InkWell(
                              onTap: () => _bump(r, d),
                              child: Container(
                                height: 40,
                                alignment: Alignment.center,
                                color: (r.alloc[d] ?? 0) > 0
                                    ? KColors.amber.withValues(alpha: 0.12)
                                    : (d >= 5
                                          ? KColors.bg
                                          : Colors.transparent),
                                child: Text(
                                  (r.alloc[d] ?? 0) == 0
                                      ? '·'
                                      : '${r.alloc[d]}',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: (r.alloc[d] ?? 0) > 0
                                        ? KColors.amber
                                        : KColors.textMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    TableRow(
                      decoration: const BoxDecoration(color: KColors.surface2),
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'used / room',
                            style: TextStyle(
                              color: KColors.textDim,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        for (var d = 0; d < 7; d++)
                          Builder(
                            builder: (_) {
                              final load = loads[d]!;
                              final cap = _capacity[d] ?? 0;
                              final over = overcommitted(
                                load: load,
                                capacity: cap,
                              );
                              return Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  '$load / $cap',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: over ? KColors.red : KColors.textDim,
                                    fontSize: 11,
                                    fontWeight: over
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _h('Day missions'),
                for (var d = 0; d < 5; d++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            _kDays[d],
                            style: const TextStyle(
                              color: KColors.textDim,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _missionCtrls[d],
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: 'What is this day for?',
                              isDense: true,
                            ),
                            onChanged: (_) => _missionTouched.add(d),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 4: commit ───────────────────────────────────────────────────

  Widget _commitStep() {
    final loads = {
      for (var d = 0; d < 7; d++) d: dayLoad(_rocks.map((r) => r.alloc), d),
    };
    final overDays = [
      for (var d = 0; d < 7; d++)
        if (overcommitted(load: loads[d]!, capacity: _capacity[d] ?? 0))
          _kDays[d],
    ];
    final unallocated = _rocks.where((r) => r.total == 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hint(
          'This is the week as you will see it every morning. Commit writes '
          'the rocks, their days and the missions in one go.',
        ),
        Expanded(
          child: ListView(
            children: [
              for (final r in _rocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.flag, size: 13, color: KColors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.label,
                          style: const TextStyle(
                            color: KColors.text,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        r.total == 0
                            ? 'no days yet'
                            : [
                                for (var d = 0; d < 7; d++)
                                  if ((r.alloc[d] ?? 0) > 0)
                                    '${_kDays[d]} ${r.alloc[d]}',
                              ].join(' · '),
                        style: GoogleFonts.jetBrainsMono(
                          color: r.total == 0 ? KColors.amber : KColors.textDim,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              for (var d = 0; d < 5; d++)
                if (_missionCtrls[d]!.text.trim().isNotEmpty)
                  Text(
                    '${_kDays[d]}: ${_missionCtrls[d]!.text.trim()}',
                    style: const TextStyle(
                      color: KColors.textDim,
                      fontSize: 12,
                    ),
                  ),
              const SizedBox(height: 12),
              if (overDays.isNotEmpty)
                Text(
                  'Overcommitted: ${overDays.join(', ')}. Something will give.',
                  style: const TextStyle(color: KColors.red, fontSize: 12),
                ),
              if (unallocated.isNotEmpty)
                Text(
                  '${unallocated.length} ${unallocated.length == 1 ? 'rock has' : 'rocks have'} '
                  'no day. They stay on the list but the mornings won\'t pre-place them.',
                  style: const TextStyle(color: KColors.amber, fontSize: 12),
                ),
              if (_rocks.isEmpty)
                const Text(
                  'No rocks. Commit still records that the week was looked at.',
                  style: TextStyle(color: KColors.textMuted, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _monthName(int m) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];
}
