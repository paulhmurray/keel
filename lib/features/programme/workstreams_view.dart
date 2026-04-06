import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/widgets/rag_badge.dart';
import '../../shared/widgets/status_chip.dart';
import 'workstream_form.dart';

class WorkstreamsView extends StatelessWidget {
  const WorkstreamsView({super.key});

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project.'));
    }

    final db = context.read<AppDatabase>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Workstreams',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) =>
                      WorkstreamFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Workstream'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<Workstream>>(
              stream: db.programmeDao.watchWorkstreamsForProject(projectId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No workstreams yet.',
                        style: TextStyle(color: KColors.textDim)),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final w = items[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: RAGBadge(rag: w.status, showLabel: false),
                        title: Text(w.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: w.lead != null
                            ? Text('Lead: ${w.lead}',
                                style: const TextStyle(
                                    color: KColors.textDim, fontSize: 12))
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusChip(status: w.status),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => WorkstreamFormDialog(
                                    projectId: projectId,
                                    db: db,
                                    workstream: w),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: KColors.red),
                              onPressed: () =>
                                  db.programmeDao.deleteWorkstream(w.id),
                            ),
                          ],
                        ),
                      ),
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
}
