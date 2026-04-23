import '../platform/web_download.dart';
import '../status/status_calculator.dart';

class StatusHtmlExporter {
  static Future<String> export({
    required String projectName,
    required ProgrammeStatusData data,
    required List<String> monthLabels,
    required String? narrative,
    required DateTime weekOf,
  }) async {
    final html = _buildHtml(
      projectName: projectName,
      data: data,
      monthLabels: monthLabels,
      narrative: narrative,
      weekOf: weekOf,
    );
    final slug =
        projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final weekStr = weekOf.toIso8601String().substring(0, 10);
    return saveTextAndOpen('status-$slug-$weekStr.html', html);
  }

  static String _buildHtml({
    required String projectName,
    required ProgrammeStatusData data,
    required List<String> monthLabels,
    required String? narrative,
    required DateTime weekOf,
  }) {
    final ragColor = switch (data.programmeRag) {
      Rag.green      => '#22c55e',
      Rag.amber      => '#f59e0b',
      Rag.red        => '#ef4444',
      Rag.notStarted => '#64748b',
    };
    final ragBg = switch (data.programmeRag) {
      Rag.green      => '#0d3325',
      Rag.amber      => '#3d2b05',
      Rag.red        => '#3f1515',
      Rag.notStarted => '#1a1f2e',
    };
    final weekStr =
        '${_dayOrd(weekOf.day)} ${_month(weekOf.month)} ${weekOf.year}';

    final sb = StringBuffer();
    sb.writeln('''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Status — $projectName</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #1a1f2e; color: #e2e8f0; font-family: 'Segoe UI', system-ui, sans-serif; font-size: 13px; padding: 32px; }
  h1 { font-size: 18px; font-weight: 700; color: #e2e8f0; }
  h2 { font-size: 11px; font-weight: 700; letter-spacing: 0.15em; color: #8a9faf; text-transform: uppercase; margin: 24px 0 8px; }
  .meta { color: #8a9faf; font-size: 11px; margin-top: 4px; }
  .card { background: #252b3b; border: 1px solid #2e3446; border-radius: 6px; padding: 16px; margin-bottom: 16px; }
  .rag-badge { display: inline-block; padding: 6px 16px; border-radius: 4px; font-weight: 700; font-size: 16px; background: $ragBg; color: $ragColor; border: 1px solid $ragColor; }
  .rag-row { display: flex; align-items: center; gap: 16px; }
  .rag-narrative { color: #e2e8f0; font-size: 13px; }
  .trend { font-size: 14px; color: #8a9faf; }
  table { width: 100%; border-collapse: collapse; }
  th { text-align: left; font-size: 9px; font-weight: 700; letter-spacing: 0.1em; color: #8a9faf; padding: 4px 8px; border-bottom: 1px solid #2e3446; }
  td { padding: 6px 8px; border-bottom: 1px solid #1e2538; font-size: 12px; }
  .rag-green { color: #34d399; font-weight: 600; }
  .rag-amber { color: #fbbf24; font-weight: 600; }
  .rag-red   { color: #ef4444; font-weight: 600; }
  .rag-na    { color: #64748b; }
  .milestone-row { display: flex; align-items: baseline; gap: 12px; padding: 6px 0; border-bottom: 1px solid #1e2538; }
  .milestone-icon { width: 20px; flex-shrink: 0; }
  .milestone-name { flex: 1; }
  .milestone-date { color: #8a9faf; font-size: 11px; width: 80px; }
  .milestone-owner { color: #8a9faf; font-size: 11px; width: 120px; }
  .risk-ref { color: #fbbf24; font-weight: 700; width: 40px; flex-shrink: 0; }
  .count-grid { display: flex; gap: 16px; flex-wrap: wrap; }
  .count-tile { background: #1a1f2e; border: 1px solid #2e3446; border-radius: 4px; padding: 12px 16px; min-width: 140px; }
  .count-num { font-size: 24px; font-weight: 700; color: #fbbf24; }
  .count-label { font-size: 10px; color: #8a9faf; margin-top: 2px; }
  .narrative-box { background: #1a1f2e; border: 1px solid #2e3446; border-radius: 4px; padding: 16px; white-space: pre-wrap; line-height: 1.6; font-size: 13px; color: #e2e8f0; }
</style>
</head>
<body>
<h1>Status — $projectName</h1>
<p class="meta">Week of $weekStr</p>
''');

    // Programme RAG
    sb.writeln('<h2>Programme RAG</h2>');
    sb.writeln('<div class="card">');
    sb.writeln('<div class="rag-row">');
    sb.writeln(
        '<span class="rag-badge">${data.programmeRag.label.toUpperCase()}</span>');
    sb.writeln(
        '<span class="trend">${data.programmeTrend.arrow} ${data.programmeTrend.label}</span>');
    sb.writeln('</div>');
    sb.writeln('</div>');

    // Narrative (if any)
    if (narrative != null && narrative.isNotEmpty) {
      sb.writeln('<h2>Status Narrative</h2>');
      sb.writeln('<div class="card"><div class="narrative-box">'
          '${_esc(narrative)}</div></div>');
    }

    // Workstreams
    sb.writeln('<h2>Workstreams</h2>');
    sb.writeln('<div class="card"><table>');
    sb.writeln('<tr><th>WORK PACKAGE</th><th>RAG</th><th>TREND</th></tr>');
    for (final ws in data.workstreams) {
      final ragClass = switch (ws.rag) {
        Rag.green      => 'rag-green',
        Rag.amber      => 'rag-amber',
        Rag.red        => 'rag-red',
        Rag.notStarted => 'rag-na',
      };
      final trend = ws.trend == RagTrend.noData
          ? '—'
          : '${ws.trend.arrow} ${ws.trend.label}'
              '${ws.previousRagLabel != null ? ' (was ${ws.previousRagLabel})' : ''}';
      sb.writeln('<tr>'
          '<td>${_esc(ws.wp.name)}</td>'
          '<td class="$ragClass">${ws.rag.label}</td>'
          '<td style="color:#8a9faf;font-size:11px;">$trend</td>'
          '</tr>');
    }
    sb.writeln('</table></div>');

    // Upcoming milestones
    if (data.upcomingMilestones.isNotEmpty) {
      sb.writeln('<h2>Upcoming Milestones (next 30 days)</h2>');
      sb.writeln('<div class="card">');
      for (final m in data.upcomingMilestones) {
        final icon = switch (m.activityType) {
          'hard_deadline' => '⚠',
          'gate'          => '◈',
          _               => '◆',
        };
        final monthLabel = m.startMonth != null &&
                m.startMonth! >= 0 &&
                m.startMonth! < monthLabels.length
            ? monthLabels[m.startMonth!]
            : m.startMonth != null
                ? 'M${m.startMonth}'
                : '—';
        sb.writeln('<div class="milestone-row">'
            '<span class="milestone-icon">$icon</span>'
            '<span class="milestone-name">${_esc(m.name)}</span>'
            '<span class="milestone-date">$monthLabel</span>'
            '<span class="milestone-owner">${_esc(m.owner ?? '—')}</span>'
            '</div>');
      }
      sb.writeln('</div>');
    }

    // Top risks
    if (data.topRisks.isNotEmpty) {
      sb.writeln('<h2>Top Risks</h2>');
      sb.writeln('<div class="card"><table>');
      sb.writeln('<tr><th>REF</th><th>LIKELIHOOD / IMPACT</th><th>DESCRIPTION</th></tr>');
      for (final r in data.topRisks) {
        sb.writeln('<tr>'
            '<td class="risk-ref">${_esc(r.ref ?? '—')}</td>'
            '<td style="color:#fbbf24;font-size:11px;">'
            '${_cap(r.likelihood)} / ${_cap(r.impact)}</td>'
            '<td>${_esc(r.description)}</td>'
            '</tr>');
      }
      sb.writeln('</table></div>');
    }

    // Pending decisions
    if (data.pendingDecisions.isNotEmpty) {
      sb.writeln('<h2>Pending Decisions</h2>');
      sb.writeln('<div class="card"><table>');
      sb.writeln('<tr><th>REF</th><th>DUE</th><th>DESCRIPTION</th></tr>');
      for (final d in data.pendingDecisions) {
        sb.writeln('<tr>'
            '<td style="color:#fbbf24;font-weight:700;">'
            '${_esc(d.ref ?? '—')}</td>'
            '<td style="color:#8a9faf;font-size:11px;">'
            '${_esc(d.dueDate ?? '—')}</td>'
            '<td>${_esc(d.description)}</td>'
            '</tr>');
      }
      sb.writeln('</table></div>');
    }

    // Counts
    sb.writeln('<h2>Counts</h2>');
    sb.writeln('<div class="card"><div class="count-grid">');
    _countTile(sb, '${data.overdueActionsCount}', 'Overdue actions');
    _countTile(sb, '${data.openActionsCount}', 'Open actions');
    _countTile(sb, '${data.pendingDecisionsCount}', 'Pending decisions');
    _countTile(sb, '${data.openRisksCount}', 'Open risks');
    sb.writeln('</div></div>');

    sb.writeln('</body></html>');
    return sb.toString();
  }

  static void _countTile(StringBuffer sb, String num, String label) {
    sb.writeln('<div class="count-tile">'
        '<div class="count-num">$num</div>'
        '<div class="count-label">$label</div>'
        '</div>');
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _month(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];

  static String _dayOrd(int d) {
    if (d >= 11 && d <= 13) return '${d}th';
    return switch (d % 10) {
      1 => '${d}st', 2 => '${d}nd', 3 => '${d}rd', _ => '${d}th'
    };
  }
}
