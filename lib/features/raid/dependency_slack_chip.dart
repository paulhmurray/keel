import 'package:flutter/material.dart';

import '../../core/raid/dependency_timeline.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;

/// Coloured chip summarising the slack between a dependency's needed-by
/// date and the plan activity it gates. Green = room to spare, amber =
/// under two weeks, red = lands after the activity needs it.
class DependencySlackChip extends StatelessWidget {
  final DependencySlack slack;
  final bool compact;

  const DependencySlackChip({super.key, required this.slack, this.compact = false});

  Color get _color => switch (slack.severity) {
        SlackSeverity.ok => KColors.phosphor,
        SlackSeverity.tight => KColors.amber,
        SlackSeverity.late => KColors.red,
      };

  Color get _dim => switch (slack.severity) {
        SlackSeverity.ok => KColors.phosDim,
        SlackSeverity.tight => KColors.amberDim,
        SlackSeverity.late => KColors.redDim,
      };

  String get _compactText {
    final approx = slack.activityDateIsEstimate ? '≈' : '';
    if (slack.days == 0) return 'on the day';
    if (slack.days > 0) return '$approx${slack.days}d slack';
    return '$approx${-slack.days}d late';
  }

  @override
  Widget build(BuildContext context) {
    final anchorWord =
        slack.anchor == SlackAnchor.activityStart ? 'starts' : 'ends';
    final tooltip = '${slack.label}\n'
        'Needed by ${du.formatDate(du.toIsoDate(slack.neededBy))} · '
        'activity $anchorWord ${du.formatDate(du.toIsoDate(slack.activityDate))}'
        '${slack.activityDateIsEstimate ? ' (month precision)' : ''}';
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
        decoration: BoxDecoration(
          color: _dim,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            slack.severity == SlackSeverity.late
                ? Icons.warning_amber_rounded
                : Icons.schedule,
            size: compact ? 10 : 12,
            color: _color,
          ),
          const SizedBox(width: 4),
          Text(
            compact ? _compactText : slack.label,
            style: TextStyle(
                color: _color,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}
