import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/portfolio/programme_pulse.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';

/// Portfolio overview, phase 1: one row per linked programme from its
/// latest pulse. Health by rules (computed RAG beside the self-reported
/// one, watermelon flagged), the decision system, flow and completeness.
/// Phase 2 adds the heatmap, trends and the cross-programme roll-ups.
///
/// Web-safe by construction: reads the local pulse table only.
class PortfolioView extends StatelessWidget {
  const PortfolioView({super.key});

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProjectProvider>();
    final portfolioId = pp.currentProjectId;
    if (portfolioId == null || !pp.isPortfolio) {
      return Center(
        child: Text('Select a portfolio.',
            style: TextStyle(color: KColors.textDim)),
      );
    }
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<PortfolioPulse>>(
      stream: db.portfolioPulsesDao.watchForPortfolio(portfolioId),
      builder: (context, snap) {
        final rows = latestPerProgramme(snap.data ?? const []);
        return _PortfolioBody(
          portfolioName: pp.currentProject?.name ?? 'Portfolio',
          rows: rows,
          loading: snap.connectionState == ConnectionState.waiting,
        );
      },
    );
  }
}

class _PortfolioBody extends StatelessWidget {
  final String portfolioName;
  final List<PortfolioPulse> rows;
  final bool loading;
  const _PortfolioBody({
    required this.portfolioName,
    required this.rows,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final pulses = <PortfolioPulse, ProgrammePulse>{
      for (final r in rows) r: _decode(r),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('PORTFOLIO PULSE'),
          const SizedBox(height: 4),
          Text(
            rows.isEmpty
                ? 'No programme pulses yet.'
                : '${rows.length} programme${rows.length == 1 ? '' : 's'} '
                    'reporting. Health is computed from each programme\'s '
                    'data; the reported colour sits beside it.',
            style: TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty && !loading)
            _EmptyState()
          else
            _PulseTable(rows: rows, pulses: pulses),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionLabel('ACROSS THE PORTFOLIO'),
            const SizedBox(height: 8),
            _Totals(pulses: pulses.values.toList()),
          ],
        ],
      ),
    );
  }

  static ProgrammePulse _decode(PortfolioPulse r) {
    try {
      return ProgrammePulse.fromJson(
          (jsonDecode(r.payload) as Map).cast<String, dynamic>());
    } catch (_) {
      return ProgrammePulse.fromJson(const {});
    }
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Link programmes from Settings → Portfolio Links. Generate a code '
        'here and have each programme manager paste it into their '
        'programme\'s settings. Each linked programme sends one pulse a '
        'week; the first arrives on its next sync or launch.',
        style: TextStyle(color: KColors.textDim, fontSize: 12, height: 1.5),
      ),
    );
  }
}

class _PulseTable extends StatelessWidget {
  final List<PortfolioPulse> rows;
  final Map<PortfolioPulse, ProgrammePulse> pulses;
  const _PulseTable({required this.rows, required this.pulses});

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(
      color: KColors.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
    return Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text('PROGRAMME', style: head)),
                Expanded(flex: 2, child: Text('COMPUTED', style: head)),
                Expanded(flex: 2, child: Text('REPORTED', style: head)),
                Expanded(flex: 2, child: Text('MILESTONES', style: head)),
                Expanded(flex: 2, child: Text('RISKS', style: head)),
                Expanded(flex: 3, child: Text('DECISIONS', style: head)),
                Expanded(flex: 2, child: Text('FINANCE', style: head)),
                Expanded(flex: 2, child: Text('LOAD', style: head)),
                Expanded(flex: 2, child: Text('DATA', style: head)),
                Expanded(flex: 2, child: Text('PULSE', style: head)),
              ],
            ),
          ),
          Divider(height: 1, color: KColors.border),
          for (final r in rows) _PulseRow(row: r, pulse: pulses[r]!),
        ],
      ),
    );
  }
}

class _PulseRow extends StatelessWidget {
  final PortfolioPulse row;
  final ProgrammePulse pulse;
  const _PulseRow({required this.row, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final h = pulse.health;
    final d = pulse.decisions;
    final f = pulse.finance;
    final body = TextStyle(color: KColors.text, fontSize: 12);
    final dim = TextStyle(color: KColors.textDim, fontSize: 11);
    final age = DateTime.now().difference(pulse.capturedAt).inDays;
    // A same-machine programme can be opened straight from its row; a
    // remote one (no local project row) has nothing to open.
    final pp = context.read<ProjectProvider>();
    final isLocal = pp.projects.any((p) => p.id == row.sourceProgrammeId);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.sourceProgrammeName ?? row.sourceProgrammeId,
                    style: body.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLocal)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.open_in_new,
                        size: 13, color: KColors.textMuted),
                  ),
              ],
            ),
          ),
          Expanded(flex: 2, child: _RagChip(h.computedRag)),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _RagChip(h.reportedRag ?? 'not_started',
                    label: h.reportedRag == null ? 'none' : null),
                if (h.watermelon) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Reported better than the data says',
                    child: Icon(Icons.warning_amber_rounded,
                        size: 14, color: KColors.red),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              h.overdueMilestones > 0
                  ? '${h.overdueMilestones} overdue · ${h.openMilestones} open'
                  : '${h.openMilestones} open',
              style: h.overdueMilestones > 0 ? body.copyWith(color: KColors.red) : body,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${pulse.raid.openRisks} open'
              '${pulse.raid.highOpen > 0 ? ' · ${pulse.raid.highOpen} high' : ''}'
              '${pulse.raid.escalatedOpen > 0 ? ' · ${pulse.raid.escalatedOpen} esc' : ''}',
              style: body,
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${d.open} open'
                  '${d.pastNeedBy > 0 ? ' · ${d.pastNeedBy} past need-by' : ''}',
                  style: d.pastNeedBy > 0 ? body.copyWith(color: KColors.red) : body,
                ),
                Text(
                  d.medianLatencyDays == null
                      ? 'no decisions made in 90d'
                      : 'median ${d.medianLatencyDays}d raised→made',
                  style: dim,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: f == null
                ? Text('—', style: dim)
                : Text(
                    f.varianceBp == null
                        ? 'no forecast'
                        : '${_bp(f.varianceBp!)}'
                            '${f.breachingProjects > 0 ? ' · ${f.breachingProjects} breach' : ''}',
                    style: f.breachingProjects > 0
                        ? body.copyWith(color: KColors.red)
                        : body,
                  ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              pulse.flow.peopleOn3PlusProjects > 0
                  ? '${pulse.flow.peopleOn3PlusProjects} on 3+ projects'
                  : '${pulse.flow.projectsLinked} projects',
              style: body,
            ),
          ),
          Expanded(
            flex: 2,
            child: _Completeness(score: pulse.completeness.score),
          ),
          Expanded(
            flex: 2,
            child: Text(
              age == 0 ? 'today' : '${age}d ago',
              style: age > 10 ? dim.copyWith(color: KColors.amber) : dim,
            ),
          ),
        ],
      ),
    );
    if (!isLocal) return content;
    return Tooltip(
      message: 'Open ${row.sourceProgrammeName ?? 'programme'}',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () => pp.selectProjectById(row.sourceProgrammeId),
        hoverColor: KColors.surface2,
        child: content,
      ),
    );
  }

  static String _bp(int bp) {
    final pct = bp / 100;
    final sign = pct > 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(1)}%';
  }
}

class _Totals extends StatelessWidget {
  final List<ProgrammePulse> pulses;
  const _Totals({required this.pulses});

  @override
  Widget build(BuildContext context) {
    final red = pulses.where((p) => p.health.computedRag == 'red').length;
    final amber = pulses.where((p) => p.health.computedRag == 'amber').length;
    final watermelons = pulses.where((p) => p.health.watermelon).length;
    final pastNeedBy =
        pulses.fold<int>(0, (n, p) => n + p.decisions.pastNeedBy);
    final overdueMs =
        pulses.fold<int>(0, (n, p) => n + p.health.overdueMilestones);
    final escalated = pulses.fold<int>(0, (n, p) => n + p.raid.escalatedOpen);
    final loaded =
        pulses.fold<int>(0, (n, p) => n + p.flow.peopleOn3PlusProjects);
    final avgData = pulses.isEmpty
        ? 0
        : (pulses.fold<int>(0, (n, p) => n + p.completeness.score) /
                pulses.length)
            .round();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Stat('Red / amber (computed)', '$red / $amber',
            alert: red > 0),
        _Stat('Watermelons', '$watermelons', alert: watermelons > 0),
        _Stat('Decisions past need-by', '$pastNeedBy', alert: pastNeedBy > 0),
        _Stat('Overdue milestones', '$overdueMs', alert: overdueMs > 0),
        _Stat('Escalated open', '$escalated'),
        _Stat('People on 3+ projects', '$loaded', alert: loaded > 0),
        _Stat('Data completeness', '$avgData%'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool alert;
  const _Stat(this.label, this.value, {this.alert = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: alert ? KColors.red : KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  color: alert ? KColors.red : KColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: KColors.textDim, fontSize: 11)),
        ],
      ),
    );
  }
}

class _RagChip extends StatelessWidget {
  final String rag;
  final String? label;
  const _RagChip(this.rag, {this.label});

  @override
  Widget build(BuildContext context) {
    final color = switch (rag) {
      'red' => KColors.red,
      'amber' => KColors.amber,
      'green' => KColors.phosphor,
      _ => KColors.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        (label ?? rag.replaceAll('_', ' ')).toUpperCase(),
        style: TextStyle(
            color: color, fontSize: 9.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Completeness extends StatelessWidget {
  final int score;
  const _Completeness({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? KColors.phosphor
        : score >= 50
            ? KColors.amber
            : KColors.red;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 6,
              backgroundColor: KColors.surface2,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('$score%', style: TextStyle(color: KColors.textDim, fontSize: 11)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: KColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
      ),
    );
  }
}
