import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';

/// Small badge a source-module row can show to indicate the item is
/// already on Canvas (and in which band). Listens via the DAO so the
/// badge stays in sync when the card moves bands or is removed.
class InCanvasIndicator extends StatelessWidget {
  final String itemType;
  final String itemId;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  const InCanvasIndicator({
    super.key,
    required this.itemType,
    required this.itemId,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) return const SizedBox.shrink();
    final db = context.read<AppDatabase>();
    return StreamBuilder<CanvasCard?>(
      stream: db.canvasCardsDao.watchCardLinkedTo(
        projectId: projectId,
        itemType: itemType,
        itemId: itemId,
      ),
      builder: (context, snap) {
        final card = snap.data;
        if (card == null) return const SizedBox.shrink();
        return Tooltip(
          message: 'On canvas · ${CanvasBands.label(card.band)}',
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: KColors.amberDim,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: KColors.amber.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bubble_chart,
                      size: 11, color: KColors.amber),
                  SizedBox(width: 4),
                  Text(
                    'Canvas',
                    style: TextStyle(
                      color: KColors.amber,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
