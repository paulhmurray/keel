import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../theme/keel_colors.dart';

/// Dropdown of plan activities grouped under their work package, with
/// a "none" option. Shared by the action form (link an action to the
/// plan) and the dependency form (which activity the dependency gates).
class PlanActivityPicker extends StatelessWidget {
  final String? value;
  final List<TimelineWorkPackage> workPackages;
  final List<TimelineActivity> activities;
  final ValueChanged<String?> onChanged;
  final String label;

  const PlanActivityPicker({
    super.key,
    required this.value,
    required this.workPackages,
    required this.activities,
    required this.onChanged,
    this.label = 'Plan Activity (optional)',
  });

  static const _kTypeIcons = {
    'milestone': '◆ ',
    'hard_deadline': '⚠ ',
    'gate': '◈ ',
  };

  /// "[WP] Activity name" for display outside the picker.
  static String labelFor(
    String activityId, {
    required List<TimelineWorkPackage> workPackages,
    required List<TimelineActivity> activities,
  }) {
    final act = activities
        .cast<TimelineActivity?>()
        .firstWhere((a) => a?.id == activityId, orElse: () => null);
    if (act == null) return activityId;
    final wp = workPackages
        .cast<TimelineWorkPackage?>()
        .firstWhere((w) => w?.id == act.workPackageId, orElse: () => null);
    final prefix = wp != null ? '[${wp.shortCode ?? wp.name}] ' : '';
    return '$prefix${act.name}';
  }

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String?>>[];
    items.add(const DropdownMenuItem<String?>(
        value: null,
        child: Text('— none —', style: TextStyle(color: KColors.textDim))));

    for (final wp in workPackages) {
      final wpActs =
          activities.where((a) => a.workPackageId == wp.id).toList();
      if (wpActs.isEmpty) continue;
      items.add(DropdownMenuItem<String?>(
        enabled: false,
        value: '__header__${wp.id}',
        child: Text(
          wp.shortCode ?? wp.name,
          style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5),
        ),
      ));
      for (final act in wpActs) {
        final prefix = _kTypeIcons[act.activityType] ?? '';
        items.add(DropdownMenuItem<String?>(
          value: act.id,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '$prefix${act.name}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ));
      }
    }

    // A stale id (activity deleted) would crash the dropdown; show none.
    final safeValue =
        activities.any((a) => a.id == value) ? value : null;

    return DropdownButtonFormField<String?>(
      value: safeValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: onChanged,
    );
  }
}
