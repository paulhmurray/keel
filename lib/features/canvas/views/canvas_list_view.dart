import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';
import '../canvas_link_badge.dart';

/// Flat list of all canvas cards, grouped by band. Read-only — tapping a
/// card opens the side editor in canvas_view.
class CanvasListView extends StatelessWidget {
  final List<CanvasCard> cards;
  final void Function(CanvasCard) onTap;

  const CanvasListView({
    super.key,
    required this.cards,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final byBand = <String, List<CanvasCard>>{
      'this_week': [],
      'next_30_days': [],
      'horizon': [],
    };
    for (final c in cards) {
      (byBand[c.band] ??= []).add(c);
    }
    final bands = [
      ('this_week', 'This Week'),
      ('next_30_days', 'Next 30 Days'),
      ('horizon', 'Horizon'),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      children: [
        for (final band in bands)
          if ((byBand[band.$1] ?? const []).isNotEmpty)
            _BandSection(
              title: band.$2,
              cards: byBand[band.$1]!,
              onTap: onTap,
            ),
        if (cards.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No cards yet. Switch to grid view to start adding.',
                style: TextStyle(color: KColors.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}

class _BandSection extends StatelessWidget {
  final String title;
  final List<CanvasCard> cards;
  final void Function(CanvasCard) onTap;

  const _BandSection({
    required this.title,
    required this.cards,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            '${title.toUpperCase()} · ${cards.length}',
            style: const TextStyle(
              color: KColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
        for (final card in cards)
          _Row(card: card, onTap: () => onTap(card)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final CanvasCard card;
  final VoidCallback onTap;

  const _Row({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: KColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            if (card.linkedItemType != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  CanvasLinkBadge.iconForType(card.linkedItemType!),
                  size: 14,
                  color: CanvasLinkBadge.colourForType(
                      card.linkedItemType!),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title.isEmpty ? '(untitled)' : card.title,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (card.body != null && card.body!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        card.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KColors.textDim,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (card.promotedAt != null)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.arrow_forward,
                    size: 14, color: KColors.phosphor),
              ),
          ],
        ),
      ),
    );
  }
}
