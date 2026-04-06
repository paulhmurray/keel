import 'package:flutter/material.dart';
import '../theme/keel_colors.dart';

class StatusChip extends StatelessWidget {
  final String status;

  const StatusChip({super.key, required this.status});

  Color get _bg {
    switch (status.toLowerCase()) {
      case 'open':
        return KColors.blueDim;
      case 'closed':
      case 'resolved':
      case 'done':
      case 'completed':
      case 'mitigated':
        return KColors.phosDim;
      case 'in progress':
      case 'in_progress':
      case 'active':
        return KColors.phosDim;
      case 'pending':
      case 'on hold':
      case 'blocked':
        return KColors.amberDim;
      case 'cancelled':
      case 'rejected':
      case 'deferred':
        return KColors.redDim;
      case 'approved':
      case 'accepted':
      case 'decided':
        return KColors.phosDim;
      default:
        return KColors.surface2;
    }
  }

  Color get _fg {
    switch (status.toLowerCase()) {
      case 'open':
        return KColors.blue;
      case 'closed':
      case 'resolved':
      case 'done':
      case 'completed':
      case 'mitigated':
        return KColors.phosphor;
      case 'in progress':
      case 'in_progress':
      case 'active':
        return KColors.phosphor;
      case 'pending':
      case 'on hold':
      case 'blocked':
        return KColors.amber;
      case 'cancelled':
      case 'rejected':
      case 'deferred':
        return KColors.red;
      case 'approved':
      case 'accepted':
      case 'decided':
        return KColors.phosphor;
      default:
        return KColors.textDim;
    }
  }

  String get _displayText {
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        _displayText.toUpperCase(),
        style: TextStyle(
          color: _fg,
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.05,
        ),
      ),
    );
  }
}
