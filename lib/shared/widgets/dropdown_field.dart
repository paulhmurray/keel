import 'package:flutter/material.dart';

import '../theme/keel_colors.dart';

/// A reusable dropdown form field used across RAID, Decisions, Actions, etc.
class DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  /// Optional display-name overrides keyed by item value.
  final Map<String, String>? labelOverrides;
  /// Clip the selected label to the field's width instead of letting a
  /// long item force the field wider than its column. Only safe where
  /// the parent bounds the width (an Expanded, a SizedBox) — an
  /// unbounded parent would throw — so it's opt-in.
  final bool isExpanded;

  const DropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelOverrides,
    this.isExpanded = false,
  });

  String _labelFor(String s) {
    if (labelOverrides != null && labelOverrides!.containsKey(s)) {
      return labelOverrides![s]!;
    }
    return s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s;
  }

  @override
  Widget build(BuildContext context) {
    // Ensure the current value is always present in the list to avoid the
    // "exactly one item" Flutter assertion when the DB holds a legacy value.
    final effectiveItems = items.contains(value)
        ? items
        : [value, ...items];
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: isExpanded,
      decoration: InputDecoration(labelText: label),
      dropdownColor: KColors.surface2,
      items: effectiveItems
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text(
                  _labelFor(s),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
