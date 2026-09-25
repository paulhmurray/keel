import 'package:flutter/material.dart';

import '../theme/keel_colors.dart';

/// "Hiding closed / Showing closed" pill for a register header. Mirrors
/// the Actions view's old-closed toggle so the behaviour reads the same
/// everywhere: closed items age out of the default view after two
/// weeks and this brings them back.
class ClosedToggle extends StatelessWidget {
  final bool showClosed;
  final int hiddenCount;
  final VoidCallback onTap;

  const ClosedToggle({
    super.key,
    required this.showClosed,
    required this.hiddenCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = showClosed ? KColors.amber : KColors.textDim;
    return Tooltip(
      message: showClosed
          ? 'Click to hide items closed more than 2 weeks ago'
          : hiddenCount == 0
              ? 'No aged-out closed items to show'
              : 'Click to show $hiddenCount closed item${hiddenCount == 1 ? '' : 's'} '
                  'hidden because they closed more than 2 weeks ago',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: showClosed
                ? KColors.amber.withValues(alpha: 0.15)
                : KColors.surface2,
            border: Border.all(
              color: showClosed ? KColors.amber : KColors.border2,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                showClosed ? Icons.visibility : Icons.visibility_off_outlined,
                size: 13,
                color: activeColor,
              ),
              const SizedBox(width: 5),
              Text(
                showClosed ? 'Showing closed' : 'Hiding closed',
                style: TextStyle(
                  color: activeColor,
                  fontSize: 11,
                  fontWeight: showClosed ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (!showClosed && hiddenCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: KColors.border2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$hiddenCount',
                      style: const TextStyle(
                          color: KColors.textDim,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty-state body for a register whose every item is closed and
/// hidden — says so instead of pretending the register is empty.
class HiddenClosedNotice extends StatelessWidget {
  final int hiddenCount;
  final VoidCallback onShow;

  const HiddenClosedNotice(
      {super.key, required this.hiddenCount, required this.onShow});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 32, color: KColors.textMuted),
          const SizedBox(height: 10),
          Text(
            '$hiddenCount closed item${hiddenCount == 1 ? '' : 's'} hidden',
            style: const TextStyle(color: KColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Nothing open. Closed items are kept for the audit trail.',
            style: TextStyle(color: KColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onShow,
            icon: const Icon(Icons.visibility, size: 14),
            label: const Text('Show closed', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
