import 'dart:ui' show Offset;

import '../../core/database/database.dart';

/// Anything that can be dragged onto / within the Canvas.
///
/// [CanvasCardDragData] represents an existing card being moved or copied.
/// [ExternalItemDragData] represents an item from another module (RAID,
/// Actions, Decisions, Plan, Journal) being pulled in — phase B feature.
sealed class CanvasDragPayload {
  const CanvasDragPayload();
}

/// A canvas card being moved between (or within) bands.
///
/// [pointerOffsetInCard] is the local offset of the pointer relative to
/// the card's top-left at the moment the drag started — used so the band
/// can preserve the visual anchoring when computing the new position_x/y.
class CanvasCardDragData extends CanvasDragPayload {
  final CanvasCard card;
  final Offset pointerOffsetInCard;

  const CanvasCardDragData(this.card, this.pointerOffsetInCard);
}

/// An item from a non-Canvas module being dragged onto Canvas.
/// On drop, the receiving band creates a linked card.
class ExternalItemDragData extends CanvasDragPayload {
  final String itemType; // matches CanvasLinkType
  final String itemId;
  final String title;
  final String? body;

  const ExternalItemDragData({
    required this.itemType,
    required this.itemId,
    required this.title,
    this.body,
  });
}
