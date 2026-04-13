import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/source_badge.dart';
import '../../shared/utils/date_utils.dart' as du;
import 'decision_form.dart';

class DecisionsView extends StatefulWidget {
  final bool triggerNew;

  const DecisionsView({super.key, this.triggerNew = false});

  @override
  State<DecisionsView> createState() => _DecisionsViewState();
}

class _DecisionsViewState extends State<DecisionsView> {
  @override
  void initState() {
    super.initState();
    if (widget.triggerNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final projectId = context.read<ProjectProvider>().currentProjectId;
        if (projectId == null) return;
        final db = context.read<AppDatabase>();
        showDialog(
          context: context,
          builder: (_) => DecisionFormDialog(projectId: projectId, db: db),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project to view decisions.',
          style: TextStyle(color: KColors.textDim)));
    }

    final db = context.read<AppDatabase>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.gavel, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('DECISIONS',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) =>
                      DecisionFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Decision'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // List
          Expanded(
            child: StreamBuilder<List<Decision>>(
              stream: db.decisionsDao.watchDecisionsForProject(projectId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.gavel_outlined,
                            size: 40, color: KColors.textMuted),
                        const SizedBox(height: 12),
                        const Text('No decisions yet.',
                            style: TextStyle(color: KColors.textDim)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => DecisionFormDialog(
                                projectId: projectId, db: db),
                          ),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Decision'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _DecisionCard(
                      decision: items[i], db: db, projectId: projectId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Color _decisionBarColor(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return KColors.blue;
    case 'decided':
    case 'approved':
      return KColors.phosphor;
    default:
      return KColors.textMuted;
  }
}

class _DecisionCard extends StatelessWidget {
  final Decision decision;
  final AppDatabase db;
  final String projectId;

  const _DecisionCard(
      {required this.decision, required this.db, required this.projectId});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => DecisionFormDialog(
              projectId: projectId, db: db, decision: decision,
              startInViewMode: true),
        ),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Colour bar
              Container(
                width: 2,
                height: 48,
                color: _decisionBarColor(decision.status),
                margin: const EdgeInsets.only(right: 12),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (decision.ref != null) ...[
                          Text(
                            decision.ref!,
                            style: const TextStyle(
                                color: KColors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            decision.description,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                                color: KColors.text),
                          ),
                        ),
                        StatusChip(status: decision.status),
                        const SizedBox(width: 6),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert,
                              size: 16, color: KColors.textMuted),
                          onSelected: (val) {
                            if (val == 'edit') {
                              showDialog(
                                context: context,
                                builder: (_) => DecisionFormDialog(
                                    projectId: projectId,
                                    db: db,
                                    decision: decision),
                              );
                            } else if (val == 'delete') {
                              db.decisionsDao.deleteDecision(decision.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (decision.decisionMaker != null &&
                            decision.decisionMaker!.isNotEmpty) ...[
                          const Icon(Icons.person_outline,
                              size: 11, color: KColors.textDim),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(decision.decisionMaker!,
                                style: const TextStyle(
                                    color: KColors.textDim, fontSize: 11),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (decision.dueDate != null &&
                            decision.dueDate!.isNotEmpty) ...[
                          const Icon(Icons.calendar_today_outlined,
                              size: 11, color: KColors.textDim),
                          const SizedBox(width: 3),
                          Text(du.formatDate(decision.dueDate),
                              style: const TextStyle(
                                  color: KColors.textDim, fontSize: 11)),
                          const SizedBox(width: 4),
                        ],
                        SourceBadge(source: decision.source),
                      ],
                    ),
                    if (decision.rationale != null &&
                        decision.rationale!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Rationale: ${decision.rationale}',
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 11)),
                    ],
                    if (decision.outcome != null &&
                        decision.outcome!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('Outcome: ${decision.outcome}',
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 11)),
                    ],
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
