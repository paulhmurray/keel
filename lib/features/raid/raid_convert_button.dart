import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../core/raid/raid_conversion_service.dart';
import '../../shared/theme/keel_colors.dart';

/// "Convert ▾" menu shown in a RAID form's edit-mode title. Offers the
/// other three RAID kinds plus Decision; confirms, converts (same id,
/// new ref, links follow), then closes the host form dialog.
///
/// Hidden for cascaded items ([sourceProjectId] non-null) — those are
/// read-only on this side.
class RaidConvertButton extends StatelessWidget {
  final AppDatabase db;
  final RaidKind from;
  final String itemId;
  final String? itemRef;
  final String? sourceProjectId;

  const RaidConvertButton({
    super.key,
    required this.db,
    required this.from,
    required this.itemId,
    required this.itemRef,
    required this.sourceProjectId,
  });

  Future<void> _convert(BuildContext context, RaidKind to) async {
    final refLabel = itemRef ?? 'this ${from.label.toLowerCase()}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Convert to ${to.label}'),
        content: Text(
          'Convert $refLabel into a ${to.label.toLowerCase()}? It gets a '
          'new ${to.refPrefix}-ref; ${from.label.toLowerCase()}-specific '
          'fields are preserved in its source note. Unsaved edits in this '
          'form are discarded.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Convert')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      final newRef = await RaidConversionService(db)
          .convert(id: itemId, from: from, to: to);
      messenger?.showSnackBar(SnackBar(
        content: Text('Converted $refLabel to ${to.label} $newRef'),
      ));
    } on StateError catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (sourceProjectId != null) return const SizedBox.shrink();

    final targets =
        RaidKind.values.where((k) => k != from && k != RaidKind.decision);

    return PopupMenuButton<RaidKind>(
      tooltip: 'Convert to another type',
      onSelected: (to) => _convert(context, to),
      itemBuilder: (_) => [
        for (final k in targets)
          PopupMenuItem(
            value: k,
            height: 32,
            child: Text('Convert to ${k.label}',
                style: const TextStyle(fontSize: 12)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: RaidKind.decision,
          height: 32,
          child: Text('Convert to ${RaidKind.decision.label}',
              style: const TextStyle(fontSize: 12)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.border2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 13, color: KColors.textDim),
            SizedBox(width: 4),
            Text('Convert',
                style: TextStyle(color: KColors.textDim, fontSize: 11)),
            Icon(Icons.arrow_drop_down, size: 14, color: KColors.textDim),
          ],
        ),
      ),
    );
  }
}
