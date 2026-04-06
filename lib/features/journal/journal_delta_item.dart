import 'package:flutter/material.dart';
import '../../core/journal/journal_parser.dart';
import '../../shared/theme/keel_colors.dart';

class JournalDeltaItemWidget extends StatelessWidget {
  final DetectedDelta delta;
  final bool isActive;
  final VoidCallback onConfirm;
  final VoidCallback onIgnore;
  final VoidCallback onEdit;

  const JournalDeltaItemWidget({
    super.key,
    required this.delta,
    required this.isActive,
    required this.onConfirm,
    required this.onIgnore,
    required this.onEdit,
  });

  Color get _typeColor {
    switch (delta.type) {
      case DeltaType.decision: return KColors.blue;
      case DeltaType.action: return KColors.phosphor;
      case DeltaType.risk: return KColors.amber;
      case DeltaType.issue: return KColors.red;
      case DeltaType.dependency: return KColors.blue;
      case DeltaType.timelineChange: return KColors.amber;
    }
  }

  Color get _typeBg {
    switch (delta.type) {
      case DeltaType.decision: return KColors.blueDim;
      case DeltaType.action: return KColors.phosDim;
      case DeltaType.risk: return KColors.amberDim;
      case DeltaType.issue: return KColors.redDim;
      case DeltaType.dependency: return KColors.blueDim;
      case DeltaType.timelineChange: return KColors.amberDim;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConfirmed = delta.confirmed;
    final isIgnored = delta.ignored;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isIgnored
            ? KColors.surface
            : isConfirmed
                ? KColors.phosDim
                : isActive
                    ? KColors.surface2
                    : KColors.surface,
        border: Border.all(
          color: isConfirmed
              ? KColors.phosphor.withValues(alpha: 0.4)
              : isActive
                  ? _typeColor.withValues(alpha: 0.4)
                  : KColors.border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _typeBg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(delta.typeIcon,
                          style: TextStyle(color: _typeColor, fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        delta.typeLabel.toUpperCase(),
                        style: TextStyle(
                          color: _typeColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.08,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (isConfirmed)
                  const Icon(Icons.check_circle, size: 14, color: KColors.phosphor)
                else if (isIgnored)
                  const Icon(Icons.cancel_outlined, size: 14, color: KColors.textMuted),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              delta.title,
              style: TextStyle(
                color: isIgnored ? KColors.textDim : KColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                decoration: isIgnored ? TextDecoration.lineThrough : null,
              ),
            ),
            // Fields display
            if (!isIgnored) ...[
              const SizedBox(height: 6),
              ..._buildFieldRows(),
            ],
            if (!isConfirmed && !isIgnored && isActive) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _ActionBtn(
                    label: 'Y  Confirm',
                    color: KColors.phosphor,
                    onTap: onConfirm,
                  ),
                  const SizedBox(width: 8),
                  _ActionBtn(
                    label: 'E  Edit',
                    color: KColors.amber,
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 8),
                  _ActionBtn(
                    label: 'N  Ignore',
                    color: KColors.textDim,
                    onTap: onIgnore,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFieldRows() {
    final rows = <Widget>[];
    final f = delta.editFields;
    void addRow(String label, String? value) {
      if (value == null || value.isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Text(
              '$label: ',
              style: const TextStyle(color: KColors.textDim, fontSize: 11),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(color: KColors.text, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ));
    }

    switch (delta.type) {
      case DeltaType.action:
        addRow('Owner', f['owner']);
        addRow('Due', f['dueDate']);
        break;
      case DeltaType.decision:
        addRow('Decision-maker', f['decisionMaker']);
        break;
      case DeltaType.risk:
        addRow('Likelihood', f['likelihood']);
        addRow('Impact', f['impact']);
        break;
      case DeltaType.issue:
        addRow('Owner', f['owner']);
        addRow('Priority', f['priority']);
        break;
      case DeltaType.dependency:
        addRow('Owner', f['owner']);
        break;
      case DeltaType.timelineChange:
        addRow('Item', f['item']);
        if (f['previousDate'] != null) addRow('Was', f['previousDate']);
        if (f['newDate'] != null) addRow('Now', f['newDate']);
        break;
    }
    return rows;
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.05,
          ),
        ),
      ),
    );
  }
}
