import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/update_banner.dart';
import '../../shared/widgets/rag_badge.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/utils/date_utils.dart' as du;

class LeftPanel extends StatelessWidget {
  final VoidCallback? onNavigateToRaid;
  final VoidCallback? onNavigateToDecisions;
  final VoidCallback? onNavigateToActions;
  final VoidCallback? onNavigateToJournal;
  final VoidCallback? onNavigateToPlaybook;

  const LeftPanel({
    super.key,
    this.onNavigateToRaid,
    this.onNavigateToDecisions,
    this.onNavigateToActions,
    this.onNavigateToJournal,
    this.onNavigateToPlaybook,
  });

  @override
  Widget build(BuildContext context) {
    final projectProvider = context.watch<ProjectProvider>();
    final db = context.read<AppDatabase>();
    final projectId = projectProvider.currentProjectId;

    return Container(
      width: 220,
      color: KColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                        ),
                        _SectionHeader(
                          label: 'Pending Decisions',
                          icon: Icons.gavel,
                        ),
                        _TopDecisionsSection(
                          projectId: projectId,
                          db: db,
                          onTap: onNavigateToDecisions,
                        ),
                        _SectionHeader(
                          label: 'Overdue Actions',
                          icon: Icons.check_circle,
                        ),
                        _TopActionsSection(
                          projectId: projectId,
                          db: db,
                          onTap: onNavigateToActions,
                        ),
                        _SectionHeader(label: 'Recent Journal', icon: Icons.menu_book_outlined),
                        _RecentJournalSection(projectId: projectId, db: db, onTap: onNavigateToJournal),
                        _SectionHeader(label: 'Playbook Stage', icon: Icons.account_tree_outlined),
                        _PlaybookStageSection(projectId: projectId, db: db, onTap: onNavigateToPlaybook),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
          ),
          const StandardUpdateNotice(),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          Icon(icon, size: 11, color: KColors.textMuted),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 9,
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

  const _TopRisksSection(
      {required this.projectId, required this.db, this.onTap});

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
                    onTap: onTap,
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

  const _TopDecisionsSection(
      {required this.projectId, required this.db, this.onTap});

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
                    onTap: onTap,
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

  const _TopActionsSection(
      {required this.projectId, required this.db, this.onTap});

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
                              fontSize: 10,
                            ),
                          )
                        : null,
                    onTap: onTap,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: KColors.border, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 2,
              height: 36,
              color: barColor,
              margin: const EdgeInsets.only(right: 10),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: 3),
                    trailing!,
                  ],
                ],
              ),
            ),
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
        style: const TextStyle(color: KColors.textMuted, fontSize: 11),
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
          style: TextStyle(color: KColors.textDim, fontSize: 11),
        ),
      ),
    );
  }
}

class _RecentJournalSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;
  const _RecentJournalSection({required this.projectId, required this.db, this.onTap});

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
              onTap: onTap,
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

  const _PlaybookStageSection({
    required this.projectId,
    required this.db,
    this.onTap,
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

                return _PulseItem(
                  label: 'Stage $stageIdx: ${current.name}',
                  barColor: barColor,
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _statusLabel(status),
                        style: TextStyle(color: barColor, fontSize: 9),
                      ),
                      if (totalCount > 0)
                        Text(
                          '$checkedCount of $totalCount checklist done',
                          style: const TextStyle(
                              color: KColors.textMuted, fontSize: 9),
                        ),
                    ],
                  ),
                  onTap: onTap,
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
