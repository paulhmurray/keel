import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' show Value;
import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/source_badge.dart';
import '../../shared/utils/date_utils.dart' as du;
import 'action_form.dart';

class ActionsView extends StatelessWidget {
  const ActionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project to view actions.',
          style: TextStyle(color: KColors.textDim)));
    }

    final db = context.read<AppDatabase>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('ACTIONS',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) =>
                      ActionFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Action'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<ProjectAction>>(
              stream: db.actionsDao.watchActionsForProject(projectId),
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
                        const Icon(Icons.check_circle_outline,
                            size: 40, color: KColors.textMuted),
                        const SizedBox(height: 12),
                        const Text('No actions yet.',
                            style: TextStyle(color: KColors.textDim)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) =>
                                ActionFormDialog(projectId: projectId, db: db),
                          ),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Action'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _ActionCard(
                      action: items[i], db: db, projectId: projectId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Color _actionBarColor(ProjectAction action) {
  if (action.status == 'closed') return KColors.phosphor;
  final isOverdue = action.dueDate != null &&
      action.status != 'closed' &&
      action.dueDate!.compareTo(
              DateTime.now().toIso8601String().substring(0, 10)) <
          0;
  if (isOverdue) return KColors.red;
  return KColors.amber;
}

class _ActionCard extends StatelessWidget {
  final ProjectAction action;
  final AppDatabase db;
  final String projectId;

  const _ActionCard(
      {required this.action, required this.db, required this.projectId});

  bool get _isOverdue {
    if (action.dueDate == null || action.status == 'closed') return false;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return action.dueDate!.compareTo(today) < 0;
  }

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
          builder: (_) => ActionFormDialog(
              projectId: projectId, db: db, action: action,
              startInViewMode: true),
        ),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 2,
                height: 48,
                color: _actionBarColor(action),
                margin: const EdgeInsets.only(right: 12),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (action.ref != null) ...[
                          Text(action.ref!,
                              style: const TextStyle(
                                  color: KColors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(action.description,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                  color: KColors.text)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        StatusChip(status: action.status),
                        const SizedBox(width: 8),
                        if (action.owner != null &&
                            action.owner!.isNotEmpty) ...[
                          const Icon(Icons.person_outline,
                              size: 11, color: KColors.textDim),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(action.owner!,
                                style: const TextStyle(
                                    color: KColors.textDim, fontSize: 11),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (action.dueDate != null) ...[
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 11,
                            color: _isOverdue ? KColors.red : KColors.textDim,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            du.formatDate(action.dueDate),
                            style: TextStyle(
                              color: _isOverdue ? KColors.red : KColors.textDim,
                              fontSize: 11,
                              fontWeight: _isOverdue
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        SourceBadge(source: action.source),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 16, color: KColors.textMuted),
                onSelected: (val) {
                  if (val == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) => ActionFormDialog(
                          projectId: projectId, db: db, action: action),
                    );
                  } else if (val == 'close') {
                    db.actionsDao.upsertAction(
                      ProjectActionsCompanion(
                        id: Value(action.id),
                        projectId: Value(action.projectId),
                        description: Value(action.description),
                        status: const Value('closed'),
                        updatedAt: Value(DateTime.now()),
                      ),
                    );
                  } else if (val == 'delete') {
                    db.actionsDao.deleteAction(action.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'close', child: Text('Mark Closed')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
