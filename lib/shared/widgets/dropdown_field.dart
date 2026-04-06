import 'package:flutter/material.dart';

import '../theme/keel_colors.dart';

/// A reusable dropdown form field used across RAID, Decisions, Actions, etc.
class DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const DropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      dropdownColor: KColors.surface2,
      items: items
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text(
                  s[0].toUpperCase() + s.substring(1),
                  style: const TextStyle(fontSize: 13),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
