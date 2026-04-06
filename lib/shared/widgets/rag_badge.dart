import 'package:flutter/material.dart';
import '../theme/keel_colors.dart';

class RAGBadge extends StatelessWidget {
  final String rag;
  final bool showLabel;

  const RAGBadge({
    super.key,
    required this.rag,
    this.showLabel = true,
  });

  Color get _fg {
    switch (rag.toLowerCase()) {
      case 'green':
        return KColors.phosphor;
      case 'amber':
        return KColors.amber;
      case 'red':
        return KColors.red;
      default:
        return KColors.textDim;
    }
  }

  Color get _bg {
    switch (rag.toLowerCase()) {
      case 'green':
        return KColors.phosDim;
      case 'amber':
        return KColors.amberDim;
      case 'red':
        return KColors.redDim;
      default:
        return KColors.surface2;
    }
  }

  String get _label {
    switch (rag.toLowerCase()) {
      case 'green':
        return 'GREEN';
      case 'amber':
        return 'AMBER';
      case 'red':
        return 'RED';
      default:
        return rag.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!showLabel) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: _fg, shape: BoxShape.circle),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        _label,
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
