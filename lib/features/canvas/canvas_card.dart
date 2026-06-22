import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import 'canvas_card_body.dart';
import 'canvas_constants.dart';
import 'canvas_link_badge.dart';
import 'canvas_tags.dart';

/// Visual representation of a single CanvasCard. Stateless render — all
/// state (position, content) comes from the row; mutation goes back through
/// callbacks to the parent band so it can call the DAO.
class CanvasCardWidget extends StatelessWidget {
  final CanvasCard card;
  final bool isSelected;
  final bool isDragging;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  const CanvasCardWidget({
    super.key,
    required this.card,
    this.isSelected = false,
    this.isDragging = false,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dims = CanvasCardDimensions.forSize(card.size);
    final colour = CanvasCardColours.colourFor(card.colour);
    final isPromoted = card.promotedAt != null;
    final isLinked = card.linkedItemType != null && card.linkedItemId != null;

    return Opacity(
      opacity: isDragging ? 0.4 : 1.0,
      child: Container(
        width: dims.width,
        height: dims.height,
        decoration: BoxDecoration(
          color: KColors.surface,
          border: Border.all(
            color: isSelected ? KColors.amber : KColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isLinked || isPromoted)
                  _CardTopBar(
                    linkedItemType: card.linkedItemType,
                    linkedItemId: card.linkedItemId,
                    isPromoted: isPromoted,
                    promotedToType: card.promotedToType,
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.title.isEmpty ? '(untitled)' : card.title,
                          maxLines: card.body == null || card.body!.isEmpty
                              ? 4
                              : 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: KColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        if (card.body != null && card.body!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Expanded(
                            child: CanvasCardBody(body: card.body!),
                          ),
                        ],
                        if (_tagsOf(card).isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _TagChipRow(tags: _tagsOf(card)),
                        ],
                      ],
                    ),
                  ),
                ),
                if (colour != null)
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns the parsed tag list from the persisted JSON column.
List<String> _tagsOf(CanvasCard card) => CanvasTags.decode(card.tags);

/// Horizontal row of small `#tag` chips rendered below the body.
/// Wraps when there are many tags; the surrounding ClipRect on the body
/// area keeps the card height stable.
class _TagChipRow extends StatelessWidget {
  final List<String> tags;

  const _TagChipRow({required this.tags});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Wrap(
        spacing: 4,
        runSpacing: 3,
        children: tags
            .map((t) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: KColors.amberDim.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: KColors.amber.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    '#$t',
                    style: const TextStyle(
                      color: KColors.amber,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _CardTopBar extends StatelessWidget {
  final String? linkedItemType;
  final String? linkedItemId;
  final bool isPromoted;
  final String? promotedToType;

  const _CardTopBar({
    required this.linkedItemType,
    required this.linkedItemId,
    required this.isPromoted,
    required this.promotedToType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: KColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (linkedItemType != null)
            Expanded(
              child: CanvasLinkBadge(
                itemType: linkedItemType!,
                itemId: linkedItemId,
              ),
            )
          else
            const Spacer(),
          if (isPromoted)
            Tooltip(
              message: 'Promoted to '
                  '${promotedToType ?? 'item'}',
              child: const Icon(
                Icons.arrow_forward,
                size: 13,
                color: KColors.phosphor,
              ),
            ),
        ],
      ),
    );
  }
}
