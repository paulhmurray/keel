import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';

/// Visual badge shown at the top of a linked Canvas card. Renders the
/// item type's icon plus the (truncated) reference / id.
class CanvasLinkBadge extends StatelessWidget {
  final String itemType;
  final String? itemId;
  final String? label;

  const CanvasLinkBadge({
    super.key,
    required this.itemType,
    this.itemId,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final icon = iconForType(itemType);
    final colour = colourForType(itemType);
    final display = label ?? _shortRef(itemType, itemId);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colour),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: colour,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }

  static IconData iconForType(String type) {
    switch (type) {
      case 'risk':
        return Icons.shield_outlined;
      case 'assumption':
        return Icons.lightbulb_outline;
      case 'issue':
        return Icons.warning_amber_outlined;
      case 'dependency':
        return Icons.link;
      case 'decision':
        return Icons.gavel_outlined;
      case 'action':
        return Icons.check_circle_outline;
      case 'milestone':
        return Icons.diamond_outlined;
      case 'activity':
        return Icons.timelapse;
      case 'journal':
        return Icons.menu_book_outlined;
      default:
        return Icons.bookmark_outline;
    }
  }

  static Color colourForType(String type) {
    switch (type) {
      case 'risk':
      case 'issue':
        return KColors.amber;
      case 'dependency':
        return KColors.phosphor;
      case 'action':
        return KColors.blue;
      case 'decision':
        return KColors.amber;
      case 'milestone':
        return KColors.text;
      case 'activity':
        return KColors.phosphor;
      case 'journal':
        return KColors.textDim;
      default:
        return KColors.textDim;
    }
  }

  static String labelForType(String type) {
    switch (type) {
      case 'risk':
        return 'Risk';
      case 'assumption':
        return 'Assumption';
      case 'issue':
        return 'Issue';
      case 'dependency':
        return 'Dependency';
      case 'decision':
        return 'Decision';
      case 'action':
        return 'Action';
      case 'milestone':
        return 'Milestone';
      case 'activity':
        return 'Activity';
      case 'journal':
        return 'Journal';
      default:
        return type;
    }
  }

  String _shortRef(String type, String? id) {
    final t = labelForType(type).toUpperCase();
    if (id == null || id.isEmpty) return t;
    final shortId = id.length > 6 ? id.substring(0, 6) : id;
    return '$t · $shortId';
  }
}
