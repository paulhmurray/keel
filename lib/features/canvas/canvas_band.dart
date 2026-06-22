import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import 'canvas_card.dart';
import 'canvas_constants.dart';
import 'canvas_drag_payload.dart';
import 'canvas_sequence_painter.dart';

/// One of the three Canvas bands. Cards are positioned freely (pixel x/y)
/// inside the band's content area. The band is itself a drag target so
/// cards can be moved in from other bands, and (in phase B) items can be
/// pulled in from other modules.
class CanvasBand extends StatelessWidget {
  final String band;
  final String title;
  final List<CanvasCard> cards;
  final List<CanvasSequence> sequences;
  final bool isFocusBand;

  /// Called when an empty point inside the band is tapped — used to create
  /// a new card at that point.
  final void Function(Offset localOffset) onTapEmpty;

  /// Called when an existing canvas card is dropped at [localOffset] in
  /// this band. The receiver moves it / repositions it.
  final void Function(CanvasCardDragData drag, Offset localOffset)
      onAcceptCard;

  /// Called when an external item (RAID, Action, etc) is dropped onto the
  /// band. Phase B — receiver creates a linked card.
  final void Function(ExternalItemDragData drag, Offset localOffset)
      onAcceptExternal;

  /// Card-level callbacks plumbed up to canvas_view.
  final void Function(CanvasCard card) onTapCard;
  final void Function(CanvasCard card) onEditCard;
  final void Function(CanvasCard card) onLongPressCard;

  /// Provides feedback for the in-progress drag — the canvas_view tracks
  /// the dragging card so we can dim it via [draggingCardId].
  final String? draggingCardId;
  final void Function(String? cardId) onDraggingCardChanged;

  /// When non-null, tapping a card creates a sequence from this card to
  /// the tapped one (used by the "Add arrow to…" editor flow).
  final String? sequenceSourceCardId;

  const CanvasBand({
    super.key,
    required this.band,
    required this.title,
    required this.cards,
    required this.sequences,
    required this.isFocusBand,
    required this.onTapEmpty,
    required this.onAcceptCard,
    required this.onAcceptExternal,
    required this.onTapCard,
    required this.onEditCard,
    required this.onLongPressCard,
    required this.draggingCardId,
    required this.onDraggingCardChanged,
    this.sequenceSourceCardId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CanvasBandTheme.backgroundFor(band),
        border: const Border(
          bottom: BorderSide(color: KColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BandHeader(
            title: title,
            count: cards.length,
            isFocusBand: isFocusBand,
          ),
          SizedBox(
            height: CanvasLayout.bandHeight,
            child: _BandSurface(
              band: band,
              cards: cards,
              sequences: sequences,
              draggingCardId: draggingCardId,
              sequenceSourceCardId: sequenceSourceCardId,
              onTapEmpty: onTapEmpty,
              onAcceptCard: onAcceptCard,
              onAcceptExternal: onAcceptExternal,
              onTapCard: onTapCard,
              onEditCard: onEditCard,
              onLongPressCard: onLongPressCard,
              onDraggingCardChanged: onDraggingCardChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _BandHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool isFocusBand;

  const _BandHeader({
    required this.title,
    required this.count,
    required this.isFocusBand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: KColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: KColors.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (isFocusBand)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: KColors.amberDim,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: KColors.amber, width: 0.5),
              ),
              child: const Text(
                'now',
                style: TextStyle(
                  color: KColors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BandSurface extends StatelessWidget {
  final String band;
  final List<CanvasCard> cards;
  final List<CanvasSequence> sequences;
  final String? draggingCardId;
  final String? sequenceSourceCardId;
  final void Function(Offset localOffset) onTapEmpty;
  final void Function(CanvasCardDragData drag, Offset localOffset)
      onAcceptCard;
  final void Function(ExternalItemDragData drag, Offset localOffset)
      onAcceptExternal;
  final void Function(CanvasCard card) onTapCard;
  final void Function(CanvasCard card) onEditCard;
  final void Function(CanvasCard card) onLongPressCard;
  final void Function(String? cardId) onDraggingCardChanged;

  const _BandSurface({
    required this.band,
    required this.cards,
    required this.sequences,
    required this.draggingCardId,
    required this.sequenceSourceCardId,
    required this.onTapEmpty,
    required this.onAcceptCard,
    required this.onAcceptExternal,
    required this.onTapCard,
    required this.onEditCard,
    required this.onLongPressCard,
    required this.onDraggingCardChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = cards.isEmpty;
    return DragTarget<CanvasDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.offset);
        final payload = details.data;
        if (payload is CanvasCardDragData) {
          onAcceptCard(payload, local);
        } else if (payload is ExternalItemDragData) {
          onAcceptExternal(payload, local);
        }
      },
      builder: (context, candidate, _) {
        final isHover = candidate.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            border: isHover
                ? Border.all(color: KColors.amber.withValues(alpha: 0.5))
                : null,
          ),
          child: Stack(
            children: [
              // Background tap target — creates a new card where clicked.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) =>
                      onTapEmpty(details.localPosition),
                  child: isEmpty
                      ? Center(
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 360),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                CanvasBandTheme.emptyHint(band),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: KColors.textMuted,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
              // Sequence arrows behind cards.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: CanvasSequencePainter(
                      cards: cards,
                      sequences: sequences
                          .where((s) {
                            // Only draw if both endpoints exist in this band.
                            final from = cards.where(
                                (c) => c.id == s.fromCardId).firstOrNull;
                            final to = cards.where(
                                (c) => c.id == s.toCardId).firstOrNull;
                            return from != null &&
                                to != null &&
                                from.band == band &&
                                to.band == band;
                          })
                          .toList(),
                      draggingCardId: draggingCardId,
                    ),
                  ),
                ),
              ),
              ...cards.map((card) => _PositionedCard(
                    card: card,
                    isDragging: draggingCardId == card.id,
                    isSequenceTarget: sequenceSourceCardId != null &&
                        sequenceSourceCardId != card.id,
                    isSequenceSource: sequenceSourceCardId == card.id,
                    onTap: () => onTapCard(card),
                    onDoubleTap: () => onEditCard(card),
                    onLongPress: () => onLongPressCard(card),
                    onDraggingChanged: onDraggingCardChanged,
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _PositionedCard extends StatelessWidget {
  final CanvasCard card;
  final bool isDragging;
  final bool isSequenceTarget;
  final bool isSequenceSource;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;
  final void Function(String? cardId) onDraggingChanged;

  const _PositionedCard({
    required this.card,
    required this.isDragging,
    required this.isSequenceTarget,
    required this.isSequenceSource,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.onDraggingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: card.positionX.toDouble(),
      top: card.positionY.toDouble(),
      child: Builder(
        builder: (cardCtx) {
          final inner = CanvasCardWidget(
            card: card,
            isDragging: isDragging,
            isSelected: isSequenceSource,
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            onLongPress: onLongPress,
          );
          Widget widget = Draggable<CanvasDragPayload>(
            // Use a tracked pointer offset of zero — the band recomputes
            // position from the drop's global offset minus the band's
            // origin, which (since the drag feedback hangs from the
            // pointer's relative origin) is close enough for v1.
            data: CanvasCardDragData(card, Offset.zero),
            feedback: Material(
              color: Colors.transparent,
              child: CanvasCardWidget(card: card),
            ),
            childWhenDragging: Opacity(
              opacity: 0.15,
              child: CanvasCardWidget(card: card),
            ),
            onDragStarted: () => onDraggingChanged(card.id),
            onDragEnd: (_) => onDraggingChanged(null),
            onDraggableCanceled: (_, __) => onDraggingChanged(null),
            child: inner,
          );
          if (isSequenceTarget) {
            // The amber highlight is purely visual — it must not absorb
            // taps, or the tap-to-pick-target flow on the underlying
            // InkWell never fires.
            widget = Stack(
              children: [
                widget,
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: KColors.amber.withValues(alpha: 0.6),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return widget;
        },
      ),
    );
  }
}
