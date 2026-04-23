import 'package:flutter/material.dart';
import '../../../core/programme/coverage_calculator.dart';
import '../../../shared/theme/keel_colors.dart';

class CoverageIndicator extends StatelessWidget {
  final CoverageResult stakeholders;
  final CoverageResult team;

  const CoverageIndicator({
    super.key,
    required this.stakeholders,
    required this.team,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PROGRAMME COVERAGE',
            style: TextStyle(
              color: KColors.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 14),
          _CoverageBar(label: 'Stakeholders', result: stakeholders),
          const SizedBox(height: 10),
          _CoverageBar(label: 'Team', result: team),
        ],
      ),
    );
  }
}

class _CoverageBar extends StatelessWidget {
  final String label;
  final CoverageResult result;

  const _CoverageBar({required this.label, required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.isFull ? KColors.phosphor : KColors.amber;
    final pct = result.percentage;

    String statusText;
    if (result.applicable == 0) {
      statusText = 'No roles configured';
    } else if (result.isEmpty) {
      statusText = 'No roles assigned yet';
    } else if (result.isFull) {
      statusText = 'All roles filled';
    } else {
      statusText = 'Missing: ${result.missingRoles.join(' · ')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: const TextStyle(color: KColors.text, fontSize: 12),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: KColors.surface2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 36,
              child: result.isEmpty
                  ? const SizedBox.shrink()
                  : Text(
                      '${(pct * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          statusText,
          style: TextStyle(
            color: result.isFull ? KColors.phosphor : KColors.textDim,
            fontSize: 10,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
