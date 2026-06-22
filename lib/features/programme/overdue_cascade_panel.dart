import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;

/// Programme-side derived panel that surfaces every overdue cascaded
/// item from linked projects in one place. Phase C.7 mounts it at
/// the top of the Actions and Decisions views — the [kind] selects
/// which DAO query feeds the list.
///
/// The panel is purely a roll-up: cascaded rows are still rendered
/// inline in the main list below. Showing them again here makes the
/// "what's overdue across my whole portfolio?" question answerable
/// at a glance.
enum OverdueCascadeKind { action, decision }

class OverdueCascadePanel extends StatelessWidget {
  final OverdueCascadeKind kind;

  const OverdueCascadePanel({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    final projectProvider = context.watch<ProjectProvider>();
    final current = projectProvider.currentProject;
    // Programme-only — projects have their own overdue lists in the
    // primary list rows and don't need this aggregation.
    if (current == null || !projectProvider.isProgramme) {
      return const SizedBox.shrink();
    }
    final db = context.read<AppDatabase>();
    final stream = kind == OverdueCascadeKind.action
        ? db.actionsDao
            .watchOverdueCascadedActionsForProgramme(current.id)
        : db.decisionsDao
            .watchOverdueCascadedDecisionsForProgramme(current.id);

    return StreamBuilder<List<dynamic>>(
      stream: stream,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        final title = kind == OverdueCascadeKind.action
            ? 'OVERDUE ACTIONS · LINKED PROJECTS · ${items.length}'
            : 'OVERDUE DECISIONS · LINKED PROJECTS · ${items.length}';
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: KColors.red.withValues(alpha: 0.06),
            border: Border.all(
                color: KColors.red.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_outlined,
                      color: KColors.red, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      color: KColors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final item in items)
                _OverdueRow(item: item, kind: kind),
            ],
          ),
        );
      },
    );
  }
}

class _OverdueRow extends StatelessWidget {
  final dynamic item; // ProjectAction or Decision
  final OverdueCascadeKind kind;

  const _OverdueRow({required this.item, required this.kind});

  @override
  Widget build(BuildContext context) {
    // Both row types share the same shape — null-safe field reads
    // keep the widget agnostic without an extra wrapping type.
    final String ref = (item.ref as String?) ?? '';
    final String description = item.description as String? ?? '';
    final String? dueDate = item.dueDate as String?;
    // Pull source project id directly (cached source name lives on
    // the Persons + Charter tables, not on Actions/Decisions, so we
    // resolve via the project provider's project list when possible).
    final String? sourceProjectId = item.sourceProjectId as String?;
    final String? owner = kind == OverdueCascadeKind.action
        ? (item.owner as String?)
        : (item.decisionMaker as String?);

    final projects = context.watch<ProjectProvider>().projects;
    final sourceName = sourceProjectId == null
        ? null
        : projects
            .cast<Project?>()
            .firstWhere(
              (p) => p?.id == sourceProjectId,
              orElse: () => null,
            )
            ?.name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: KColors.surface,
              border: Border.all(color: KColors.border2, width: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              sourceName != null ? 'PROJ · $sourceName' : 'PROJ',
              style: const TextStyle(
                color: KColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (ref.isNotEmpty) ...[
            Text(
              ref,
              style: const TextStyle(
                color: KColors.amber,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              description,
              style: const TextStyle(color: KColors.text, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (owner != null && owner.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              owner,
              style: const TextStyle(
                  color: KColors.textDim, fontSize: 11),
            ),
          ],
          const SizedBox(width: 12),
          // Due date in red — this is the whole point of the panel.
          Text(
            dueDate == null ? '' : du.formatDate(dueDate),
            style: const TextStyle(
              color: KColors.red,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
