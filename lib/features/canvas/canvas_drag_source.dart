import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';
import 'canvas_drag_payload.dart';

/// Wraps any widget with a long-press-draggable affordance whose payload
/// is an [ExternalItemDragData] — i.e. the source module exposes its rows
/// as drag sources for Canvas.
///
/// Use this on RAID/Action/Decision/Plan/Journal list rows so the PM can
/// drag them into Canvas to start thinking. The wrapped widget keeps its
/// normal tap behaviour.
class CanvasDragSource extends StatelessWidget {
  final String itemType;
  final String itemId;
  final String title;
  final String? body;
  final Widget child;
  final Axis axis;

  const CanvasDragSource({
    super.key,
    required this.itemType,
    required this.itemId,
    required this.title,
    this.body,
    required this.child,
    this.axis = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    final data = ExternalItemDragData(
      itemType: itemType,
      itemId: itemId,
      title: title,
      body: body,
    );
    return LongPressDraggable<CanvasDragPayload>(
      data: data,
      delay: const Duration(milliseconds: 300),
      feedback: Material(
        color: Colors.transparent,
        child: _DragGhost(title: title, itemType: itemType),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: child),
      child: child,
    );
  }
}

class _DragGhost extends StatelessWidget {
  final String title;
  final String itemType;

  const _DragGhost({required this.title, required this.itemType});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.amber, width: 1),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bubble_chart_outlined,
              size: 14, color: KColors.amber),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title.isEmpty ? '($itemType)' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
