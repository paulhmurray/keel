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
    // Ensure the current value is always present in the list to avoid the
    // "exactly one item" Flutter assertion when the DB holds a legacy value.
    final effectiveItems = items.contains(value)
        ? items
        : [value, ...items];
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      dropdownColor: KColors.surface2,
      items: effectiveItems
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text(
                  s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s,
                  style: const TextStyle(fontSize: 13),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
