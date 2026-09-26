import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cascade/cascade_service.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/raid/dependency_plan_link.dart';
import '../../core/raid/dependency_timeline.dart';
import '../../core/raid/raid_conversion_service.dart' show RaidKind;
import '../../core/raid/raid_lifecycle.dart';
import '../../core/raid/risk_rating.dart';
import '../../shared/widgets/closed_toggle.dart';
import '../../core/programme/source_filter.dart';
import '../../shared/widgets/source_filter_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../../shared/widgets/compass_empty_state.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/source_badge.dart';
import '../canvas/canvas_drag_source.dart';
import '../canvas/in_canvas_indicator.dart';
import 'risk_form.dart';
import '../../shared/widgets/min_width_hscroll.dart';
import 'assumption_form.dart';
import 'issue_form.dart';
import 'dependency_form.dart';
import 'dependency_slack_chip.dart';

// ── Escalation helpers (Phase C.2) ─────────────────────────────────────────
//
// The four RAID row widgets share the same escalate / unescalate
// affordance: an extra item in their popup menu + a small "↑ ESC"
// badge when escalatedAt is non-null. Centralising the logic here so
// the four rows don't each grow their own cascade plumbing.

/// Builds a [CascadeService] for the active providers. The gateway is
/// always present (local same-machine transport at minimum, plus the
/// remote HTTP transport when signed in) so escalation works whether or
/// not the user is online. [db] is unused now that the factory reads it
/// from context, kept in the signature so the call sites don't churn.
CascadeService _cascadeFor(BuildContext context, AppDatabase db) =>
    buildCascadeService(context);

/// Cascaded rows are read-only on the programme side — sourceProjectId
/// non-null means this row arrived from a linked project.
bool _isCascaded(String? sourceProjectId) => sourceProjectId != null;

/// Small badge rendered next to the source badge when a row is
/// escalated. Distinct visual so escalated rows pop without crowding.
/// "▲ STEERCO" — flagged to the Steering Committee in the register.
class _SteercoBadge extends StatelessWidget {
  const _SteercoBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: KColors.redDim,
          border: Border.all(color: KColors.red, width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: const Tooltip(
          message: 'Flagged to the Steering Committee',
          child: Text('▲ STEERCO',
              style: TextStyle(
                  color: KColors.red,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4)),
        ),
      );
}

class _EscalatedBadge extends StatelessWidget {
  const _EscalatedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: KColors.amberDim,
        border: Border.all(color: KColors.amber, width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Tooltip(
        message: 'Escalated — visible to linked programmes',
        child: const Text(
          '↑ ESC',
          style: TextStyle(
            color: KColors.amber,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// "Cascaded from project" badge for the programme side. Resolves the
/// source project's name via the live project list (accurate for
/// same-machine links); falls back to a bare "PROJ" when the source
/// project isn't on this machine.
class _CascadedBadge extends StatelessWidget {
  final String? sourceProjectId;
  const _CascadedBadge({this.sourceProjectId});

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<ProjectProvider>().projects;
    final name = sourceProjectId == null
        ? null
        : projects
            .cast<Project?>()
            .firstWhere((p) => p?.id == sourceProjectId, orElse: () => null)
            ?.name;
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: KColors.border2, width: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Tooltip(
        message: name == null
            ? 'Cascaded from a linked project — read-only'
            : 'Cascaded from project: $name — read-only',
        child: Text(
          name == null ? 'PROJ' : 'PROJ · $name',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(
            color: KColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column width constants
// ---------------------------------------------------------------------------

// Below this width the RAID tables scroll horizontally rather than
// crushing their fixed columns (split view / narrow windows).
const _kTableMinW = 950.0;
// Issues carry more columns (impact, escalation, last-updated).
const _kIssuesTableMinW = 1200.0;
const _kRefW = 80.0;
const _kImpactW = 190.0;
const _kEscW = 36.0;
const _kUpdatedW = 64.0;
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
  fontSize: 10,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.12,
);

// ---------------------------------------------------------------------------
// Matrix Dot
// ---------------------------------------------------------------------------

/// One rating cell: the 1–5 rank, coloured by its band, with the scale
/// word in the tooltip.
class _MatrixDot extends StatelessWidget {
  final int rank;
  final String label;

  const _MatrixDot({required this.rank, required this.label});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (levelBand(rank)) {
      'high' => (KColors.redDim, KColors.red),
      'medium' => (KColors.amberDim, KColors.amber),
      _ => (KColors.phosDim, KColors.phosphor),
    };
    return Tooltip(
      message: label,
      child: Container(
        width: 28,
        height: 28,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        alignment: Alignment.center,
        child: Text('$rank',
            style: TextStyle(
                color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
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

  // "Show closed" is one setting for the whole log (all four tabs), kept
  // per project. Closed items age out of the default view two weeks
  // after closing; this brings them back.
  bool _showClosed = false;
  String? _prefsProjectId;
  // Programme-side source filter (which linked project, escalated only).
  // Session-scoped: it's a lens, not a setting.
  SourceFilter _filter = SourceFilter.all;

  Future<void> _loadPrefs(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool('keel_raid_show_closed_$projectId') ?? false;
    if (mounted) setState(() => _showClosed = v);
  }

  Future<void> _toggleShowClosed() async {
    setState(() => _showClosed = !_showClosed);
    final pid = _prefsProjectId;
    if (pid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keel_raid_show_closed_$pid', _showClosed);
  }

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
    if (_prefsProjectId != projectId) {
      _prefsProjectId = projectId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs(projectId));
    }

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
              const Spacer(),
              _RaidClosedToggle(
                db: db,
                projectId: projectId,
                showClosed: _showClosed,
                onTap: _toggleShowClosed,
              ),
            ],
          ),
        ),

        // Programme-only: which linked project / escalated only.
        SourceFilterBar(
          filter: _filter,
          onChanged: (f) => setState(() => _filter = f),
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
                  showClosed: _showClosed, onShowClosed: _toggleShowClosed,
                  filter: _filter,
                  triggerNew: widget.initialTab == 0 && widget.triggerNew),
              _AssumptionsTab(projectId: projectId, db: db,
                  showClosed: _showClosed, onShowClosed: _toggleShowClosed,
                  filter: _filter,
                  triggerNew: widget.initialTab == 1 && widget.triggerNew),
              _IssuesTab(projectId: projectId, db: db,
                  showClosed: _showClosed, onShowClosed: _toggleShowClosed,
                  filter: _filter,
                  triggerNew: widget.initialTab == 2 && widget.triggerNew),
              _DependenciesTab(projectId: projectId, db: db,
                  showClosed: _showClosed, onShowClosed: _toggleShowClosed,
                  filter: _filter,
                  triggerNew: widget.initialTab == 3 && widget.triggerNew),
            ],
          ),
        ),
      ],
    );
  }
}

/// Header pill: watches all four registers so its hidden-count badge
/// reflects the whole log, not just the visible tab.
class _RaidClosedToggle extends StatelessWidget {
  final AppDatabase db;
  final String projectId;
  final bool showClosed;
  final VoidCallback onTap;

  const _RaidClosedToggle({
    required this.db,
    required this.projectId,
    required this.showClosed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dao = db.raidDao;
    return StreamBuilder<List<Risk>>(
      stream: dao.watchRisksForProject(projectId),
      builder: (_, rs) => StreamBuilder<List<Assumption>>(
        stream: dao.watchAssumptionsForProject(projectId),
        builder: (_, as) => StreamBuilder<List<Issue>>(
          stream: dao.watchIssuesForProject(projectId),
          builder: (_, iss) => StreamBuilder<List<ProgramDependency>>(
            stream: dao.watchDependenciesForProject(projectId),
            builder: (_, ds) {
              final hidden = partitionAgedOut<Risk>(rs.data ?? const [],
                          kind: RaidKind.risk,
                          status: (r) => r.status,
                          closedAt: (r) => r.closedAt,
                          updatedAt: (r) => r.updatedAt,
                          showClosed: false)
                      .hidden
                      .length +
                  partitionAgedOut<Assumption>(as.data ?? const [],
                          kind: RaidKind.assumption,
                          status: (a) => a.status,
                          closedAt: (a) => a.closedAt,
                          updatedAt: (a) => a.updatedAt,
                          showClosed: false)
                      .hidden
                      .length +
                  partitionAgedOut<Issue>(iss.data ?? const [],
                          kind: RaidKind.issue,
                          status: (i) => i.status,
                          closedAt: (i) => i.closedAt,
                          updatedAt: (i) => i.updatedAt,
                          showClosed: false)
                      .hidden
                      .length +
                  partitionAgedOut<ProgramDependency>(ds.data ?? const [],
                          kind: RaidKind.dependency,
                          status: (d) => d.status,
                          closedAt: (d) => d.closedAt,
                          updatedAt: (d) => d.updatedAt,
                          showClosed: false)
                      .hidden
                      .length;
              return ClosedToggle(
                  showClosed: showClosed, hiddenCount: hidden, onTap: onTap);
            },
          ),
        ),
      ),
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
                        fontSize: 10, color: KColors.amber, fontWeight: FontWeight.bold),
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
  final bool showClosed;
  final VoidCallback onShowClosed;
  final SourceFilter filter;

  const _RisksTab({
    required this.projectId,
    required this.db,
    required this.showClosed,
    required this.onShowClosed,
    this.filter = SourceFilter.all,
    this.triggerNew = false,
  });

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

  Color _riskBarColor(Risk risk) =>
      switch (riskBand(risk.likelihood, risk.impact)) {
        'high' => KColors.red,
        'medium' => KColors.amber,
        _ => KColors.phosphor,
      };

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
          child: MinWidthHScroll(
            minWidth: _kTableMinW,
            child: Column(
            children: [
              _buildHeaderRow([
                (width: _kRefW, label: 'REF'),
                (width: null, label: 'RISK'),
                (width: _kLikeW, label: 'LIKE'),
                (width: _kImpW, label: 'CONS'),
                (width: _kMitigationW, label: 'TREATMENT'),
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
                        final part = partitionAgedOut<Risk>(
                          snap.data!,
                          kind: RaidKind.risk,
                          status: (x) => x.status,
                          closedAt: (x) => x.closedAt,
                          updatedAt: (x) => x.updatedAt,
                          showClosed: widget.showClosed,
                        );
                        final items = widget.filter.apply(part.visible,
                            sourceProjectId: (x) => x.sourceProjectId,
                            escalatedAt: (x) => x.escalatedAt);
                        if (items.isEmpty && part.hidden.isNotEmpty) {
                          return HiddenClosedNotice(
                              hiddenCount: part.hidden.length,
                              onShow: widget.onShowClosed);
                        }
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
    return CanvasDragSource(
      itemType: 'risk',
      itemId: risk.id,
      title: risk.description,
      body: risk.mitigation,
      child: InkWell(
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
                  if (risk.title != null && risk.title!.isNotEmpty) ...[
                    Text(risk.title!,
                        style: _kTitleStyle.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(risk.description, style: _kMetaStyle, maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ] else
                    Text(risk.description, style: _kTitleStyle, maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  if (risk.steerco ||
                      reviewOverdue(risk.nextReviewAt, DateTime.now())) ...[
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 2, children: [
                      if (risk.steerco) const _SteercoBadge(),
                      if (reviewOverdue(risk.nextReviewAt, DateTime.now()))
                        Text('Review overdue · ${du.formatDate(risk.nextReviewAt)}',
                            style: const TextStyle(
                                color: KColors.amber, fontSize: 10)),
                    ]),
                  ],
                ],
              ),
            ),
            // Likelihood
            SizedBox(
                width: _kLikeW,
                child: _MatrixDot(
                    rank: likelihoodRank(risk.likelihood),
                    label: likelihoodLabel(risk.likelihood))),
            // Consequence
            SizedBox(
                width: _kImpW,
                child: _MatrixDot(
                    rank: consequenceRank(risk.impact),
                    label: consequenceLabel(risk.impact))),
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
            SizedBox(
              width: _kSourceW,
              child: Wrap(
                runSpacing: 2,
                children: [
                  SourceBadge(source: risk.source),
                  if (risk.escalatedAt != null)
                    const _EscalatedBadge(),
                  if (_isCascaded(risk.sourceProjectId))
                    _CascadedBadge(sourceProjectId: risk.sourceProjectId),
                ],
              ),
            ),
            // Canvas indicator
            InCanvasIndicator(itemType: 'risk', itemId: risk.id),
            // Actions
            SizedBox(
              width: _kMenuW,
              child: _isCascaded(risk.sourceProjectId)
                  ? const SizedBox.shrink()
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 16, color: KColors.textMuted),
                      onSelected: (val) async {
                        if (val == 'edit') {
                          await showDialog(
                            context: context,
                            builder: (_) => RiskFormDialog(
                                projectId: projectId, db: db, risk: risk),
                          );
                          if (context.mounted) {
                            final fresh =
                                await db.raidDao.getRiskById(risk.id);
                            if (fresh != null && context.mounted) {
                              await _cascadeFor(context, db).pushRisk(fresh);
                            }
                          }
                        } else if (val == 'delete') {
                          if (context.mounted) {
                            await _cascadeFor(context, db).tombstoneRaidItem(
                              projectId: projectId,
                              itemKind: CascadeKinds.risk,
                              itemId: risk.id,
                            );
                          }
                          await db.raidDao.deleteRisk(risk.id);
                        } else if (val == 'escalate') {
                          await db.raidDao
                              .setRiskEscalated(risk.id, true);
                          final fresh =
                              await db.raidDao.getRiskById(risk.id);
                          if (fresh != null && context.mounted) {
                            await _cascadeFor(context, db).pushRisk(fresh);
                          }
                        } else if (val == 'unescalate') {
                          await db.raidDao.setRiskEscalated(risk.id, false);
                          // Re-push with the flag off: full-detail links keep
                          // the row unflagged, escalated-only links get a tombstone.
                          final fresh = await db.raidDao.getRiskById(risk.id);
                          if (fresh != null && context.mounted) {
                            await _cascadeFor(context, db).pushRisk(fresh);
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('Edit')),
                        if (risk.escalatedAt == null)
                          const PopupMenuItem(
                              value: 'escalate',
                              child: Text('Escalate to programme'))
                        else
                          const PopupMenuItem(
                              value: 'unescalate',
                              child: Text('Stop escalating')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                      ],
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
// Assumptions Tab
// ---------------------------------------------------------------------------

class _AssumptionsTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final bool triggerNew;
  final bool showClosed;
  final VoidCallback onShowClosed;
  final SourceFilter filter;

  const _AssumptionsTab({
    required this.projectId,
    required this.db,
    required this.showClosed,
    required this.onShowClosed,
    this.filter = SourceFilter.all,
    this.triggerNew = false,
  });

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
          child: MinWidthHScroll(
            minWidth: _kTableMinW,
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
                        final part = partitionAgedOut<Assumption>(
                          snap.data!,
                          kind: RaidKind.assumption,
                          status: (x) => x.status,
                          closedAt: (x) => x.closedAt,
                          updatedAt: (x) => x.updatedAt,
                          showClosed: widget.showClosed,
                        );
                        final items = widget.filter.apply(part.visible,
                            sourceProjectId: (x) => x.sourceProjectId,
                            escalatedAt: (x) => x.escalatedAt);
                        if (items.isEmpty && part.hidden.isNotEmpty) {
                          return HiddenClosedNotice(
                              hiddenCount: part.hidden.length,
                              onShow: widget.onShowClosed);
                        }
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
    return CanvasDragSource(
      itemType: 'assumption',
      itemId: assumption.id,
      title: assumption.description,
      child: InkWell(
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
            SizedBox(
              width: _kSourceW,
              child: Wrap(
                runSpacing: 2,
                children: [
                  SourceBadge(source: assumption.source),
                  if (assumption.escalatedAt != null)
                    const _EscalatedBadge(),
                  if (_isCascaded(assumption.sourceProjectId))
                    _CascadedBadge(sourceProjectId: assumption.sourceProjectId),
                ],
              ),
            ),
            InCanvasIndicator(itemType: 'assumption', itemId: assumption.id),
            SizedBox(
              width: _kMenuW,
              child: _isCascaded(assumption.sourceProjectId)
                  ? const SizedBox.shrink()
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 16, color: KColors.textMuted),
                      onSelected: (val) async {
                        if (val == 'edit') {
                          await showDialog(
                            context: context,
                            builder: (_) => AssumptionFormDialog(
                                projectId: projectId,
                                db: db,
                                assumption: assumption),
                          );
                          if (context.mounted) {
                            final fresh = await db.raidDao
                                .getAssumptionById(assumption.id);
                            if (fresh != null && context.mounted) {
                              await _cascadeFor(context, db)
                                  .pushAssumption(fresh);
                            }
                          }
                        } else if (val == 'delete') {
                          if (context.mounted) {
                            await _cascadeFor(context, db).tombstoneRaidItem(
                              projectId: projectId,
                              itemKind: CascadeKinds.assumption,
                              itemId: assumption.id,
                            );
                          }
                          await db.raidDao.deleteAssumption(assumption.id);
                        } else if (val == 'escalate') {
                          await db.raidDao
                              .setAssumptionEscalated(assumption.id, true);
                          final fresh = await db.raidDao
                              .getAssumptionById(assumption.id);
                          if (fresh != null && context.mounted) {
                            await _cascadeFor(context, db)
                                .pushAssumption(fresh);
                          }
                        } else if (val == 'unescalate') {
                          await db.raidDao.setAssumptionEscalated(assumption.id, false);
                          // Re-push with the flag off: full-detail links keep
                          // the row unflagged, escalated-only links get a tombstone.
                          final fresh = await db.raidDao.getAssumptionById(assumption.id);
                          if (fresh != null && context.mounted) {
                            await _cascadeFor(context, db).pushAssumption(fresh);
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('Edit')),
                        if (assumption.escalatedAt == null)
                          const PopupMenuItem(
                              value: 'escalate',
                              child: Text('Escalate to programme'))
                        else
                          const PopupMenuItem(
                              value: 'unescalate',
                              child: Text('Stop escalating')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                      ],
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
// Issues Tab
// ---------------------------------------------------------------------------

class _IssuesTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final bool triggerNew;
  final bool showClosed;
  final VoidCallback onShowClosed;
  final SourceFilter filter;

  const _IssuesTab({
    required this.projectId,
    required this.db,
    required this.showClosed,
    required this.onShowClosed,
    this.filter = SourceFilter.all,
    this.triggerNew = false,
  });

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
          child: MinWidthHScroll(
            minWidth: _kIssuesTableMinW,
            child: Column(
            children: [
              _buildHeaderRow([
                (width: _kRefW, label: 'REF'),
                (width: null, label: 'ISSUE'),
                (width: _kImpactW, label: 'IMPACT IF UNRESOLVED'),
                (width: _kEscW, label: 'ESC'),
                (width: _kOwnerW, label: 'OWNER'),
                (width: _kDueW, label: 'DUE'),
                (width: _kPriorityW, label: 'PRIORITY'),
                (width: _kStatusW, label: 'STATUS'),
                (width: _kUpdatedW, label: 'UPDATED'),
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
                        final part = partitionAgedOut<Issue>(
                          snap.data!,
                          kind: RaidKind.issue,
                          status: (x) => x.status,
                          closedAt: (x) => x.closedAt,
                          updatedAt: (x) => x.updatedAt,
                          showClosed: widget.showClosed,
                        );
                        final items = widget.filter.apply(part.visible,
                            sourceProjectId: (x) => x.sourceProjectId,
                            escalatedAt: (x) => x.escalatedAt);
                        if (items.isEmpty && part.hidden.isNotEmpty) {
                          return HiddenClosedNotice(
                              hiddenCount: part.hidden.length,
                              onShow: widget.onShowClosed);
                        }
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
        ),
      ],
    );
  }
}

/// Relative "last touched" stamp. Open issues untouched for three weeks
/// or more render red — either resolved-but-not-closed or neglected.
class _UpdatedAgo extends StatelessWidget {
  final DateTime updatedAt;
  final bool isOpen;

  const _UpdatedAgo({required this.updatedAt, required this.isOpen});

  static String relativeAge(DateTime dt, DateTime now) {
    final d = now.difference(dt);
    if (d.inDays >= 365) return '${(d.inDays / 365).floor()}y';
    if (d.inDays >= 30) return '${(d.inDays / 30).floor()}mo';
    if (d.inDays >= 7) return '${(d.inDays / 7).floor()}w';
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    return 'now';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stale = isOpen && now.difference(updatedAt).inDays >= 21;
    return Tooltip(
      message: 'Last updated ${du.formatDate(updatedAt.toIso8601String())}'
          '${stale ? ' — stale: resolved-but-not-closed, or neglected?' : ''}',
      waitDuration: const Duration(milliseconds: 350),
      child: Text(
        relativeAge(updatedAt, now),
        style: TextStyle(
          color: stale ? KColors.red : KColors.textDim,
          fontSize: 11,
          fontWeight: stale ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
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
    return CanvasDragSource(
      itemType: 'issue',
      itemId: issue.id,
      title: issue.description,
      body: issue.resolution,
      child: InkWell(
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
            // Title (bold, scannable) with the full description dimmed
            // beneath — pre-title rows just show the description.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(issue.title ?? issue.description,
                      style: _kTitleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (issue.title != null && issue.title!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(issue.description,
                        style: _kMetaStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            // Impact if unresolved — separate from what the issue is.
            SizedBox(
              width: _kImpactW,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(issue.impactStatement ?? '—',
                    style: issue.impactStatement == null
                        ? _kMetaStyle
                        : _kMitigationStyle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
            // Escalation-required flag.
            SizedBox(
              width: _kEscW,
              child: issue.escalationRequired
                  ? const Tooltip(
                      message: 'Escalation required',
                      child: Icon(Icons.arrow_upward,
                          size: 14, color: KColors.red),
                    )
                  : const SizedBox.shrink(),
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
            // Last touched — stale open issues (3+ weeks) glow red:
            // either resolved-but-not-closed or being neglected.
            SizedBox(
              width: _kUpdatedW,
              child: _UpdatedAgo(
                updatedAt: issue.updatedAt,
                isOpen: issue.status == 'open' ||
                    issue.status == 'in progress',
              ),
            ),
            SizedBox(
              width: _kSourceW,
              child: Wrap(
                runSpacing: 2,
                children: [
                  SourceBadge(source: issue.source),
                  if (issue.escalatedAt != null)
                    const _EscalatedBadge(),
                  if (_isCascaded(issue.sourceProjectId))
                    _CascadedBadge(sourceProjectId: issue.sourceProjectId),
                ],
              ),
            ),
            InCanvasIndicator(itemType: 'issue', itemId: issue.id),
            SizedBox(
              width: _kMenuW,
              child: _isCascaded(issue.sourceProjectId)
                  ? const SizedBox.shrink()
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 16, color: KColors.textMuted),
                      onSelected: (val) async {
                        if (val == 'edit') {
                          await showDialog(
                            context: context,
                            builder: (_) => IssueFormDialog(
                                projectId: projectId,
                                db: db,
                                issue: issue),
                          );
                          if (context.mounted) {
                            final fresh =
                                await db.raidDao.getIssueById(issue.id);
                            if (fresh != null && context.mounted) {
                              await _cascadeFor(context, db)
                                  .pushIssue(fresh);
                            }
                          }
                        } else if (val == 'delete') {
                          if (context.mounted) {
                            await _cascadeFor(context, db).tombstoneRaidItem(
                              projectId: projectId,
                              itemKind: CascadeKinds.issue,
                              itemId: issue.id,
                            );
                          }
                          await db.raidDao.deleteIssue(issue.id);
                        } else if (val == 'escalate') {
                          await db.raidDao
                              .setIssueEscalated(issue.id, true);
                          final fresh =
                              await db.raidDao.getIssueById(issue.id);
                          if (fresh != null && context.mounted) {
                            await _cascadeFor(context, db).pushIssue(fresh);
                          }
                        } else if (val == 'unescalate') {
                          await db.raidDao.setIssueEscalated(issue.id, false);
                          // Re-push with the flag off: full-detail links keep
                          // the row unflagged, escalated-only links get a tombstone.
                          final fresh = await db.raidDao.getIssueById(issue.id);
                          if (fresh != null && context.mounted) {
                            await _cascadeFor(context, db).pushIssue(fresh);
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('Edit')),
                        if (issue.escalatedAt == null)
                          const PopupMenuItem(
                              value: 'escalate',
                              child: Text('Escalate to programme'))
                        else
                          const PopupMenuItem(
                              value: 'unescalate',
                              child: Text('Stop escalating')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                      ],
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
// Dependencies Tab
// ---------------------------------------------------------------------------

class _DependenciesTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final bool triggerNew;
  final bool showClosed;
  final VoidCallback onShowClosed;
  final SourceFilter filter;

  const _DependenciesTab({
    required this.projectId,
    required this.db,
    required this.showClosed,
    required this.onShowClosed,
    this.filter = SourceFilter.all,
    this.triggerNew = false,
  });

  @override
  State<_DependenciesTab> createState() => _DependenciesTabState();
}

class _DependenciesTabState extends State<_DependenciesTab> {
  // Plan context for the slack chips — loaded once per tab build; the
  // dependency stream re-renders rows but plan dates change rarely.
  Map<String, TimelineActivity> _activitiesById = const {};
  String? _month0Date;

  @override
  void initState() {
    super.initState();
    _loadPlan();
    if (widget.triggerNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showDialog(
          context: context,
          builder: (_) => DependencyFormDialog(projectId: widget.projectId, db: widget.db),
        );
      });
    }
  }

  Future<void> _loadPlan() async {
    final acts = await widget.db.programmeGanttDao
        .getActivitiesForProject(widget.projectId);
    final header =
        await widget.db.programmeGanttDao.getHeader(widget.projectId);
    if (!mounted) return;
    setState(() {
      _activitiesById = {for (final a in acts) a.id: a};
      _month0Date = header?.month0Date;
    });
  }

  DependencySlack? _slackFor(ProgramDependency d) {
    if (isTerminalStatus(RaidKind.dependency, d.status)) return null;
    final a = d.planActivityId != null ? _activitiesById[d.planActivityId] : null;
    if (a == null) return null;
    return dependencySlack(
      dueDate: d.dueDate,
      dependencyType: d.dependencyType,
      activityStartDate: a.startDate,
      activityEndDate: a.endDate,
      activityStartMonth: a.startMonth,
      activityEndMonth: a.endMonth,
      month0Date: _month0Date,
    );
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
                ).then((_) => _loadPlan()),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Dependency'),
              ),
            ],
          ),
        ),
        Expanded(
          child: MinWidthHScroll(
            minWidth: _kTableMinW,
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
                        final part = partitionAgedOut<ProgramDependency>(
                          snap.data!,
                          kind: RaidKind.dependency,
                          status: (x) => x.status,
                          closedAt: (x) => x.closedAt,
                          updatedAt: (x) => x.updatedAt,
                          showClosed: widget.showClosed,
                        );
                        final items = widget.filter.apply(part.visible,
                            sourceProjectId: (x) => x.sourceProjectId,
                            escalatedAt: (x) => x.escalatedAt);
                        if (items.isEmpty && part.hidden.isNotEmpty) {
                          return HiddenClosedNotice(
                              hiddenCount: part.hidden.length,
                              onShow: widget.onShowClosed);
                        }
                        if (items.isEmpty) {
                          return const CompassEmptyState(
                            message: 'No dependencies charted',
                            subMessage: 'Add a dependency to begin tracking',
                          );
                        }
                        return ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (ctx, i) => _DependencyRow(
                              dep: items[i],
                              db: db,
                              projectId: projectId,
                              slack: _slackFor(items[i]),
                              activityName: items[i].planActivityId != null
                                  ? _activitiesById[items[i].planActivityId]
                                      ?.name
                                  : null),
                        );
                      },
                    ),
                  ),
                ],
              ),
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
  final DependencySlack? slack;
  final String? activityName;

  const _DependencyRow({
    required this.dep,
    required this.db,
    required this.projectId,
    this.slack,
    this.activityName,
  });

  @override
  Widget build(BuildContext context) {
    return CanvasDragSource(
      itemType: 'dependency',
      itemId: dep.id,
      title: dep.description,
      child: InkWell(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dep.description, style: _kTitleStyle, maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                  if ((dep.counterparty != null &&
                          dep.counterparty!.isNotEmpty) ||
                      activityName != null ||
                      slack != null) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (dep.counterparty != null &&
                            dep.counterparty!.isNotEmpty)
                          Text(
                            dep.dependencyType == 'outbound'
                                ? '→ ${dep.counterparty}'
                                : '← ${dep.counterparty}',
                            style: _kMetaStyle,
                          ),
                        if (activityName != null)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.timeline,
                                size: 11, color: KColors.textMuted),
                            const SizedBox(width: 3),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 220),
                              child: Text(activityName!,
                                  style: _kMetaStyle,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        if (slack != null)
                          DependencySlackChip(slack: slack!, compact: true),
                      ],
                    ),
                  ],
                ],
              ),
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
            SizedBox(
              width: _kSourceW,
              child: Wrap(
                runSpacing: 2,
                children: [
                  SourceBadge(source: dep.source),
                  if (dep.escalatedAt != null)
                    const _EscalatedBadge(),
                  if (_isCascaded(dep.sourceProjectId))
                    _CascadedBadge(sourceProjectId: dep.sourceProjectId),
                ],
              ),
            ),
            InCanvasIndicator(itemType: 'dependency', itemId: dep.id),
            SizedBox(
              width: _kMenuW,
              child: _isCascaded(dep.sourceProjectId)
                  ? const SizedBox.shrink()
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 16, color: KColors.textMuted),
                      onSelected: (val) async {
                        if (val == 'edit') {
                          await showDialog(
                            context: context,
                            builder: (_) => DependencyFormDialog(
                                projectId: projectId,
                                db: db,
                                dependency: dep),
                          );
                          if (context.mounted) {
                            final fresh =
                                await db.raidDao.getDependencyById(dep.id);
                            if (fresh != null && context.mounted) {
                              await _cascadeFor(context, db)
                                  .pushDependency(fresh);
                            }
                          }
                        } else if (val == 'delete') {
                          if (context.mounted) {
                            await _cascadeFor(context, db).tombstoneRaidItem(
                              projectId: projectId,
                              itemKind: CascadeKinds.dependency,
                              itemId: dep.id,
                            );
                          }
                          await DependencyPlanLink.remove(
                              db, projectId, dep.id);
                          await db.raidDao.deleteDependency(dep.id);
                        } else if (val == 'escalate') {
                          await db.raidDao
                              .setDependencyEscalated(dep.id, true);
                          final fresh =
                              await db.raidDao.getDependencyById(dep.id);
                          if (fresh != null && context.mounted) {
                            await _cascadeFor(context, db)
                                .pushDependency(fresh);
                          }
                        } else if (val == 'unescalate') {
                          await db.raidDao.setDependencyEscalated(dep.id, false);
                          // Re-push with the flag off: full-detail links keep
                          // the row unflagged, escalated-only links get a tombstone.
                          final fresh = await db.raidDao.getDependencyById(dep.id);
                          if (fresh != null && context.mounted) {
                            await _cascadeFor(context, db).pushDependency(fresh);
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('Edit')),
                        if (dep.escalatedAt == null)
                          const PopupMenuItem(
                              value: 'escalate',
                              child: Text('Escalate to programme'))
                        else
                          const PopupMenuItem(
                              value: 'unescalate',
                              child: Text('Stop escalating')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
