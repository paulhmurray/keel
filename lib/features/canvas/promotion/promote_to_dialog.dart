import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';
import '../canvas_link_badge.dart';

/// "Promote to…" dialog. Returns the selected target type
/// (matches [CanvasLinkType.promotable] values) or null if cancelled.
class PromoteToDialog extends StatelessWidget {
  const PromoteToDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final options = CanvasLinkType.promotable;
    return AlertDialog(
      backgroundColor: KColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: KColors.border),
      ),
      title: const Text(
        'Promote to…',
        style: TextStyle(
          color: KColors.amber,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      content: SizedBox(
        width: 320,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: options.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: KColors.border),
          itemBuilder: (_, i) {
            final type = options[i];
            return ListTile(
              dense: true,
              leading: Icon(
                CanvasLinkBadge.iconForType(type),
                color: CanvasLinkBadge.colourForType(type),
                size: 18,
              ),
              title: Text(
                CanvasLinkBadge.labelForType(type),
                style:
                    const TextStyle(color: KColors.text, fontSize: 13),
              ),
              subtitle: Text(
                _hintFor(type),
                style: const TextStyle(
                  color: KColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
              onTap: () => Navigator.of(context).pop(type),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String _hintFor(String type) {
    switch (type) {
      case CanvasLinkType.action:
        return 'New entry in Actions';
      case CanvasLinkType.decision:
        return 'New entry in Decisions';
      case CanvasLinkType.risk:
        return 'New risk in RAID';
      case CanvasLinkType.assumption:
        return 'New assumption in RAID';
      case CanvasLinkType.issue:
        return 'New issue in RAID';
      case CanvasLinkType.dependency:
        return 'New dependency in RAID';
      case CanvasLinkType.milestone:
        return 'New milestone in Plan';
      case CanvasLinkType.activity:
        return 'New activity in Plan';
      default:
        return '';
    }
  }
}
