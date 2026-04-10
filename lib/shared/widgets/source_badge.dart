import 'package:flutter/material.dart';

import '../theme/keel_colors.dart';

class SourceBadge extends StatelessWidget {
  final String source;

  const SourceBadge({super.key, required this.source});

  Color get _fg {
    switch (source.toLowerCase()) {
      case 'manual':
        return KColors.textDim;
      case 'inbox':
        return KColors.blue;
      case 'document':
        return KColors.amber;
      case 'observation':
        return KColors.phosphor;
      case 'meeting':
        return KColors.blue;
      case 'email':
        return KColors.textDim;
      default:
        return KColors.textDim;
    }
  }

  Color get _bg {
    switch (source.toLowerCase()) {
      case 'manual':
        return KColors.surface2;
      case 'inbox':
        return KColors.blueDim;
      case 'document':
        return KColors.amberDim;
      case 'observation':
        return KColors.phosDim;
      case 'meeting':
        return KColors.blueDim;
      case 'email':
        return KColors.surface2;
      default:
        return KColors.surface2;
    }
  }

  IconData get _icon {
    switch (source.toLowerCase()) {
      case 'manual':
        return Icons.edit_outlined;
      case 'inbox':
        return Icons.inbox_outlined;
      case 'document':
        return Icons.description_outlined;
      case 'observation':
        return Icons.visibility_outlined;
      case 'meeting':
        return Icons.people_outline;
      case 'email':
        return Icons.email_outlined;
      default:
        return Icons.label_outline;
    }
  }

  String get _label {
    final s = source.toLowerCase();
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: _fg.withAlpha(80)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 11, color: _fg),
            const SizedBox(width: 4),
            Text(
              _label,
              style: TextStyle(
                color: _fg,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
