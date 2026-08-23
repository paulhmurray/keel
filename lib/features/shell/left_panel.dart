import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/helm/day_plan_logic.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/update_banner.dart';
import '../../shared/widgets/rag_badge.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../helm/helm_view.dart' show blockKindColor;

class LeftPanel extends StatelessWidget {
  // Section-level navigation (used when the section is empty or as a
  // header tap target — clicking a row prefers the item callbacks below).
  final VoidCallback? onNavigateToRaid;
  final VoidCallback? onNavigateToDecisions;
  final VoidCallback? onNavigateToActions;
  final VoidCallback? onNavigateToJournal;
  final VoidCallback? onNavigateToPlaybook;
  final VoidCallback? onNavigateToProgramme;

  // Item-level openers — invoked when the user clicks a specific row.
  // The shell wires these to navigate + open the relevant form dialog.
  final void Function(Risk)? onOpenRisk;
  final void Function(Decision)? onOpenDecision;
  final void Function(ProjectAction)? onOpenAction;
  final void Function(JournalEntry)? onOpenJournal;
  final void Function(String stageId)? onOpenPlaybookStage;

  // Helm is GLOBAL — the My Day section at the top stays put when the
  // active project changes.
  final VoidCallback? onNavigateToHelm;

  const LeftPanel({
    super.key,
    this.onNavigateToRaid,
    this.onNavigateToDecisions,
    this.onNavigateToActions,
    this.onNavigateToJournal,
    this.onNavigateToPlaybook,
    this.onNavigateToProgramme,
    this.onNavigateToHelm,
    this.onOpenRisk,
    this.onOpenDecision,
    this.onOpenAction,
    this.onOpenJournal,
    this.onOpenPlaybookStage,
  });

  @override
  Widget build(BuildContext context) {
    final projectProvider = context.watch<ProjectProvider>();
    final db = context.read<AppDatabase>();
    final projectId = projectProvider.currentProjectId;

    return Container(
      width: 240,
      color: KColors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // My Day rides above the project pulse and survives project
          // switches — the user's day is global. It gets the lion's share
          // of the panel (up to ~half) so the WHOLE day reads at a
          // glance; the pulse below is deliberately condensed.
          ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: constraints.maxHeight * 0.52),
            child: _MyDaySection(db: db, onOpen: onNavigateToHelm),
          ),
          Expanded(
            child: projectId == null
                ? _NoProjectPlaceholder()
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(
                          label: 'Top Risks',
                          icon: Icons.shield,
                        ),
                        _TopRisksSection(
                          projectId: projectId,
                          db: db,
                          onTap: onNavigateToRaid,
                          onOpenItem: onOpenRisk,
                        ),
                        _SectionHeader(
                          label: 'Pending Decisions',
                          icon: Icons.gavel,
                        ),
                        _TopDecisionsSection(
                          projectId: projectId,
                          db: db,
                          onTap: onNavigateToDecisions,
                          onOpenItem: onOpenDecision,
                        ),
                        _SectionHeader(
                          label: 'Overdue Actions',
                          icon: Icons.check_circle,
                        ),
                        _TopActionsSection(
                          projectId: projectId,
                          db: db,
                          onTap: onNavigateToActions,
                          onOpenItem: onOpenAction,
                        ),
                        _SectionHeader(label: 'Recent Journal', icon: Icons.menu_book_outlined),
                        _RecentJournalSection(
                          projectId: projectId,
                          db: db,
                          onTap: onNavigateToJournal,
                          onOpenItem: onOpenJournal,
                        ),
                        _SectionHeader(label: 'Playbook Stage', icon: Icons.account_tree_outlined),
                        _PlaybookStageSection(
                          projectId: projectId,
                          db: db,
                          onTap: onNavigateToPlaybook,
                          onOpenStage: onOpenPlaybookStage,
                        ),
                        _ProgrammeGapsSection(projectId: projectId, db: db, onTap: onNavigateToProgramme),
                        _UpcomingDeadlinesSection(projectId: projectId, db: db),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
          ),
          const StandardUpdateNotice(),
        ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My Day — the Helm readout. Global (not project-scoped): shows the
// current block by wall clock plus what's next, so the morning's plan
// stays in view all day. Distinct amber treatment marks it as "you"
// above "the project".
// ---------------------------------------------------------------------------

class _MyDaySection extends StatefulWidget {
  final AppDatabase db;
  final VoidCallback? onOpen;

  const _MyDaySection({required this.db, this.onOpen});

  @override
  State<_MyDaySection> createState() => _MyDaySectionState();
}

class _MyDaySectionState extends State<_MyDaySection> {
  Timer? _clock;

  // Memoized streams: the minute tick rebuilds this widget, and streams
  // created inline in build would make the StreamBuilders resubscribe
  // and blink to their empty state every tick. Re-anchored at midnight.
  Stream<DayPlan?>? _planStream;
  String? _planStreamDate;
  Stream<List<DayPlanBlock>>? _blocksStream;
  String? _blocksStreamPlanId;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(
        const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String get _todayIso {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Stream<DayPlan?> _planStreamForToday(String dateIso) {
    if (_planStreamDate != dateIso) {
      _planStreamDate = dateIso;
      _planStream = widget.db.dayPlanDao.watchPlanForDate(dateIso);
      _blocksStreamPlanId = null;
      _blocksStream = null;
    }
    return _planStream!;
  }

  Stream<List<DayPlanBlock>> _blocksStreamFor(String planId) {
    if (_blocksStreamPlanId != planId) {
      _blocksStreamPlanId = planId;
      _blocksStream = widget.db.dayPlanDao.watchBlocksForPlan(planId);
    }
    return _blocksStream!;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KColors.surface2,
        border: Border(
          left: BorderSide(color: KColors.amber, width: 2),
          bottom: BorderSide(color: KColors.border2, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: widget.onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.explore_outlined,
                      size: 13, color: KColors.amber),
                  const SizedBox(width: 6),
                  Text(
                    'MY DAY',
                    style: GoogleFonts.jetBrainsMono(
                      color: KColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right,
                      size: 14, color: KColors.textMuted),
                ],
              ),
            ),
          ),
          Flexible(
            child: StreamBuilder<DayPlan?>(
              stream: _planStreamForToday(_todayIso),
              builder: (context, planSnap) {
                final plan = planSnap.data;
                if (plan == null) {
                  return _myDayNote('No plan yet — chart your day.');
                }
                return StreamBuilder<List<DayPlanBlock>>(
                  stream: _blocksStreamFor(plan.id),
                  builder: (context, blockSnap) {
                    final blocks = blockSnap.data ?? const [];
                    final starts =
                        parseRevisionStarts(plan.revisionStartsJson);
                    final now = DateTime.now();
                    final nowMin = now.hour * 60 + now.minute;
                    // The WHOLE effective day, not just what's next —
                    // past blocks stay visible (dimmed) so the plan
                    // reads at a glance; scrolls when the day is packed.
                    final schedule = effectiveSchedule(blocks, starts);
                    final home =
                        imminentHomeBlock(blocks, starts, nowMin);
                    if (schedule.isEmpty) {
                      return _myDayNote('No blocks yet — chart your day.');
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (home != null)
                          _HomeCountdown(block: home, nowMin: nowMin),
                        Flexible(
                          child: GestureDetector(
                            onTap: widget.onOpen,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  for (final b in schedule)
                                    _MyDayRow(
                                      block: b,
                                      isNow: b.startMinute <= nowMin &&
                                          nowMin < b.endMinute,
                                      isPast: b.endMinute <= nowMin,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _myDayNote(String text) {
    return InkWell(
      onTap: widget.onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Text(
          text,
          style: const TextStyle(color: KColors.textDim, fontSize: 11),
        ),
      ),
    );
  }
}

/// The hard-stop banner: a home block is imminent (or in progress).
/// The whole point of blocking school pickup is not looking up at 15:31 —
/// this escalates from violet to red as the departure closes in.
class _HomeCountdown extends StatelessWidget {
  final DayPlanBlock block;
  final int nowMin;

  const _HomeCountdown({required this.block, required this.nowMin});

  @override
  Widget build(BuildContext context) {
    final minutesLeft = block.startMinute - nowMin;
    final started = minutesLeft <= 0;
    final urgent = started || minutesLeft <= 10;
    final fg = urgent ? KColors.red : KColors.violet;
    final bg = urgent ? KColors.redDim : KColors.violetDim;
    final headline = started
        ? 'GO NOW'
        : minutesLeft >= 60
            ? 'LEAVE IN 1H'
            : 'LEAVE IN ${minutesLeft}M';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: fg.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_walk, size: 14, color: fg),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: GoogleFonts.jetBrainsMono(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  '${formatMinute(block.startMinute)} · ${block.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: KColors.text, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyDayRow extends StatelessWidget {
  final DayPlanBlock block;
  final bool isNow;
  final bool isPast;

  const _MyDayRow({
    required this.block,
    required this.isNow,
    this.isPast = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = isNow
        ? KColors.text
        : isPast
            ? KColors.textMuted
            : KColors.textDim;
    return Container(
      color: isNow
          ? KColors.amber.withValues(alpha: 0.08)
          : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              formatMinute(block.startMinute),
              style: GoogleFonts.jetBrainsMono(
                color: isNow ? KColors.amber : KColors.textMuted,
                fontSize: 9,
                fontWeight: isNow ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Container(
            width: 2,
            height: 14,
            color: isPast
                ? blockKindColor(block.kind).withValues(alpha: 0.4)
                : blockKindColor(block.kind),
            margin: const EdgeInsets.only(right: 6),
          ),
          Expanded(
            child: Text(
              block.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: 11,
                fontWeight: isNow ? FontWeight.w600 : FontWeight.w400,
                // Strikethrough means DONE — a past block left unticked
                // stays legible; it's tomorrow's carry-over signal.
                decoration:
                    block.done ? TextDecoration.lineThrough : null,
                decorationColor: KColors.textMuted,
              ),
            ),
          ),
          if (isNow)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: KColors.amber,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'NOW',
                style: GoogleFonts.jetBrainsMono(
                  color: KColors.bg,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    // Deliberately tight — the pulse is the SMALL half of the panel now;
    // My Day above it gets the space.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
      child: Row(
        children: [
          Icon(icon, size: 12, color: KColors.textDim),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: KColors.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Top Risks ----

class _TopRisksSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;
  final void Function(Risk)? onOpenItem;

  const _TopRisksSection(
      {required this.projectId,
      required this.db,
      this.onTap,
      this.onOpenItem});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Risk>>(
      stream: db.raidDao.watchOpenRisksForProject(projectId),
      builder: (context, snap) {
        if (!snap.hasData) return const _PulseLoading();
        final sorted = snap.data!.toList()
          ..sort((a, b) =>
            (_score(b.likelihood) * _score(b.impact)) -
            (_score(a.likelihood) * _score(a.impact)));
        final risks = sorted.take(3).toList();
        if (risks.isEmpty) {
          return const _PulseEmpty(message: 'No open risks');
        }
        return Column(
          children: risks
              .map((r) => _PulseItem(
                    label: r.ref != null
                        ? '[${r.ref}] ${r.description}'
                        : r.description,
                    barColor: _riskBarColor(r.likelihood, r.impact),
                    trailing: RAGBadge(
                      rag: _riskRag(r.likelihood, r.impact),
                      showLabel: false,
                    ),
                    // Prefer the item-aware opener so the click navigates
                    // *and* opens the risk dialog; fall back to the
                    // section-level navigation if not wired.
                    onTap: onOpenItem != null
                        ? () => onOpenItem!(r)
                        : onTap,
                  ))
              .toList(),
        );
      },
    );
  }

  Color _riskBarColor(String likelihood, String impact) {
    final score = _score(likelihood) * _score(impact);
    if (score >= 9) return KColors.red;
    if (score >= 4) return KColors.amber;
    return KColors.phosphor;
  }

  String _riskRag(String likelihood, String impact) {
    final score = _score(likelihood) * _score(impact);
    if (score >= 9) return 'red';
    if (score >= 4) return 'amber';
    return 'green';
  }

  int _score(String val) {
    switch (val.toLowerCase()) {
      case 'high':
        return 3;
      case 'medium':
        return 2;
      default:
        return 1;
    }
  }
}

// ---- Top Decisions ----

class _TopDecisionsSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;
  final void Function(Decision)? onOpenItem;

  const _TopDecisionsSection(
      {required this.projectId,
      required this.db,
      this.onTap,
      this.onOpenItem});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Decision>>(
      stream: db.decisionsDao.watchPendingDecisionsForProject(projectId),
      builder: (context, snap) {
        if (!snap.hasData) return const _PulseLoading();
        final decisions = snap.data!.take(3).toList();
        if (decisions.isEmpty) {
          return const _PulseEmpty(message: 'No pending decisions');
        }
        return Column(
          children: decisions
              .map((d) => _PulseItem(
                    label: d.ref != null
                        ? '[${d.ref}] ${d.description}'
                        : d.description,
                    barColor: KColors.blue,
                    trailing: StatusChip(status: d.status),
                    onTap: onOpenItem != null
                        ? () => onOpenItem!(d)
                        : onTap,
                  ))
              .toList(),
        );
      },
    );
  }
}

// ---- Overdue Actions ----

class _TopActionsSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;
  final void Function(ProjectAction)? onOpenItem;

  const _TopActionsSection(
      {required this.projectId,
      required this.db,
      this.onTap,
      this.onOpenItem});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProjectAction>>(
      stream: db.actionsDao.watchOverdueActionsForProject(projectId),
      builder: (context, snap) {
        if (!snap.hasData) return const _PulseLoading();
        final actions = snap.data!.take(3).toList();
        if (actions.isEmpty) {
          return const _PulseEmpty(message: 'No overdue actions');
        }
        return Column(
          children: actions
              .map((a) => _PulseItem(
                    label: a.ref != null
                        ? '[${a.ref}] ${a.description}'
                        : a.description,
                    barColor: KColors.red,
                    trailing: a.dueDate != null
                        ? Text(
                            du.formatDate(a.dueDate),
                            style: const TextStyle(
                              color: KColors.red,
                              fontSize: 11,
                            ),
                          )
                        : null,
                    onTap: onOpenItem != null
                        ? () => onOpenItem!(a)
                        : onTap,
                  ))
              .toList(),
        );
      },
    );
  }
}

// ---- Helper Widgets ----

class _PulseItem extends StatelessWidget {
  final String label;
  final Color barColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _PulseItem({
    required this.label,
    required this.barColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Condensed single-line rows: the trailing badge sits beside the
    // label instead of under it, halving each row's height.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: KColors.border, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 2,
              height: 20,
              color: barColor,
              margin: const EdgeInsets.only(right: 8),
            ),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: KColors.text,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _PulseLoading extends StatelessWidget {
  const _PulseLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      child: SizedBox(
        height: 14,
        width: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
    );
  }
}

class _PulseEmpty extends StatelessWidget {
  final String message;

  const _PulseEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
      child: Text(
        message,
        style: const TextStyle(color: KColors.textMuted, fontSize: 12),
      ),
    );
  }
}

class _NoProjectPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Create or select a project to see live data.',
          textAlign: TextAlign.center,
          style: TextStyle(color: KColors.textDim, fontSize: 12),
        ),
      ),
    );
  }
}

class _RecentJournalSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;
  final void Function(JournalEntry)? onOpenItem;
  const _RecentJournalSection({
    required this.projectId,
    required this.db,
    this.onTap,
    this.onOpenItem,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<JournalEntry>>(
      stream: db.journalDao.watchRecentEntriesForProject(projectId, limit: 2),
      builder: (context, snap) {
        if (!snap.hasData) return const _PulseLoading();
        final entries = snap.data!;
        if (entries.isEmpty) return const _PulseEmpty(message: 'No journal entries');
        return Column(
          children: entries.map((e) {
            final title = e.title?.isNotEmpty == true
                ? e.title!
                : e.body.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => 'Entry');
            final cleaned = title.replaceAll(RegExp(r'^#+\s*'), '').trim();
            return _PulseItem(
              label: cleaned.isEmpty ? 'Journal entry' : cleaned,
              barColor: e.confirmedAt != null ? KColors.phosphor : KColors.amber,
              trailing: Text(
                _fmt(e.entryDate),
                style: const TextStyle(color: KColors.textDim, fontSize: 10),
              ),
              onTap: onOpenItem != null ? () => onOpenItem!(e) : onTap,
            );
          }).toList(),
        );
      },
    );
  }

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${m[dt.month-1]}';
    } catch (_) { return iso; }
  }
}

// ---------------------------------------------------------------------------
// Playbook stage section
// ---------------------------------------------------------------------------

class _PlaybookStageSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;
  final void Function(String stageId)? onOpenStage;

  const _PlaybookStageSection({
    required this.projectId,
    required this.db,
    this.onTap,
    this.onOpenStage,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProjectPlaybook?>(
      stream: db.playbookDao.watchProjectPlaybook(projectId),
      builder: (context, ppSnap) {
        if (!ppSnap.hasData || ppSnap.data == null) {
          return const _PulseEmpty(message: 'No playbook attached');
        }
        final pp = ppSnap.data!;
        return StreamBuilder<List<PlaybookStage>>(
          stream: db.playbookDao.watchStagesForPlaybook(pp.playbookId),
          builder: (context, stagesSnap) {
            return StreamBuilder<List<ProjectStageProgressesData>>(
              stream: db.playbookDao.watchProgressForProjectPlaybook(pp.id),
              builder: (context, progressSnap) {
                final stages = stagesSnap.data ?? [];
                final progressList = progressSnap.data ?? [];
                final progressMap = {
                  for (final p in progressList) p.stageId: p,
                };

                // Find current stage: first non-complete
                PlaybookStage? current;
                ProjectStageProgressesData? currentProgress;
                for (final s in stages) {
                  final prog = progressMap[s.id];
                  if (prog == null || prog.status != 'complete') {
                    current = s;
                    currentProgress = prog;
                    break;
                  }
                }

                if (current == null) {
                  return _PulseItem(
                    label: 'All stages complete',
                    barColor: KColors.phosphor,
                    onTap: onTap,
                  );
                }

                final status = currentProgress?.status ?? 'not_started';
                final barColor = switch (status) {
                  'in_progress' => KColors.amber,
                  'blocked' => KColors.red,
                  'pending_approval' => KColors.blue,
                  _ => KColors.textDim,
                };

                final checkedCount = _checkedCount(currentProgress?.checklist);
                final totalCount = _totalCount(currentProgress?.checklist);
                final stageIdx =
                    stages.indexWhere((s) => s.id == current!.id) + 1;

                final stageId = current.id;
                return _PulseItem(
                  label: 'Stage $stageIdx: ${current.name}',
                  barColor: barColor,
                  trailing: Text(
                    totalCount > 0
                        ? '${_statusLabel(status)} · $checkedCount/$totalCount'
                        : _statusLabel(status),
                    style: TextStyle(color: barColor, fontSize: 10),
                  ),
                  onTap: onOpenStage != null
                      ? () => onOpenStage!(stageId)
                      : onTap,
                );
              },
            );
          },
        );
      },
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'in_progress' => 'In progress',
        'blocked' => 'Blocked',
        'pending_approval' => 'Pending approval',
        'complete' => 'Complete',
        _ => 'Not started',
      };

  static int _checkedCount(String? json) {
    if (json == null) return 0;
    try {
      final items = jsonDecode(json) as List<dynamic>;
      return items.where((e) => (e as Map)['checked'] == true).length;
    } catch (_) {
      return 0;
    }
  }

  static int _totalCount(String? json) {
    if (json == null) return 0;
    try {
      return (jsonDecode(json) as List<dynamic>).length;
    } catch (_) {
      return 0;
    }
  }
}

// ---------------------------------------------------------------------------
// Upcoming Deadlines — hard-deadline milestones within 30 days, not achieved
// ---------------------------------------------------------------------------

class _UpcomingDeadlinesSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;

  const _UpcomingDeadlinesSection({
    required this.projectId,
    required this.db,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Milestone>>(
      stream: db.milestonesDao.watchForProject(projectId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final today = DateTime.now();
        final in30Days = today.add(const Duration(days: 30));
        final todayStr = today.toIso8601String().substring(0, 10);
        final in30Str = in30Days.toIso8601String().substring(0, 10);

        final upcoming = snap.data!
            .where((ms) =>
                ms.isHardDeadline &&
                ms.status != 'achieved' &&
                ms.date.isNotEmpty &&
                ms.date.compareTo(todayStr) >= 0 &&
                ms.date.compareTo(in30Str) <= 0)
            .take(2)
            .toList();

        if (upcoming.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
                label: 'Upcoming Deadlines',
                icon: Icons.diamond_outlined),
            ...upcoming.map((ms) => _PulseItem(
                  label: ms.name,
                  barColor: KColors.red,
                  trailing: Text(
                    ms.date,
                    style: const TextStyle(
                        color: KColors.red, fontSize: 10),
                  ),
                )),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Programme Gaps — sponsor + change manager alerts
// ---------------------------------------------------------------------------

class _ProgrammeGapsSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;

  const _ProgrammeGapsSection({
    required this.projectId,
    required this.db,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StakeholderRole>>(
      stream: db.stakeholderRoleDao.watchForProject(projectId),
      builder: (context, srSnap) {
        return StreamBuilder<List<TeamRole>>(
          stream: db.teamRoleDao.watchForProject(projectId),
          builder: (context, trSnap) {
            final stakeholderRoles = srSnap.data ?? [];
            final teamRoles = trSnap.data ?? [];

            final sponsorFilled = stakeholderRoles
                .where((r) =>
                    r.roleName == 'Programme Sponsor' &&
                    r.isApplicable &&
                    r.personId != null)
                .isNotEmpty;

            final changeMgrFilled = teamRoles
                .where((r) =>
                    r.roleName == 'Change Manager' &&
                    r.isApplicable &&
                    r.personId != null)
                .isNotEmpty;

            final gaps = <String>[];
            if (!sponsorFilled &&
                stakeholderRoles.any((r) =>
                    r.roleName == 'Programme Sponsor' && r.isApplicable)) {
              gaps.add('Programme Sponsor');
            }
            if (!changeMgrFilled &&
                teamRoles.any((r) =>
                    r.roleName == 'Change Manager' && r.isApplicable)) {
              gaps.add('Change Manager');
            }

            if (gaps.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                    label: 'Programme Gaps', icon: Icons.warning_amber_rounded),
                ...gaps.map((g) => _PulseItem(
                      label: 'No $g assigned',
                      barColor: KColors.amber,
                      trailing: const Icon(Icons.warning_amber_rounded,
                          size: 12, color: KColors.amber),
                      onTap: onTap,
                    )),
              ],
            );
          },
        );
      },
    );
  }
}
