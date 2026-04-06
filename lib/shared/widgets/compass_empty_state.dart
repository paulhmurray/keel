import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/keel_colors.dart';

class CompassEmptyState extends StatelessWidget {
  final String message;
  final String? subMessage;

  const CompassEmptyState({
    super.key,
    required this.message,
    this.subMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.22,
            child: SvgPicture.asset(
              'assets/keel-logo.svg',
              width: 180,
              height: 180,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(
              color: KColors.textDim,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              subMessage!,
              style: const TextStyle(
                color: KColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
