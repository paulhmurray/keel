import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/helm/day_plan_logic.dart';
import '../../shared/theme/keel_colors.dart';

// ---------------------------------------------------------------------------
// Helm — the global daily time-blocking planner (Cal Newport style).
//
// One page per day: a time grid of 30-minute slots from 06:00 to 21:00,
// one column per revision. The morning ritual builds revision 0; when the
// day breaks, "Revise from now" opens a new column governing the rest of
// the day while the old column stays as the honest record. The rail on
// the right surfaces raw material from EVERY project — carry-over,
// overdue and due-today actions, unowned risks, pending decisions — to
// drag onto the grid.
// ---------------------------------------------------------------------------

const int kHelmDayStart = 6 * 60; // 06:00
const int kHelmDayEnd = 21 * 60; // 21:00
const int kHelmSlotMinutes = 30;
const double kHelmSlotHeight = 30.0;
const double kHelmColumnWidth = 216.0;

const List<(String, String)> kBlockKinds = [
  ('focus', 'Focus'),
  ('meeting', 'Meeting'),
  ('admin', 'Admin'),
  ('break', 'Break'),
  // Life outside work that the plan must protect — school pickup, an
  // appointment. Blocking it stops work from silently eating it.
  ('home', 'Home'),
];

Color blockKindColor(String kind) => switch (kind) {
      'meeting' => KColors.blue,
      'admin' => KColors.amber,
      'break' => KColors.textMuted,
      'home' => KColors.violet,
      _ => KColors.phosphor,
    };

Color blockKindDimColor(String kind) => switch (kind) {
      'meeting' => KColors.blueDim,
      'admin' => KColors.amberDim,
      'break' => KColors.surface2,
      'home' => KColors.violetDim,
      _ => KColors.phosDim,
    };

String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

int _nowMinute() {
  final now = DateTime.now();
  return now.hour * 60 + now.minute;
}

/// Payload for dragging a rail item onto the grid.
class _RailDrag {
  final String label;
  final String kind;
  final String? projectId;
  final String? linkedActionId;
  const _RailDrag({
    required this.label,
    required this.kind,
    this.projectId,
    this.linkedActionId,
  });
}

class HelmView extends StatefulWidget {
  // Rail item click-through. Items come from EVERY project, so the shell
  // switches the active project before navigating + opening the dialog.
  final void Function(ProjectAction)? onOpenAction;
  final void Function(Risk)? onOpenRisk;
  final void Function(Issue)? onOpenIssue;
  final void Function(Assumption)? onOpenAssumption;
  final void Function(ProgramDependency)? onOpenDependency;
  final void Function(Decision)? onOpenDecision;

  const HelmView({
    super.key,
    this.onOpenAction,
    this.onOpenRisk,
    this.onOpenIssue,
    this.onOpenAssumption,
    this.onOpenDependency,
    this.onOpenDecision,
  });

  @override
  State<HelmView> createState() => _HelmViewState();
}

class _HelmViewState extends State<HelmView> {
  DateTime _date = DateTime.now();
  Timer? _clock;

  // Streams are memoized, NOT created in build: the minute tick calls
  // setState, and a rebuild that hands StreamBuilder a fresh stream makes
  // it resubscribe and drop to its no-data state — a whole-page flicker
  // every minute. Reusing the same stream instance keeps rebuilds paint-only.
  Stream<DayPlan?>? _planStream;
  String? _planStreamDate;
  Stream<List<DayPlanBlock>>? _blocksStream;
  String? _blocksStreamPlanId;

  bool get _isToday => _isoDate(_date) == _isoDate(DateTime.now());

  @override
  void initState() {
    super.initState();
    // Minute tick keeps the now-line and NOW highlight honest.
    _clock = Timer.periodic(
        const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Stream<DayPlan?> _planStreamFor(AppDatabase db, String dateIso) {
    if (_planStreamDate != dateIso) {
      _planStreamDate = dateIso;
      _planStream = db.dayPlanDao.watchPlanForDate(dateIso);
      _blocksStreamPlanId = null;
      _blocksStream = null;
    }
    return _planStream!;
  }

  Stream<List<DayPlanBlock>> _blocksStreamFor(
      AppDatabase db, String planId) {
    if (_blocksStreamPlanId != planId) {
      _blocksStreamPlanId = planId;
      _blocksStream = db.dayPlanDao.watchBlocksForPlan(planId);
    }
    return _blocksStream!;
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final dateIso = _isoDate(_date);

    return Column(
      children: [
        _HelmHeader(
          date: _date,
          isToday: _isToday,
          onPrev: () =>
              setState(() => _date = _date.subtract(const Duration(days: 1))),
          onNext: () =>
              setState(() => _date = _date.add(const Duration(days: 1))),
          onToday: () => setState(() => _date = DateTime.now()),
        ),
        Expanded(
          child: StreamBuilder<DayPlan?>(
            stream: _planStreamFor(db, dateIso),
            builder: (context, planSnap) {
              if (planSnap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(strokeWidth: 1.5));
              }
              final plan = planSnap.data;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: plan == null
                        ? _EmptyDay(
                            isToday: _isToday,
                            onChart: () => db.dayPlanDao
                                .getOrCreatePlanForDate(dateIso),
                          )
                        : StreamBuilder<List<DayPlanBlock>>(
                            stream: _blocksStreamFor(db, plan.id),
                            builder: (context, blockSnap) {
                              return _TimeGrid(
                                plan: plan,
                                blocks: blockSnap.data ?? const [],
                                isToday: _isToday,
                                db: db,
                              );
                            },
                          ),
                  ),
                  Container(width: 1, color: KColors.border),
                  _PlanningRail(
                    db: db,
                    date: _date,
                    onOpenAction: widget.onOpenAction,
                    onOpenRisk: widget.onOpenRisk,
                    onOpenIssue: widget.onOpenIssue,
                    onOpenAssumption: widget.onOpenAssumption,
                    onOpenDependency: widget.onOpenDependency,
                    onOpenDecision: widget.onOpenDecision,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _HelmHeader extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final VoidCallback onPrev, onNext, onToday;

  const _HelmHeader({
    required this.date,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: KColors.surface,
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      // The centre pane can get narrow with both side panels open —
      // shed the legend first, then the weekday, rather than overflow.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLegend = constraints.maxWidth >= 920;
          final compactDate = constraints.maxWidth < 640;
          final label = compactDate
              ? '${date.day} ${_months[date.month - 1]} ${date.year}'
              : '${_weekdays[date.weekday - 1]} ${date.day} '
                  '${_months[date.month - 1]} ${date.year}';
          return Row(
            children: [
              Text(
                'HELM',
                style: GoogleFonts.syne(
                  color: KColors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'my day',
                style: TextStyle(color: KColors.textMuted, fontSize: 12),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.chevron_left,
                    size: 18, color: KColors.textDim),
                onPressed: onPrev,
                tooltip: 'Previous day',
              ),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: KColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right,
                    size: 18, color: KColors.textDim),
                onPressed: onNext,
                tooltip: 'Next day',
              ),
              if (!isToday)
                TextButton(
                  onPressed: onToday,
                  child: const Text('Today',
                      style:
                          TextStyle(color: KColors.amber, fontSize: 12)),
                ),
              const Spacer(),
              if (showLegend)
                for (final (kind, label) in kBlockKinds) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: blockKindColor(kind),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(label,
                      style: const TextStyle(
                          color: KColors.textDim, fontSize: 11)),
                  const SizedBox(width: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyDay extends StatelessWidget {
  final bool isToday;
  final VoidCallback onChart;

  const _EmptyDay({required this.isToday, required this.onChart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.explore_outlined,
              size: 48, color: KColors.textMuted),
          const SizedBox(height: 16),
          Text(
            isToday ? 'Chart your day' : 'No plan for this day',
            style: GoogleFonts.syne(
              color: KColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 380,
            child: Text(
              'Block the day in 30-minute slots — meetings, focus work on '
              'actions, admin. When the day changes course, revise the '
              'remainder in a new column and keep the original as the record.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: KColors.textDim, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onChart,
            icon: const Icon(Icons.grid_on_outlined, size: 16),
            label: Text(isToday ? 'Start today\'s plan' : 'Plan this day'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Time grid — one column per revision
// ---------------------------------------------------------------------------

class _TimeGrid extends StatelessWidget {
  final DayPlan plan;
  final List<DayPlanBlock> blocks;
  final bool isToday;
  final AppDatabase db;

  const _TimeGrid({
    required this.plan,
    required this.blocks,
    required this.isToday,
    required this.db,
  });

  @override
  Widget build(BuildContext context) {
    final starts = parseRevisionStarts(plan.revisionStartsJson);
    final revisions = plan.currentRevision + 1;
    final gridHeight = (kHelmDayEnd - kHelmDayStart) /
        kHelmSlotMinutes *
        kHelmSlotHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Flexible(child: _focusSummary(starts)),
              const Spacer(),
              if (isToday)
                Tooltip(
                  message:
                      'The day changed course? Redraw the remainder in a '
                      'new column — the original plan stays as the record.',
                  child: OutlinedButton.icon(
                    onPressed: () => _reviseFromNow(context, starts),
                    icon: const Icon(Icons.alt_route,
                        size: 14, color: KColors.amber),
                    label: const Text('Revise from now',
                        style:
                            TextStyle(color: KColors.amber, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: KColors.amber, width: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TimeAxis(height: gridHeight),
                  for (var r = 0; r < revisions; r++)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _RevisionColumn(
                        plan: plan,
                        revision: r,
                        isLatest: r == plan.currentRevision,
                        revisionStarts: starts,
                        blocks: blocks
                            .where((b) => b.revision == r)
                            .toList(),
                        isToday: isToday,
                        db: db,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _focusSummary(List<int> starts) {
    final schedule = effectiveSchedule(blocks, starts);
    final focusMinutes = schedule
        .where((b) => b.kind == 'focus')
        .fold<int>(0, (sum, b) => sum + (b.endMinute - b.startMinute));
    final meetingMinutes = schedule
        .where((b) => b.kind == 'meeting')
        .fold<int>(0, (sum, b) => sum + (b.endMinute - b.startMinute));
    String fmt(int m) =>
        m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}h${m % 60}m';
    return Text(
      'Focus ${fmt(focusMinutes)} · Meetings ${fmt(meetingMinutes)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.jetBrainsMono(
          color: KColors.textDim, fontSize: 12),
    );
  }

  Future<void> _reviseFromNow(
      BuildContext context, List<int> starts) async {
    var at = (_nowMinute() ~/ kHelmSlotMinutes) * kHelmSlotMinutes;
    at = at.clamp(kHelmDayStart, kHelmDayEnd - kHelmSlotMinutes);
    final lastStart = starts.isEmpty ? kHelmDayStart : starts.last;
    if (at <= lastStart) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Already revised from this point — adjust the latest '
                  'column instead.')));
      return;
    }
    await db.dayPlanDao.startRevision(plan.id, at);
  }
}

class _TimeAxis extends StatelessWidget {
  final double height;
  const _TimeAxis({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: height + 20,
      child: Stack(
        children: [
          for (var m = kHelmDayStart; m <= kHelmDayEnd; m += 60)
            Positioned(
              top: (m - kHelmDayStart) /
                      kHelmSlotMinutes *
                      kHelmSlotHeight +
                  14,
              right: 6,
              child: Text(
                formatMinute(m),
                style: GoogleFonts.jetBrainsMono(
                    color: KColors.textMuted, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class _RevisionColumn extends StatelessWidget {
  final DayPlan plan;
  final int revision;
  final bool isLatest;
  final List<int> revisionStarts;
  final List<DayPlanBlock> blocks;
  final bool isToday;
  final AppDatabase db;

  const _RevisionColumn({
    required this.plan,
    required this.revision,
    required this.isLatest,
    required this.revisionStarts,
    required this.blocks,
    required this.isToday,
    required this.db,
  });

  /// The minute this column starts governing (rev 0 = start of day).
  int get _columnStart =>
      revision == 0 ? kHelmDayStart : revisionStarts[revision - 1];

  @override
  Widget build(BuildContext context) {
    final gridHeight = (kHelmDayEnd - kHelmDayStart) /
        kHelmSlotMinutes *
        kHelmSlotHeight;
    final slotCount =
        (kHelmDayEnd - kHelmDayStart) ~/ kHelmSlotMinutes;
    final nowMin = _nowMinute();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: Text(
            revision == 0
                ? 'PLAN'
                : 'REV $revision · from ${formatMinute(_columnStart)}',
            style: GoogleFonts.jetBrainsMono(
              color: isLatest ? KColors.amber : KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Container(
          width: kHelmColumnWidth,
          height: gridHeight,
          decoration: BoxDecoration(
            border: Border.all(
                color: isLatest ? KColors.border2 : KColors.border),
            borderRadius: BorderRadius.circular(4),
            color: isLatest ? KColors.surface : KColors.bg,
          ),
          child: Stack(
            children: [
              // Slot lattice — drop targets + tap-to-create on the
              // latest column, from its governing start onward.
              for (var s = 0; s < slotCount; s++)
                _slotCell(context, s),
              // Blocks
              for (final b in blocks) _positionedBlock(context, b),
              // Now line
              if (isToday && nowMin >= kHelmDayStart && nowMin <= kHelmDayEnd)
                Positioned(
                  top: (nowMin - kHelmDayStart) /
                      kHelmSlotMinutes *
                      kHelmSlotHeight,
                  left: 0,
                  right: 0,
                  child: Container(height: 1.5, color: KColors.red),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _slotCell(BuildContext context, int slotIndex) {
    final minute = kHelmDayStart + slotIndex * kHelmSlotMinutes;
    final editable = isLatest && minute >= _columnStart;
    final isHour = minute % 60 == 0;
    final cell = Positioned(
      top: slotIndex * kHelmSlotHeight,
      left: 0,
      right: 0,
      height: kHelmSlotHeight,
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (d) =>
            editable &&
            (d.data is _RailDrag || d.data is DayPlanBlock),
        onAcceptWithDetails: (d) => _dropOnSlot(d.data, minute),
        builder: (context, candidates, _) {
          return InkWell(
            onTap: editable ? () => _createAt(context, minute) : null,
            child: Container(
              decoration: BoxDecoration(
                color: candidates.isNotEmpty
                    ? KColors.amber.withValues(alpha: 0.15)
                    : (editable
                        ? Colors.transparent
                        : KColors.bg.withValues(alpha: 0.4)),
                border: Border(
                  top: BorderSide(
                    color: isHour ? KColors.border2 : KColors.border,
                    width: slotIndex == 0 ? 0 : 1,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    return cell;
  }

  Future<void> _dropOnSlot(Object payload, int minute) async {
    if (payload is DayPlanBlock) {
      await db.dayPlanDao.moveBlock(plan.id, payload.id, minute);
    } else if (payload is _RailDrag) {
      await db.dayPlanDao.insertBlock(
        planId: plan.id,
        revision: revision,
        startMinute: minute,
        endMinute: minute + kHelmSlotMinutes,
        label: payload.label,
        kind: payload.kind,
        projectId: payload.projectId,
        linkedActionId: payload.linkedActionId,
      );
    }
  }

  Future<void> _createAt(BuildContext context, int minute) async {
    final result = await showDialog<_BlockDialogResult>(
      context: context,
      builder: (_) => _BlockDialog(
        startMinute: minute,
        endMinute: minute + kHelmSlotMinutes,
      ),
    );
    if (result == null || result.deleted) return;
    await db.dayPlanDao.insertBlock(
      planId: plan.id,
      revision: revision,
      startMinute: result.startMinute,
      endMinute: result.endMinute,
      label: result.label,
      kind: result.kind,
    );
  }

  Widget _positionedBlock(BuildContext context, DayPlanBlock b) {
    final superseded = isBlockSuperseded(b, revisionStarts);
    final top =
        (b.startMinute - kHelmDayStart) / kHelmSlotMinutes * kHelmSlotHeight;
    final height = (b.endMinute - b.startMinute) /
        kHelmSlotMinutes *
        kHelmSlotHeight;

    final card = _BlockCard(
      block: b,
      superseded: superseded,
      height: height,
      onToggleDone: superseded
          ? null
          : () => db.dayPlanDao.setBlockDone(plan.id, b.id, !b.done),
      onTap: superseded ? null : () => _editBlock(context, b),
    );

    Widget child = card;
    // Only the latest column is a live plan — its blocks can be dragged
    // to another slot when the schedule shifts slightly (bigger changes
    // deserve a revision).
    if (isLatest && !superseded) {
      child = Draggable<Object>(
        data: b,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: kHelmColumnWidth - 8,
            child: Opacity(opacity: 0.85, child: card),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: card),
        child: card,
      );
    }

    return Positioned(
      top: top + 1,
      left: 3,
      right: 3,
      height: height - 2,
      child: child,
    );
  }

  Future<void> _editBlock(BuildContext context, DayPlanBlock b) async {
    final result = await showDialog<_BlockDialogResult>(
      context: context,
      builder: (_) => _BlockDialog(
        startMinute: b.startMinute,
        endMinute: b.endMinute,
        label: b.label,
        kind: b.kind,
        isEdit: true,
      ),
    );
    if (result == null) return;
    if (result.deleted) {
      await db.dayPlanDao.deleteBlock(plan.id, b.id);
      return;
    }
    await db.dayPlanDao.updateBlock(
      plan.id,
      DayPlanBlocksCompanion(
        id: Value(b.id),
        startMinute: Value(result.startMinute),
        endMinute: Value(result.endMinute),
        label: Value(result.label),
        kind: Value(result.kind),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final DayPlanBlock block;
  final bool superseded;
  final double height;
  final VoidCallback? onToggleDone;
  final VoidCallback? onTap;

  const _BlockCard({
    required this.block,
    required this.superseded,
    required this.height,
    this.onToggleDone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = blockKindColor(block.kind);
    final showTime = height >= kHelmSlotHeight * 2 - 4;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: superseded
              ? KColors.surface2.withValues(alpha: 0.5)
              : blockKindDimColor(block.kind),
          border: Border(
            left: BorderSide(
                color: superseded
                    ? KColors.textMuted.withValues(alpha: 0.4)
                    : color,
                width: 2),
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.label,
                    maxLines: showTime ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: superseded ? KColors.textMuted : KColors.text,
                      fontSize: 11,
                      height: 1.2,
                      decoration: superseded || block.done
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: KColors.textMuted,
                    ),
                  ),
                  if (showTime)
                    Text(
                      '${formatMinute(block.startMinute)}–${formatMinute(block.endMinute)}',
                      style: GoogleFonts.jetBrainsMono(
                        color: KColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
            if (onToggleDone != null)
              InkWell(
                onTap: onToggleDone,
                child: Icon(
                  block.done
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 13,
                  color: block.done ? KColors.phosphor : KColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Block create/edit dialog
// ---------------------------------------------------------------------------

class _BlockDialogResult {
  final String label;
  final String kind;
  final int startMinute;
  final int endMinute;
  final bool deleted;
  const _BlockDialogResult({
    required this.label,
    required this.kind,
    required this.startMinute,
    required this.endMinute,
    this.deleted = false,
  });
}

class _BlockDialog extends StatefulWidget {
  final int startMinute;
  final int endMinute;
  final String label;
  final String kind;
  final bool isEdit;

  const _BlockDialog({
    required this.startMinute,
    required this.endMinute,
    this.label = '',
    this.kind = 'focus',
    this.isEdit = false,
  });

  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  late final TextEditingController _labelCtrl;
  late String _kind;
  late int _start;
  late int _end;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.label);
    _kind = widget.kind;
    _start = widget.startMinute;
    _end = widget.endMinute;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<int>> _timeItems(int from, int to) => [
        for (var m = from; m <= to; m += kHelmSlotMinutes)
          DropdownMenuItem(
            value: m,
            child: Text(formatMinute(m),
                style: GoogleFonts.jetBrainsMono(fontSize: 12)),
          ),
      ];

  void _save() {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty || _end <= _start) return;
    Navigator.of(context).pop(_BlockDialogResult(
      label: label,
      kind: _kind,
      startMinute: _start,
      endMinute: _end,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEdit ? 'Edit block' : 'New block'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'What are you doing?'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'Kind'),
              items: [
                for (final (value, label) in kBlockKinds)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'focus'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _start,
                    decoration:
                        const InputDecoration(labelText: 'Start'),
                    items: _timeItems(
                        kHelmDayStart, kHelmDayEnd - kHelmSlotMinutes),
                    onChanged: (v) => setState(() {
                      _start = v ?? _start;
                      if (_end <= _start) {
                        _end = _start + kHelmSlotMinutes;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _end,
                    decoration: const InputDecoration(labelText: 'End'),
                    items: _timeItems(
                        kHelmDayStart + kHelmSlotMinutes, kHelmDayEnd),
                    onChanged: (v) => setState(() => _end = v ?? _end),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (widget.isEdit)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
                const _BlockDialogResult(
                    label: '',
                    kind: '',
                    startMinute: 0,
                    endMinute: 0,
                    deleted: true)),
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

// ---------------------------------------------------------------------------
// Planning rail — raw material from every project
// ---------------------------------------------------------------------------

class _PlanningRail extends StatefulWidget {
  final AppDatabase db;
  final DateTime date;
  final void Function(ProjectAction)? onOpenAction;
  final void Function(Risk)? onOpenRisk;
  final void Function(Issue)? onOpenIssue;
  final void Function(Assumption)? onOpenAssumption;
  final void Function(ProgramDependency)? onOpenDependency;
  final void Function(Decision)? onOpenDecision;

  const _PlanningRail({
    required this.db,
    required this.date,
    this.onOpenAction,
    this.onOpenRisk,
    this.onOpenIssue,
    this.onOpenAssumption,
    this.onOpenDependency,
    this.onOpenDecision,
  });

  @override
  State<_PlanningRail> createState() => _PlanningRailState();
}

class _PlanningRailState extends State<_PlanningRail> {
  // false = Suggested (the urgent slices), true = All (the full open books).
  // Suggested is always the default; All starts fully collapsed so the
  // portfolio-wide lists only unfold section by section on request.
  bool _browse = false;
  final Set<String> _expandedSections = {};

  // Memoized streams — the parent's minute tick rebuilds this subtree,
  // and inline-created streams would make every section resubscribe and
  // blink empty once a minute. Re-anchored only when the date changes.
  late Stream<List<HelmActionItem>> _dueToday;
  late Stream<List<HelmActionItem>> _overdue;
  late Stream<List<HelmRiskItem>> _unownedRisks;
  late Stream<List<HelmDecisionItem>> _pendingDecisions;
  late Stream<List<HelmActionItem>> _allActions;
  late Stream<List<HelmRiskItem>> _allRisks;
  late Stream<List<HelmIssueItem>> _allIssues;
  late Stream<List<HelmAssumptionItem>> _allAssumptions;
  late Stream<List<HelmDependencyItem>> _allDependencies;
  Stream<DayPlan?>? _carryPlanStream;
  String? _carryDateIso;
  Stream<List<DayPlanBlock>>? _carryBlocksStream;
  String? _carryPlanId;

  AppDatabase get db => widget.db;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void didUpdateWidget(covariant _PlanningRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      // Day navigation re-anchors the "today"-relative queries.
      _initStreams();
      _carryDateIso = null;
      _carryPlanStream = null;
      _carryPlanId = null;
      _carryBlocksStream = null;
    }
  }

  void _initStreams() {
    final dao = db.dayPlanDao;
    _dueToday = dao.watchActionsDueTodayAllProjects();
    _overdue = dao.watchOverdueActionsAllProjects();
    _unownedRisks = dao.watchUnownedOpenRisksAllProjects();
    _pendingDecisions = dao.watchPendingDecisionsAllProjects();
    _allActions = dao.watchOpenActionsAllProjects();
    _allRisks = dao.watchOpenRisksAllProjects();
    _allIssues = dao.watchOpenIssuesAllProjects();
    _allAssumptions = dao.watchOpenAssumptionsAllProjects();
    _allDependencies = dao.watchOpenDependenciesAllProjects();
  }

  bool _isExpanded(String key) => _expandedSections.contains(key);

  void _toggleSection(String key) {
    setState(() {
      if (!_expandedSections.remove(key)) _expandedSections.add(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final yesterdayIso =
        _isoDate(widget.date.subtract(const Duration(days: 1)));
    return Container(
      width: 300,
      color: KColors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, 2),
              child: Text(
                'PLANNING MATERIAL',
                style: TextStyle(
                  color: KColors.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'Drag onto the grid to block time · click to open.',
                style: TextStyle(color: KColors.textMuted, fontSize: 11),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Row(
                children: [
                  _RailModeChip(
                    label: 'Suggested',
                    selected: !_browse,
                    onTap: () => setState(() => _browse = false),
                  ),
                  const SizedBox(width: 6),
                  _RailModeChip(
                    label: 'All items',
                    selected: _browse,
                    // Every entry into All starts fully collapsed — the
                    // counts give the overview, expansion is opt-in.
                    onTap: () => setState(() {
                      _browse = true;
                      _expandedSections.clear();
                    }),
                  ),
                ],
              ),
            ),
            if (_browse) ..._browseSections() else ..._suggestedSections(yesterdayIso),
          ],
        ),
      ),
    );
  }

  List<Widget> _suggestedSections(String yesterdayIso) => [
        _carryOverSection(yesterdayIso),
        _actionSection(
          title: 'Due today',
          icon: Icons.today_outlined,
          stream: _dueToday,
          barColor: KColors.amber,
        ),
        _actionSection(
          title: 'Overdue',
          icon: Icons.warning_amber_rounded,
          stream: _overdue,
          barColor: KColors.red,
        ),
        _riskSection(
          title: 'Risks needing an owner',
          stream: _unownedRisks,
          cap: 5,
        ),
        _decisionSection(cap: 5),
      ];

  List<Widget> _browseSections() => [
        _actionSection(
          title: 'Open actions',
          icon: Icons.check_circle_outline,
          stream: _allActions,
          barColor: KColors.phosphor,
          showCount: true,
          collapseKey: 'actions',
        ),
        _riskSection(
          title: 'Open risks',
          stream: _allRisks,
          showCount: true,
          collapseKey: 'risks',
        ),
        _issueSection(),
        _assumptionSection(),
        _dependencySection(),
        _decisionSection(showCount: true, collapseKey: 'decisions'),
      ];

  Widget _carryOverSection(String yesterdayIso) {
    if (_carryDateIso != yesterdayIso) {
      _carryDateIso = yesterdayIso;
      _carryPlanStream = db.dayPlanDao.watchPlanForDate(yesterdayIso);
      _carryPlanId = null;
      _carryBlocksStream = null;
    }
    return StreamBuilder<DayPlan?>(
      stream: _carryPlanStream,
      builder: (context, planSnap) {
        final plan = planSnap.data;
        if (plan == null) return const SizedBox.shrink();
        if (_carryPlanId != plan.id) {
          _carryPlanId = plan.id;
          _carryBlocksStream = db.dayPlanDao.watchBlocksForPlan(plan.id);
        }
        return StreamBuilder<List<DayPlanBlock>>(
          stream: _carryBlocksStream,
          builder: (context, blockSnap) {
            final starts = parseRevisionStarts(plan.revisionStartsJson);
            // Breaks and home blocks are time-bound, not carryable work —
            // yesterday's school pickup doesn't roll into today's backlog.
            final unfinished =
                effectiveSchedule(blockSnap.data ?? const [], starts)
                    .where((b) =>
                        !b.done && b.kind != 'break' && b.kind != 'home')
                    .toList();
            if (unfinished.isEmpty) return const SizedBox.shrink();
            return _RailSection(
              title: 'Carry-over — yesterday',
              icon: Icons.history,
              children: [
                for (final b in unfinished.take(6))
                  _RailItem(
                    label: b.label,
                    detail:
                        '${formatMinute(b.startMinute)}–${formatMinute(b.endMinute)} yesterday',
                    barColor: blockKindColor(b.kind),
                    payload: _RailDrag(
                      label: b.label,
                      kind: b.kind,
                      projectId: b.projectId,
                      linkedActionId: b.linkedActionId,
                    ),
                    onTap: b.linkedActionId == null
                        ? null
                        : () async {
                            final a = await db.actionsDao
                                .getActionById(b.linkedActionId!);
                            if (a != null) widget.onOpenAction?.call(a);
                          },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _actionSection({
    required String title,
    required IconData icon,
    required Stream<List<HelmActionItem>> stream,
    required Color barColor,
    int? cap = 8,
    bool showCount = false,
    String? collapseKey,
  }) {
    return StreamBuilder<List<HelmActionItem>>(
      stream: stream,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        final shown = showCount ? items : items.take(cap ?? items.length);
        return _RailSection(
          title: title,
          icon: icon,
          count: showCount ? items.length : null,
          expanded: collapseKey == null ? null : _isExpanded(collapseKey),
          onToggle: collapseKey == null
              ? null
              : () => _toggleSection(collapseKey),
          children: [
            for (final item in shown)
              _RailItem(
                label: item.action.description,
                detail: item.projectName,
                barColor: barColor,
                payload: _RailDrag(
                  label: item.action.description,
                  kind: 'focus',
                  projectId: item.action.projectId,
                  linkedActionId: item.action.id,
                ),
                onTap: widget.onOpenAction == null
                    ? null
                    : () => widget.onOpenAction!(item.action),
              ),
          ],
        );
      },
    );
  }

  Widget _riskSection({
    required String title,
    required Stream<List<HelmRiskItem>> stream,
    int? cap,
    bool showCount = false,
    String? collapseKey,
  }) {
    return StreamBuilder<List<HelmRiskItem>>(
      stream: stream,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        final shown = cap == null ? items : items.take(cap);
        return _RailSection(
          title: title,
          icon: Icons.shield_outlined,
          count: showCount ? items.length : null,
          expanded: collapseKey == null ? null : _isExpanded(collapseKey),
          onToggle: collapseKey == null
              ? null
              : () => _toggleSection(collapseKey),
          children: [
            for (final item in shown)
              _RailItem(
                label: item.risk.description,
                detail: item.projectName,
                barColor: KColors.amber,
                payload: _RailDrag(
                  label: 'Risk: ${item.risk.description}',
                  kind: 'admin',
                  projectId: item.risk.projectId,
                ),
                onTap: widget.onOpenRisk == null
                    ? null
                    : () => widget.onOpenRisk!(item.risk),
              ),
          ],
        );
      },
    );
  }

  Widget _issueSection() {
    return StreamBuilder<List<HelmIssueItem>>(
      stream: _allIssues,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return _RailSection(
          title: 'Open issues',
          icon: Icons.error_outline,
          count: items.length,
          expanded: _isExpanded('issues'),
          onToggle: () => _toggleSection('issues'),
          children: [
            for (final item in items)
              _RailItem(
                label: item.issue.title?.isNotEmpty == true
                    ? item.issue.title!
                    : item.issue.description,
                detail: item.projectName,
                barColor: KColors.red,
                payload: _RailDrag(
                  label: 'Issue: '
                      '${item.issue.title?.isNotEmpty == true ? item.issue.title! : item.issue.description}',
                  kind: 'focus',
                  projectId: item.issue.projectId,
                ),
                onTap: widget.onOpenIssue == null
                    ? null
                    : () => widget.onOpenIssue!(item.issue),
              ),
          ],
        );
      },
    );
  }

  Widget _assumptionSection() {
    return StreamBuilder<List<HelmAssumptionItem>>(
      stream: _allAssumptions,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return _RailSection(
          title: 'Open assumptions',
          icon: Icons.psychology_outlined,
          count: items.length,
          expanded: _isExpanded('assumptions'),
          onToggle: () => _toggleSection('assumptions'),
          children: [
            for (final item in items)
              _RailItem(
                label: item.assumption.description,
                detail: item.projectName,
                barColor: KColors.blue,
                payload: _RailDrag(
                  label: 'Validate: ${item.assumption.description}',
                  kind: 'admin',
                  projectId: item.assumption.projectId,
                ),
                onTap: widget.onOpenAssumption == null
                    ? null
                    : () => widget.onOpenAssumption!(item.assumption),
              ),
          ],
        );
      },
    );
  }

  Widget _dependencySection() {
    return StreamBuilder<List<HelmDependencyItem>>(
      stream: _allDependencies,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return _RailSection(
          title: 'Open dependencies',
          icon: Icons.link_outlined,
          count: items.length,
          expanded: _isExpanded('dependencies'),
          onToggle: () => _toggleSection('dependencies'),
          children: [
            for (final item in items)
              _RailItem(
                label: item.dependency.description,
                detail: item.projectName,
                barColor: KColors.violet,
                payload: _RailDrag(
                  label: 'Chase: ${item.dependency.description}',
                  kind: 'admin',
                  projectId: item.dependency.projectId,
                ),
                onTap: widget.onOpenDependency == null
                    ? null
                    : () => widget.onOpenDependency!(item.dependency),
              ),
          ],
        );
      },
    );
  }

  Widget _decisionSection({
    int? cap,
    bool showCount = false,
    String? collapseKey,
  }) {
    return StreamBuilder<List<HelmDecisionItem>>(
      stream: _pendingDecisions,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        final shown = cap == null ? items : items.take(cap);
        return _RailSection(
          title: 'Pending decisions',
          icon: Icons.gavel_outlined,
          count: showCount ? items.length : null,
          expanded: collapseKey == null ? null : _isExpanded(collapseKey),
          onToggle: collapseKey == null
              ? null
              : () => _toggleSection(collapseKey),
          children: [
            for (final item in shown)
              _RailItem(
                label: item.decision.description,
                detail: item.projectName,
                barColor: KColors.blue,
                payload: _RailDrag(
                  label: 'Decide: ${item.decision.description}',
                  kind: 'admin',
                  projectId: item.decision.projectId,
                ),
                onTap: widget.onOpenDecision == null
                    ? null
                    : () => widget.onOpenDecision!(item.decision),
              ),
          ],
        );
      },
    );
  }
}

class _RailModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RailModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? KColors.amberDim : KColors.surface2,
          border: Border.all(
              color: selected ? KColors.amber : KColors.border2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? KColors.amber : KColors.textDim,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _RailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final int? count;
  // Non-null [onToggle] makes the section collapsible: the header becomes
  // the toggle and [expanded] decides whether the items render.
  final bool? expanded;
  final VoidCallback? onToggle;
  final List<Widget> children;

  const _RailSection({
    required this.title,
    required this.icon,
    this.count,
    this.expanded,
    this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final collapsible = onToggle != null;
    final showItems = !collapsible || (expanded ?? false);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Row(
        children: [
          Icon(icon, size: 13, color: KColors.textDim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KColors.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
              ),
            ),
          ),
          if (count != null)
            Text(
              '$count',
              style: GoogleFonts.jetBrainsMono(
                color: KColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (collapsible) ...[
            const SizedBox(width: 4),
            Icon(
              showItems ? Icons.expand_more : Icons.chevron_right,
              size: 14,
              color: KColors.textMuted,
            ),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        collapsible ? InkWell(onTap: onToggle, child: header) : header,
        if (showItems) ...children,
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  final String label;
  final String detail;
  final Color barColor;
  final _RailDrag payload;
  final VoidCallback? onTap;

  const _RailItem({
    required this.label,
    required this.detail,
    required this.barColor,
    required this.payload,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 2,
            height: 32,
            color: barColor,
            margin: const EdgeInsets.only(right: 10, top: 2),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: KColors.text, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: KColors.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          const Icon(Icons.drag_indicator,
              size: 14, color: KColors.textMuted),
        ],
      ),
    );

    return Draggable<Object>(
      data: payload,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 260,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: KColors.surface2,
            border: Border.all(color: barColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: KColors.text, fontSize: 12),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      // Tap opens the item in its home section (drag still wins when the
      // pointer moves) — same pattern as the left-panel pulse rows.
      child: onTap != null
          ? MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: onTap, child: card),
            )
          : card,
    );
  }
}
