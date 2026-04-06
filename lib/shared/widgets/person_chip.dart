import 'package:flutter/material.dart';

import '../theme/keel_colors.dart';

class PersonChip extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;

  const PersonChip({
    super.key,
    required this.name,
    this.onTap,
  });

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: KColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: KColors.border2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: KColors.amberDim,
              child: Text(
                _initials,
                style: const TextStyle(
                  color: KColors.amber,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
