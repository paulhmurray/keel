import 'package:flutter/material.dart';

import '../../core/portfolio/portfolio_rules.dart';
import '../../shared/theme/keel_colors.dart';

/// Shared building blocks for the portfolio overview. RAG is a status
/// palette: every coloured mark carries a letter or label as well, so
/// nothing on the page is read by colour alone.

Color ragColor(String rag) => switch (rag) {
      'red' => KColors.red,
      'amber' => KColors.amber,
      'green' => KColors.phosphor,
      _ => KColors.textMuted,
    };

String ragLetter(String rag) => switch (rag) {
      'red' => 'R',
      'amber' => 'A',
      'green' => 'G',
      _ => '–',
    };

class PortfolioSectionLabel extends StatelessWidget {
  final String text;
  final String? hint;
  const PortfolioSectionLabel(this.text, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            color: KColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 3),
          Text(hint!, style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ],
      ],
    );
  }
}

class PortfolioCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const PortfolioCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

/// Word chip: GREEN / AMBER / RED / NONE.
class RagChip extends StatelessWidget {
  final String rag;
  final String? label;
  const RagChip(this.rag, {super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final color = ragColor(rag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        (label ?? rag.replaceAll('_', ' ')).toUpperCase(),
        style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Heatmap cell: colour + letter, with the rule that fired on hover.
class RagCell extends StatelessWidget {
  final String rag;
  final String reason;
  const RagCell({super.key, required this.rag, required this.reason});

  @override
  Widget build(BuildContext context) {
    final color = ragColor(rag);
    final noData = ragSeverity(rag) == 0;
    return Tooltip(
      message: reason,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        width: 30,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: noData ? Colors.transparent : color.withValues(alpha: 0.22),
          border: Border.all(color: noData ? KColors.border2 : color, width: 0.8),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          ragLetter(rag),
          style: TextStyle(
            color: noData ? KColors.textMuted : color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Single-series sparkline: a 2px line in the de-emphasis ink with the
/// current week as an 8px accent marker. One measure per sparkline; two
/// measures are two sparklines.
class PulseSparkline extends StatelessWidget {
  final List<int> values;
  final int? max; // fixed scale when the measure has a known range
  final bool upIsBad;
  final double width;
  final double height;
  const PulseSparkline({
    super.key,
    required this.values,
    this.max,
    this.upIsBad = true,
    this.width = 84,
    this.height = 22,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Text('–', style: TextStyle(color: KColors.textMuted, fontSize: 11)),
        ),
      );
    }
    final last = values.last;
    final prev = values[values.length - 2];
    final worsened = upIsBad ? last > prev : last < prev;
    final improved = upIsBad ? last < prev : last > prev;
    final accent = worsened
        ? KColors.red
        : improved
            ? KColors.phosphor
            : KColors.amber;
    return Tooltip(
      message: '${values.length} weeks · ${values.join(' → ')}',
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _SparkPainter(
            values: values,
            max: max,
            line: KColors.textDim,
            accent: accent,
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<int> values;
  final int? max;
  final Color line;
  final Color accent;
  _SparkPainter({required this.values, required this.max, required this.line, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 4.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final hi = max ?? values.reduce((a, b) => a > b ? a : b);
    final lo = 0;
    final span = (hi - lo) == 0 ? 1 : (hi - lo);
    Offset pt(int i) => Offset(
          pad + w * i / (values.length - 1),
          pad + h * (1 - (values[i] - lo) / span),
        );
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final end = pt(values.length - 1);
    canvas.drawCircle(end, 4, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.max != max || old.accent != accent;
}

/// A hero-number tile. The number wears text ink unless it IS a status.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool alert;
  const StatTile(this.label, this.value, {super.key, this.alert = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: alert ? KColors.red : KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (alert) ...[
                Icon(Icons.warning_amber_rounded, size: 14, color: KColors.red),
                const SizedBox(width: 4),
              ],
              Text(value,
                  style: TextStyle(
                      color: alert ? KColors.red : KColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: KColors.textDim, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Column header text for the tables on this page.
TextStyle portfolioHeadStyle() => TextStyle(
      color: KColors.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );

TextStyle portfolioBodyStyle({Color? color}) =>
    TextStyle(color: color ?? KColors.text, fontSize: 12);

TextStyle portfolioDimStyle() => TextStyle(color: KColors.textDim, fontSize: 11);
