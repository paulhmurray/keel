import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../core/status/narrative_refs.dart';
import '../../shared/theme/keel_colors.dart';

/// Under the narrative: what each code it mentions actually is, exactly
/// as the export will print it. Quiet when the narrative mentions none.
class ReferencedItemsPanel extends StatelessWidget {
  final AppDatabase db;
  final String projectId;
  final String? narrative;
  const ReferencedItemsPanel({
    super.key,
    required this.db,
    required this.projectId,
    required this.narrative,
  });

  @override
  Widget build(BuildContext context) {
    if (extractRefs(narrative).isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<ReferencedItem>>(
      key: ValueKey(narrative),
      future: resolveNarrativeRefsFromDb(db, projectId, narrative),
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KColors.surface,
              border: Border.all(color: KColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('REFERENCED ITEMS · goes out with the export',
                  style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              for (final r in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 56,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.ref,
                            style: const TextStyle(
                                color: KColors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        Text(r.kind,
                            style: const TextStyle(
                                color: KColors.textMuted, fontSize: 9)),
                      ]),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.headline,
                            style: const TextStyle(color: KColors.text, fontSize: 12)),
                        if (r.detail.isNotEmpty)
                          Text(r.detail,
                              style: const TextStyle(
                                  color: KColors.textDim, fontSize: 10.5)),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        );
      },
    );
  }
}
