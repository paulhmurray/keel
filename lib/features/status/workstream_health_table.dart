import 'package:flutter/material.dart';

import '../../core/status/status_calculator.dart';
import '../../shared/theme/keel_colors.dart';

class WorkstreamHealthTable extends StatelessWidget {
  final List<WorkstreamRagStatus> workstreams;

  const WorkstreamHealthTable({super.key, required this.workstreams});

  @override
  Widget build(BuildContext context) {
    if (workstreams.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No work packages defined.',
            style: TextStyle(color: KColors.textMuted, fontSize: 12)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: KColors.surface2,
              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              border:
                  Border(bottom: BorderSide(color: KColors.border)),
            ),
            child: const Row(children: [
              Expanded(
                  child: Text('WORK PACKAGE',
                      style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1))),
              SizedBox(
                  width: 80,
                  child: Text('RAG',
                      style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1))),
              SizedBox(
                  width: 150,
                  child: Text('TREND',
                      style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1))),
            ]),
          ),
          // Rows
          for (int i = 0; i < workstreams.length; i++)
            _WorkstreamRow(
              ws: workstreams[i],
              isLast: i == workstreams.length - 1,
            ),
        ],
      ),
    );
  }
}

class _WorkstreamRow extends StatelessWidget {
  final WorkstreamRagStatus ws;
  final bool isLast;

  const _WorkstreamRow({required this.ws, required this.isLast});

  Color get _ragColor => switch (ws.rag) {
        Rag.green      => KColors.phosphor,
        Rag.amber      => KColors.amber,
        Rag.red        => KColors.red,
        Rag.notStarted => KColors.textMuted,
      };

  Color get _ragBg => switch (ws.rag) {
        Rag.green      => KColors.phosDim,
        Rag.amber      => KColors.amberDim,
        Rag.red        => KColors.redDim,
        Rag.notStarted => Colors.transparent,
      };

  @override
  Widget build(BuildContext context) {
    final trendText = switch (ws.trend) {
      RagTrend.noData    => '—',
      RagTrend.steady    => '→ Steady',
      RagTrend.improved  => '↑ Improved'
          '${ws.previousRagLabel != null ? ' (was ${ws.previousRagLabel})' : ''}',
      RagTrend.worsened  => '↓ Worsened'
          '${ws.previousRagLabel != null ? ' (was ${ws.previousRagLabel})' : ''}',
    };
    final trendColor = switch (ws.trend) {
      RagTrend.improved => KColors.phosphor,
      RagTrend.worsened => KColors.red,
      _                 => KColors.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: KColors.border)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            ws.wp.shortCode != null
                ? '${ws.wp.shortCode} — ${ws.wp.name}'
                : ws.wp.name,
            style: const TextStyle(color: KColors.text, fontSize: 12),
          ),
        ),
        SizedBox(
          width: 80,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _ragBg,
              borderRadius: BorderRadius.circular(3),
              border: ws.rag == Rag.notStarted
                  ? Border.all(color: KColors.border2)
                  : null,
            ),
            child: Text(
              ws.rag.label,
              style: TextStyle(
                  color: _ragColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        SizedBox(
          width: 150,
          child: Text(trendText,
              style: TextStyle(
                  color: trendColor, fontSize: 11)),
        ),
      ]),
    );
  }
}
