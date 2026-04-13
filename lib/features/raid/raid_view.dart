import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../../shared/widgets/compass_empty_state.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/source_badge.dart';
import 'risk_form.dart';
import 'assumption_form.dart';
import 'issue_form.dart';
import 'dependency_form.dart';

// ---------------------------------------------------------------------------
// Column width constants
// ---------------------------------------------------------------------------

const _kRefW = 80.0;
const _kDescW = 240.0;
const _kLikeW = 56.0;
const _kImpW = 56.0;
const _kMitigationW = 160.0;
const _kOwnerW = 110.0;
const _kStatusW = 90.0;
const _kSourceW = 64.0;
const _kMenuW = 40.0;
const _kTypeW = 90.0;
const _kDueW = 90.0;
const _kPriorityW = 90.0;


// ---------------------------------------------------------------------------
// Shared style helpers
// ---------------------------------------------------------------------------

const _kRefStyle = TextStyle(
  color: KColors.amber,
  fontSize: 11,
  fontWeight: FontWeight.w600,
);

const _kTitleStyle = TextStyle(
  color: KColors.text,
  fontSize: 12,
  fontWeight: FontWeight.w500,
  height: 1.4,
);

const _kMetaStyle = TextStyle(
  color: KColors.textDim,
  fontSize: 10,
  height: 1.4,
);

const _kMitigationStyle = TextStyle(
  color: KColors.textDim,
  fontSize: 11,
  height: 1.4,
);

const _kHeaderCellStyle = TextStyle(
  color: KColors.textMuted,
  fontSize: 9,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.12,
);

// ---------------------------------------------------------------------------
// Matrix Dot
// ---------------------------------------------------------------------------

class _MatrixDot extends StatelessWidget {
  final String level;

  const _MatrixDot({required this.level});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (level.toLowerCase()) {
      'high' => (KColors.redDim, KColors.red, 'H'),
      'medium' => (KColors.amberDim, KColors.amber, 'M'),
      _ => (KColors.phosDim, KColors.phosphor, 'L'),
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.center,
      child: Text(label, style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

// ---------------------------------------------------------------------------
// Owner Chip
// ---------------------------------------------------------------------------

class _OwnerChip extends StatelessWidget {
  final String? name;

  const _OwnerChip({this.name});

  @override
  Widget build(BuildContext context) {
    if (name == null || name!.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: KColors.border2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        name!,
        style: const TextStyle(color: KColors.textDim, fontSize: 10, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared table header row — all fixed widths, no Expanded
// ---------------------------------------------------------------------------

Widget _buildHeaderRow(List<({double? width, String label})> cols) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: const BoxDecoration(
      color: KColors.surface,
      border: Border(bottom: BorderSide(color: KColors.border)),
    ),
    child: Row(
      children: cols.map((c) {
        final text = Text(c.label, style: _kHeaderCellStyle);
        return c.width == null
            ? Expanded(child: text)
            : SizedBox(width: c.width, child: text);
      }).toList(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Row colour bar helper
// ---------------------------------------------------------------------------

Widget _colourBar(Color color) => Container(
      width: 3,
      height: 40,
      color: color,
      margin: const EdgeInsets.only(right: 10),
    );

// ---------------------------------------------------------------------------
// RaidView
// ---------------------------------------------------------------------------

class RaidView extends StatefulWidget {
  final int? initialTab;
  final bool triggerNew;

  const RaidView({super.key, this.initialTab, this.triggerNew = false});

  @override
  State<RaidView> createState() => _RaidViewState();
}

class _RaidViewState extends State<RaidView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab ?? 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;

    if (projectId == null) {
      return const Center(
          child: Text('Select a project to view RAID.',
              style: TextStyle(color: KColors.textDim)));
    }

    final db = context.read<AppDatabase>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            children: [
              const Icon(Icons.shield, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('RAID LOG',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),

        // Tab bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: KColors.border)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              _RaidTab(label: 'Risks', stream: db.raidDao.watchRisksForProject(projectId)),
              _RaidTab(
                  label: 'Assumptions',
                  stream: db.raidDao.watchAssumptionsForProject(projectId)),
              _RaidTab(label: 'Issues', stream: db.raidDao.watchIssuesForProject(projectId)),
              _RaidTab(
                  label: 'Dependencies',
                  stream: db.raidDao.watchDependenciesForProject(projectId)),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RisksTab(projectId: projectId, db: db,
                  triggerNew: widget.initialTab == 0 && widget.triggerNew),
              _AssumptionsTab(projectId: projectId, db: db,
                  triggerNew: widget.initialTab == 1 && widget.triggerNew),
              _IssuesTab(projectId: projectId, db: db,
                  triggerNew: widget.initialTab == 2 && widget.triggerNew),
              _DependenciesTab(projectId: projectId, db: db,
                  triggerNew: widget.initialTab == 3 && widget.triggerNew),
            ],
          ),
        ),
      ],
    );
  }
}

class _RaidTab extends StatelessWidget {
  final String label;
  final Stream<List<dynamic>> stream;

  const _RaidTab({required this.label, required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<dynamic>>(
      stream: stream,
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: KColors.amberDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                        fontSize: 9, color: KColors.amber, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Risks Tab
// ---------------------------------------------------------------------------

class _RisksTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final bool triggerNew;

  const _RisksTab({required this.projectId, required this.db, this.triggerNew = false});

  @override
  State<_RisksTab> createState() => _RisksTabState();
}

class _RisksTabState extends State<_RisksTab> {
  @override
  void initState() {
    super.initState();
    if (widget.triggerNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showDialog(
          context: context,
          builder: (_) => RiskFormDialog(projectId: widget.projectId, db: widget.db),
        );
      });
    }
  }

  Color _riskBarColor(Risk risk) {
    int s(String v) =>
        v.toLowerCase() == 'high' ? 3 : v.toLowerCase() == 'medium' ? 2 : 1;
    final score = s(risk.likelihood) * s(risk.impact);
    if (score >= 9) return KColors.red;
    if (score >= 4) return KColors.amber;
    return KColors.phosphor;
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final db = widget.db;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => RiskFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Risk'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              _buildHeaderRow([
                (width: _kRefW, label: 'REF'),
                (width: null, label: 'RISK'),
                (width: _kLikeW, label: 'LIKE'),
                (width: _kImpW, label: 'IMP'),
                (width: _kMitigationW, label: 'MITIGATION'),
                (width: _kOwnerW, label: 'OWNER'),
                (width: _kStatusW, label: 'STATUS'),
                (width: _kSourceW, label: 'SOURCE'),
                (width: _kMenuW, label: ''),
              ]),
              Expanded(
                child: StreamBuilder<List<Risk>>(
                      stream: db.raidDao.watchRisksForProject(projectId),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final items = snap.data!;
                        if (items.isEmpty) {
                          return const CompassEmptyState(
                            message: 'No threats on the horizon',
                            subMessage: 'Add a risk to begin tracking',
                          );
                        }
                        return ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (ctx, i) => _RiskRow(
                            risk: items[i],
                            db: db,
                            projectId: projectId,
                            barColor: _riskBarColor(items[i]),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

class _RiskRow extends StatelessWidget {
  final Risk risk;
  final AppDatabase db;
  final String projectId;
  final Color barColor;

  const _RiskRow({
    required this.risk,
    required this.db,
    required this.projectId,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => RiskFormDialog(
            projectId: projectId, db: db, risk: risk, startInViewMode: true),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: KColors.border, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ref with colour bar
            SizedBox(
              width: _kRefW,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _colourBar(barColor),
                  Expanded(
                    child: Text(risk.ref ?? '', style: _kRefStyle, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            // Description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(risk.description, style: _kTitleStyle, maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                  if (risk.sourceNote != null && risk.sourceNote!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(risk.sourceNote!, style: _kMetaStyle, maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            // Likelihood
            SizedBox(width: _kLikeW, child: _MatrixDot(level: risk.likelihood)),
            // Impact
            SizedBox(width: _kImpW, child: _MatrixDot(level: risk.impact)),
            // Mitigation
            SizedBox(
              width: _kMitigationW,
              child: Text(risk.mitigation ?? '', style: _kMitigationStyle, maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ),
            // Owner
            SizedBox(width: _kOwnerW, child: _OwnerChip(name: risk.owner)),
            // Status
            SizedBox(width: _kStatusW, child: StatusChip(status: risk.status)),
            // Source
            SizedBox(width: _kSourceW, child: SourceBadge(source: risk.source)),
            // Actions
            SizedBox(
              width: _kMenuW,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 16, color: KColors.textMuted),
                onSelected: (val) {
                  if (val == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          RiskFormDialog(projectId: projectId, db: db, risk: risk),
                    );
                  } else if (val == 'delete') {
                    db.raidDao.deleteRisk(risk.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Assumptions Tab
// ---------------------------------------------------------------------------

class _AssumptionsTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final bool triggerNew;

  const _AssumptionsTab({required this.projectId, required this.db, this.triggerNew = false});

  @override
  State<_AssumptionsTab> createState() => _AssumptionsTabState();
}

class _AssumptionsTabState extends State<_AssumptionsTab> {
  @override
  void initState() {
    super.initState();
    if (widget.triggerNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showDialog(
          context: context,
          builder: (_) => AssumptionFormDialog(projectId: widget.projectId, db: widget.db),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final db = widget.db;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AssumptionFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Assumption'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              _buildHeaderRow([
                (width: _kRefW, label: 'REF'),
                (width: null, label: 'DESCRIPTION'),
                (width: _kOwnerW, label: 'OWNER'),
                (width: _kStatusW, label: 'STATUS'),
                (width: _kSourceW, label: 'SOURCE'),
                (width: _kMenuW, label: ''),
              ]),
              Expanded(
                child: StreamBuilder<List<Assumption>>(
                      stream: db.raidDao.watchAssumptionsForProject(projectId),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final items = snap.data!;
                        if (items.isEmpty) {
                          return const CompassEmptyState(
                            message: 'All assumptions holding steady',
                            subMessage: 'Add an assumption to begin tracking',
                          );
                        }
                        return ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (ctx, i) => _AssumptionRow(
                              assumption: items[i], db: db, projectId: projectId),
                        );
                      },
                    ),
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

class _AssumptionRow extends StatelessWidget {
  final Assumption assumption;
  final AppDatabase db;
  final String projectId;

  const _AssumptionRow(
      {required this.assumption, required this.db, required this.projectId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => AssumptionFormDialog(
            projectId: projectId, db: db, assumption: assumption,
            startInViewMode: true),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: KColors.border, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _kRefW,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _colourBar(KColors.phosphor),
                  Expanded(
                    child: Text(assumption.ref ?? '',
                        style: _kRefStyle, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(assumption.description, style: _kTitleStyle, maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ),
            SizedBox(width: _kOwnerW, child: _OwnerChip(name: assumption.owner)),
            SizedBox(width: _kStatusW, child: StatusChip(status: assumption.status)),
            SizedBox(width: _kSourceW, child: SourceBadge(source: assumption.source)),
            SizedBox(
              width: _kMenuW,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 16, color: KColors.textMuted),
                onSelected: (val) {
                  if (val == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) => AssumptionFormDialog(
                          projectId: projectId, db: db, assumption: assumption),
                    );
                  } else if (val == 'delete') {
                    db.raidDao.deleteAssumption(assumption.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Issues Tab
// ---------------------------------------------------------------------------

class _IssuesTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final bool triggerNew;

  const _IssuesTab({required this.projectId, required this.db, this.triggerNew = false});

  @override
  State<_IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<_IssuesTab> {
  @override
  void initState() {
    super.initState();
    if (widget.triggerNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showDialog(
          context: context,
          builder: (_) => IssueFormDialog(projectId: widget.projectId, db: widget.db),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final db = widget.db;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => IssueFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Issue'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              _buildHeaderRow([
                (width: _kRefW, label: 'REF'),
                (width: null, label: 'DESCRIPTION'),
                (width: _kOwnerW, label: 'OWNER'),
                (width: _kDueW, label: 'DUE'),
                (width: _kPriorityW, label: 'PRIORITY'),
                (width: _kStatusW, label: 'STATUS'),
                (width: _kSourceW, label: 'SOURCE'),
                (width: _kMenuW, label: ''),
              ]),
              Expanded(
                child: StreamBuilder<List<Issue>>(
                      stream: db.raidDao.watchIssuesForProject(projectId),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final items = snap.data!;
                        if (items.isEmpty) {
                          return const CompassEmptyState(
                            message: 'Clear water ahead — no issues logged',
                            subMessage: 'Add an issue to begin tracking',
                          );
                        }
                        return ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (ctx, i) =>
                              _IssueRow(issue: items[i], db: db, projectId: projectId),
                        );
                      },
                    ),
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  final Issue issue;
  final AppDatabase db;
  final String projectId;

  const _IssueRow(
      {required this.issue, required this.db, required this.projectId});

  Color _priorityBarColor() {
    switch (issue.priority.toLowerCase()) {
      case 'critical':
      case 'high':
        return KColors.red;
      case 'medium':
        return KColors.amber;
      default:
        return KColors.phosphor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => IssueFormDialog(
            projectId: projectId, db: db, issue: issue, startInViewMode: true),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: KColors.border, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _kRefW,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _colourBar(_priorityBarColor()),
                  Expanded(
                    child: Text(issue.ref ?? '',
                        style: _kRefStyle, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(issue.description, style: _kTitleStyle, maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ),
            SizedBox(width: _kOwnerW, child: _OwnerChip(name: issue.owner)),
            SizedBox(
              width: _kDueW,
              child: Text(du.formatDate(issue.dueDate), style: _kMetaStyle),
            ),
            SizedBox(
              width: _kPriorityW,
              child: Text(issue.priority, style: _kMetaStyle, overflow: TextOverflow.ellipsis),
            ),
            SizedBox(width: _kStatusW, child: StatusChip(status: issue.status)),
            SizedBox(width: _kSourceW, child: SourceBadge(source: issue.source)),
            SizedBox(
              width: _kMenuW,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 16, color: KColors.textMuted),
                onSelected: (val) {
                  if (val == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) =>
                          IssueFormDialog(projectId: projectId, db: db, issue: issue),
                    );
                  } else if (val == 'delete') {
                    db.raidDao.deleteIssue(issue.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dependencies Tab
// ---------------------------------------------------------------------------

class _DependenciesTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final bool triggerNew;

  const _DependenciesTab({required this.projectId, required this.db, this.triggerNew = false});

  @override
  State<_DependenciesTab> createState() => _DependenciesTabState();
}

class _DependenciesTabState extends State<_DependenciesTab> {
  @override
  void initState() {
    super.initState();
    if (widget.triggerNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showDialog(
          context: context,
          builder: (_) => DependencyFormDialog(projectId: widget.projectId, db: widget.db),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final db = widget.db;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => DependencyFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Dependency'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              _buildHeaderRow([
                (width: _kRefW, label: 'REF'),
                (width: null, label: 'DESCRIPTION'),
                (width: _kTypeW, label: 'TYPE'),
                (width: _kOwnerW, label: 'OWNER'),
                (width: _kDueW, label: 'DUE'),
                (width: _kStatusW, label: 'STATUS'),
                (width: _kSourceW, label: 'SOURCE'),
                (width: _kMenuW, label: ''),
              ]),
              Expanded(
                child: StreamBuilder<List<ProgramDependency>>(
                      stream: db.raidDao.watchDependenciesForProject(projectId),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final items = snap.data!;
                        if (items.isEmpty) {
                          return const CompassEmptyState(
                            message: 'No dependencies charted',
                            subMessage: 'Add a dependency to begin tracking',
                          );
                        }
                        return ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (ctx, i) =>
                              _DependencyRow(dep: items[i], db: db, projectId: projectId),
                        );
                      },
                    ),
                  ),
                ],
              ),
        ),
      ],
    );
  }
}

class _DependencyRow extends StatelessWidget {
  final ProgramDependency dep;
  final AppDatabase db;
  final String projectId;

  const _DependencyRow(
      {required this.dep, required this.db, required this.projectId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => DependencyFormDialog(
            projectId: projectId, db: db, dependency: dep,
            startInViewMode: true),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: KColors.border, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _kRefW,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _colourBar(KColors.blue),
                  Expanded(
                    child: Text(dep.ref ?? '',
                        style: _kRefStyle, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(dep.description, style: _kTitleStyle, maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: _kTypeW,
              child: Text(dep.dependencyType, style: _kMetaStyle, overflow: TextOverflow.ellipsis),
            ),
            SizedBox(width: _kOwnerW, child: _OwnerChip(name: dep.owner)),
            SizedBox(
              width: _kDueW,
              child: Text(du.formatDate(dep.dueDate), style: _kMetaStyle),
            ),
            SizedBox(width: _kStatusW, child: StatusChip(status: dep.status)),
            SizedBox(width: _kSourceW, child: SourceBadge(source: dep.source)),
            SizedBox(
              width: _kMenuW,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 16, color: KColors.textMuted),
                onSelected: (val) {
                  if (val == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) => DependencyFormDialog(
                          projectId: projectId, db: db, dependency: dep),
                    );
                  } else if (val == 'delete') {
                    db.raidDao.deleteDependency(dep.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
