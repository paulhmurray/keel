import '../database/database.dart';
import '../platform/web_download.dart';

class HtmlExporter {
  /// Export a status report as a self-contained HTML file.
  /// Returns the path of the written file.
  static Future<String> exportReport({
    required StatusReport report,
    required String projectName,
  }) async {
    final html = _buildReportHtml(report, projectName);
    return _writeAndOpen(html, 'report_${_slug(report.title)}.html');
  }

  /// Export RAID log as a self-contained HTML file.
  static Future<String> exportRaid({
    required String projectName,
    required List<Risk> risks,
    required List<Assumption> assumptions,
    required List<Issue> issues,
    required List<ProgramDependency> dependencies,
  }) async {
    final html =
        _buildRaidHtml(projectName, risks, assumptions, issues, dependencies);
    return _writeAndOpen(html, 'raid_${_slug(projectName)}.html');
  }

  /// Export programme narrative as a self-contained HTML file.
  static Future<String> exportNarrative({
    required String projectName,
    required List<JournalEntry> entries,
  }) async {
    final html = buildNarrativeHtml(projectName, entries);
    return _writeAndOpen(html, 'narrative_${_slug(projectName)}.html');
  }

  /// Export stakeholder map as a self-contained HTML file.
  static Future<String> exportStakeholderMap({
    required String projectName,
    required List<Person> persons,
    required List<StakeholderProfile> stakeholders,
  }) async {
    final html = buildStakeholderMapHtml(projectName, persons, stakeholders);
    return _writeAndOpen(html, 'stakeholder_map_${_slug(projectName)}.html');
  }

  // ---------------------------------------------------------------------------
  // Public HTML builders (return strings, no file I/O — used by HandoverExporter)
  // ---------------------------------------------------------------------------

  static String buildReportHtml(StatusReport report, String projectName) =>
      _buildReportHtml(report, projectName);

  static String buildRaidHtml(
    String projectName,
    List<Risk> risks,
    List<Assumption> assumptions,
    List<Issue> issues,
    List<ProgramDependency> dependencies,
  ) =>
      _buildRaidHtml(projectName, risks, assumptions, issues, dependencies);

  static String buildNarrativeHtml(
      String projectName, List<JournalEntry> entries) {
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final entryBlocks = StringBuffer();
    for (final entry in entries) {
      final entryDate = entry.entryDate;
      final title = (entry.title != null && entry.title!.isNotEmpty)
          ? _esc(entry.title!)
          : 'Journal Entry';
      final meetingMeta = (entry.meetingContext != null &&
              entry.meetingContext!.isNotEmpty)
          ? '<div class="entry-meta">&#128197; ${_esc(entry.meetingContext!)}</div>'
          : '';
      entryBlocks.writeln('''<div class="entry">
  <div class="entry-date">${_esc(entryDate)}</div>
  <div class="entry-title">$title</div>
  $meetingMeta
  <div class="entry-body">${_esc(entry.body)}</div>
</div>''');
    }

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Programme Narrative \u2013 ${_esc(projectName)}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           max-width: 860px; margin: 40px auto; padding: 0 24px; color: #111827;
           background: #f9fafb; line-height: 1.7; }
    .page-header { margin-bottom: 40px; border-bottom: 2px solid #e5e7eb; padding-bottom: 20px; }
    .page-header h1 { font-size: 26px; color: #111827; margin: 0 0 6px; }
    .page-header .subtitle { color: #6b7280; font-size: 14px; }
    .entry { background: white; border-radius: 8px; padding: 28px 32px;
             margin-bottom: 20px; box-shadow: 0 1px 3px rgba(0,0,0,.08);
             border-left: 4px solid #f59e0b; }
    .entry-date { font-size: 11px; text-transform: uppercase; letter-spacing: 1px;
                  color: #9ca3af; font-weight: 600; margin-bottom: 8px; }
    .entry-title { font-size: 17px; font-weight: 700; color: #111827; margin: 0 0 12px; }
    .entry-meta { font-size: 12px; color: #9ca3af; margin-bottom: 16px; }
    .entry-body { color: #374151; font-size: 14px; white-space: pre-wrap; }
    .footer { text-align: center; color: #9ca3af; font-size: 12px;
              margin-top: 40px; padding-bottom: 40px; }
  </style>
</head>
<body>
  <div class="page-header">
    <h1>Programme Narrative \u2014 ${_esc(projectName)}</h1>
    <div class="subtitle">${entries.length} journal ${entries.length == 1 ? 'entry' : 'entries'} \u00b7 Generated $date</div>
  </div>
  $entryBlocks
  <div class="footer">${_esc(projectName)} \u00b7 Programme Journal Export</div>
</body>
</html>''';
  }

  static String buildStakeholderMapHtml(
    String projectName,
    List<Person> persons,
    List<StakeholderProfile> stakeholders,
  ) {
    final date = DateTime.now().toIso8601String().substring(0, 10);

    // Build a lookup: personId -> Person
    final personMap = {for (final p in persons) p.id: p};

    // Determine unique stances (sorted with known order first)
    final stanceOrder = [
      'supportive',
      'neutral',
      'resistant',
      'blocker',
    ];
    final allStances = <String>{};
    for (final s in stakeholders) {
      allStances.add(s.stance ?? 'unknown');
    }
    final sortedStances = [
      ...stanceOrder.where(allStances.contains),
      ...allStances
          .where((s) => !stanceOrder.contains(s) && s != 'unknown')
          .toList()
        ..sort(),
      if (allStances.contains('unknown')) 'unknown',
    ];

    if (sortedStances.isEmpty) {
      sortedStances.add('unknown');
    }

    // Influence rows
    final influenceLevels = ['high', 'medium', 'low', 'unknown'];

    // Grid header row
    final headerCells = StringBuffer();
    headerCells.write('<div class="axis-label">Influence \\ Stance</div>');
    for (final stance in sortedStances) {
      headerCells
          .write('<div class="axis-label">${_esc(_capitalise(stance))}</div>');
    }

    // Grid body rows
    final gridRows = StringBuffer();
    for (final influence in influenceLevels) {
      // Check if any stakeholder falls in this row
      final rowStakeholders = stakeholders
          .where((s) => (s.influence ?? 'unknown') == influence)
          .toList();
      if (rowStakeholders.isEmpty) continue;

      gridRows
          .write('<div class="row-label">${_esc(_capitalise(influence))}</div>');
      for (final stance in sortedStances) {
        final cellStakeholders =
            rowStakeholders.where((s) => (s.stance ?? 'unknown') == stance);
        final cards = StringBuffer();
        for (final s in cellStakeholders) {
          final person = personMap[s.personId];
          final name = person?.name ?? 'Unknown';
          final role = person?.role ?? '';
          cards.write('''<div class="person-card">
  <div class="person-name">${_esc(name)}</div>
  ${role.isNotEmpty ? '<div class="person-role">${_esc(role)}</div>' : ''}
</div>''');
        }
        gridRows.write('<div class="cell">$cards</div>');
      }
    }

    final colCount = sortedStances.length;

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Stakeholder Map \u2013 ${_esc(projectName)}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           max-width: 1000px; margin: 40px auto; padding: 0 24px; color: #111827;
           background: #f9fafb; }
    h1 { font-size: 22px; margin-bottom: 4px; }
    .subtitle { color: #6b7280; font-size: 13px; margin-bottom: 32px; }
    .grid { display: grid; grid-template-columns: 100px repeat($colCount, 1fr);
            gap: 2px; }
    .axis-label { background: #1f2937; color: white; padding: 10px; font-size: 11px;
                  font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px;
                  text-align: center; border-radius: 4px; }
    .row-label { background: #374151; color: white; padding: 10px; font-size: 11px;
                 font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px;
                 text-align: center; border-radius: 4px; display: flex;
                 align-items: center; justify-content: center; }
    .cell { background: white; border: 1px solid #e5e7eb; border-radius: 6px;
            padding: 12px; min-height: 80px; }
    .person-card { background: #f3f4f6; border-radius: 4px; padding: 6px 8px;
                   margin-bottom: 6px; }
    .person-name { font-size: 12px; font-weight: 600; color: #111827; }
    .person-role { font-size: 11px; color: #6b7280; }
    .footer { text-align: center; color: #9ca3af; font-size: 12px;
              margin-top: 32px; padding-bottom: 40px; }
  </style>
</head>
<body>
  <h1>Stakeholder Map \u2014 ${_esc(projectName)}</h1>
  <div class="subtitle">Generated $date \u00b7 ${stakeholders.length} stakeholders</div>
  <div class="grid">
    $headerCells
    $gridRows
  </div>
  <div class="footer">${_esc(projectName)} \u00b7 Stakeholder Map Export</div>
</body>
</html>''';
  }

  // ---------------------------------------------------------------------------
  // Private HTML builders
  // ---------------------------------------------------------------------------

  static String _buildReportHtml(StatusReport report, String projectName) {
    final ragColor = _ragHexColor(report.overallRag);
    final ragBg = _ragBgColor(report.overallRag);
    final ragFg = _ragFgColor(report.overallRag);
    final generatedDate = DateTime.now().toIso8601String().substring(0, 10);

    final sections = StringBuffer();

    if (report.summary != null && report.summary!.isNotEmpty) {
      sections.writeln(_reportSection('Summary', _esc(report.summary!)));
    }
    if (report.accomplishments != null && report.accomplishments!.isNotEmpty) {
      sections
          .writeln(_reportSection('Accomplishments', _esc(report.accomplishments!)));
    }
    if (report.nextSteps != null && report.nextSteps!.isNotEmpty) {
      sections.writeln(_reportSection('Next Steps', _esc(report.nextSteps!)));
    }
    if (report.risksHighlighted != null &&
        report.risksHighlighted!.isNotEmpty) {
      sections.writeln(
          _reportSection('Risks Highlighted', _esc(report.risksHighlighted!)));
    }

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_esc(report.title)}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           max-width: 900px; margin: 40px auto; padding: 0 20px; color: #1a1a2e;
           background: #f8f9fa; line-height: 1.6; }
    .header { background: white; border-radius: 8px; padding: 28px 32px;
              margin-bottom: 24px; box-shadow: 0 1px 4px rgba(0,0,0,.1);
              border-left: 6px solid $ragColor; }
    .header h1 { margin: 0 0 4px; font-size: 24px; color: #111827; }
    .meta { color: #6b7280; font-size: 14px; margin-top: 8px; }
    .meta span + span::before { content: ' \u00b7 '; }
    .rag { display: inline-block; padding: 3px 12px; border-radius: 12px;
           font-size: 12px; font-weight: 700; text-transform: uppercase;
           background: $ragBg; color: $ragFg; }
    .section { background: white; border-radius: 8px; padding: 24px 32px;
               margin-bottom: 16px; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
    .section h2 { font-size: 13px; text-transform: uppercase; letter-spacing: 1px;
                  color: #00acc1; margin: 0 0 12px; padding-bottom: 8px;
                  border-bottom: 1px solid #e5e7eb; }
    .section p { margin: 0; white-space: pre-wrap; color: #374151; }
    .footer { text-align: center; color: #9ca3af; font-size: 12px; margin-top: 32px; padding-bottom: 40px; }
  </style>
</head>
<body>
  <div class="header">
    <h1>${_esc(report.title)}</h1>
    <div class="meta">
      <span><strong>Project:</strong> ${_esc(projectName)}</span>
      ${report.period != null ? '<span><strong>Period:</strong> ${_esc(report.period!)}</span>' : ''}
      <span><span class="rag">${_esc(report.overallRag.toUpperCase())}</span></span>
    </div>
  </div>
  $sections
  <div class="footer">Generated $generatedDate</div>
</body>
</html>''';
  }

  static String _reportSection(String title, String content) {
    return '''  <div class="section">
    <h2>$title</h2>
    <p>$content</p>
  </div>''';
  }

  static String _buildRaidHtml(
    String projectName,
    List<Risk> risks,
    List<Assumption> assumptions,
    List<Issue> issues,
    List<ProgramDependency> dependencies,
  ) {
    final generatedDate = DateTime.now().toIso8601String().substring(0, 10);

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>RAID Log \u2013 ${_esc(projectName)}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           max-width: 1100px; margin: 40px auto; padding: 0 20px; color: #1a1a2e;
           background: #f8f9fa; line-height: 1.6; }
    h1 { font-size: 24px; color: #111827; margin-bottom: 4px; }
    .subtitle { color: #6b7280; font-size: 14px; margin-bottom: 32px; }
    .section { background: white; border-radius: 8px; padding: 24px 32px;
               margin-bottom: 24px; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
    .section h2 { font-size: 15px; font-weight: 700; color: #00acc1;
                  margin: 0 0 16px; padding-bottom: 8px;
                  border-bottom: 2px solid #e5e7eb; }
    table { width: 100%; border-collapse: collapse; }
    th { background: #f3f4f6; text-align: left; padding: 8px 12px;
         font-size: 12px; text-transform: uppercase; color: #6b7280;
         letter-spacing: 0.5px; }
    td { padding: 10px 12px; border-bottom: 1px solid #e5e7eb;
         font-size: 13px; vertical-align: top; color: #374151; }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: #f9fafb; }
    .badge { display: inline-block; padding: 1px 8px; border-radius: 10px;
             font-size: 11px; font-weight: 600; }
    .badge-open { background: #dbeafe; color: #1d4ed8; }
    .badge-closed { background: #f3f4f6; color: #6b7280; }
    .badge-resolved { background: #f3f4f6; color: #6b7280; }
    .badge-in_progress { background: #ffedd5; color: #c2410c; }
    .badge-mitigated { background: #dcfce7; color: #15803d; }
    .badge-accepted { background: #f3e8ff; color: #7e22ce; }
    .badge-validated { background: #dcfce7; color: #15803d; }
    .badge-pending { background: #fef9c3; color: #a16207; }
    .badge-high { background: #fee2e2; color: #b91c1c; }
    .badge-medium { background: #fef3c7; color: #92400e; }
    .badge-low { background: #d1fae5; color: #065f46; }
    .empty { color: #9ca3af; font-style: italic; font-size: 13px; }
    .footer { text-align: center; color: #9ca3af; font-size: 12px;
              margin-top: 32px; padding-bottom: 40px; }
  </style>
</head>
<body>
  <h1>RAID Log \u2013 ${_esc(projectName)}</h1>
  <div class="subtitle">Generated $generatedDate</div>

  <div class="section">
    <h2>Risks (${risks.length})</h2>
    ${_risksTable(risks)}
  </div>

  <div class="section">
    <h2>Assumptions (${assumptions.length})</h2>
    ${_assumptionsTable(assumptions)}
  </div>

  <div class="section">
    <h2>Issues (${issues.length})</h2>
    ${_issuesTable(issues)}
  </div>

  <div class="section">
    <h2>Dependencies (${dependencies.length})</h2>
    ${_dependenciesTable(dependencies)}
  </div>

  <div class="footer">Keel \u2013 RAID Export</div>
</body>
</html>''';
  }

  static String _risksTable(List<Risk> items) {
    if (items.isEmpty) {
      return '<p class="empty">No risks recorded.</p>';
    }
    final rows = items.map((r) => '''
      <tr>
        <td>${_esc(r.ref ?? '')}</td>
        <td>${_esc(r.description)}</td>
        <td>${_badge(r.likelihood)}</td>
        <td>${_badge(r.impact)}</td>
        <td>${_esc(r.owner ?? '')}</td>
        <td>${_badge(r.status)}</td>
      </tr>''').join('\n');
    return '''<table>
      <thead><tr>
        <th>Ref</th><th>Description</th><th>Likelihood</th>
        <th>Impact</th><th>Owner</th><th>Status</th>
      </tr></thead>
      <tbody>$rows</tbody>
    </table>''';
  }

  static String _assumptionsTable(List<Assumption> items) {
    if (items.isEmpty) {
      return '<p class="empty">No assumptions recorded.</p>';
    }
    final rows = items.map((a) => '''
      <tr>
        <td>${_esc(a.ref ?? '')}</td>
        <td>${_esc(a.description)}</td>
        <td>${_esc(a.owner ?? '')}</td>
        <td>${_badge(a.status)}</td>
      </tr>''').join('\n');
    return '''<table>
      <thead><tr>
        <th>Ref</th><th>Description</th><th>Owner</th><th>Status</th>
      </tr></thead>
      <tbody>$rows</tbody>
    </table>''';
  }

  static String _issuesTable(List<Issue> items) {
    if (items.isEmpty) {
      return '<p class="empty">No issues recorded.</p>';
    }
    final rows = items.map((i) => '''
      <tr>
        <td>${_esc(i.ref ?? '')}</td>
        <td>${_esc(i.description)}</td>
        <td>${_badge(i.priority)}</td>
        <td>${_esc(i.owner ?? '')}</td>
        <td>${_badge(i.status)}</td>
      </tr>''').join('\n');
    return '''<table>
      <thead><tr>
        <th>Ref</th><th>Description</th><th>Priority</th>
        <th>Owner</th><th>Status</th>
      </tr></thead>
      <tbody>$rows</tbody>
    </table>''';
  }

  static String _dependenciesTable(List<ProgramDependency> items) {
    if (items.isEmpty) {
      return '<p class="empty">No dependencies recorded.</p>';
    }
    final rows = items.map((d) => '''
      <tr>
        <td>${_esc(d.ref ?? '')}</td>
        <td>${_esc(d.description)}</td>
        <td>${_esc(d.dependencyType)}</td>
        <td>${_esc(d.owner ?? '')}</td>
        <td>${_esc(d.dueDate ?? '')}</td>
        <td>${_badge(d.status)}</td>
      </tr>''').join('\n');
    return '''<table>
      <thead><tr>
        <th>Ref</th><th>Description</th><th>Type</th>
        <th>Owner</th><th>Due</th><th>Status</th>
      </tr></thead>
      <tbody>$rows</tbody>
    </table>''';
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _badge(String value) {
    final cls = 'badge-${value.replaceAll(' ', '_')}';
    return '<span class="badge $cls">${_esc(value)}</span>';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _ragHexColor(String rag) {
    switch (rag.toLowerCase()) {
      case 'red':
        return '#ef4444';
      case 'amber':
        return '#f59e0b';
      default:
        return '#22c55e';
    }
  }

  static String _ragBgColor(String rag) {
    switch (rag.toLowerCase()) {
      case 'red':
        return '#fee2e2';
      case 'amber':
        return '#fef3c7';
      default:
        return '#dcfce7';
    }
  }

  static String _ragFgColor(String rag) {
    switch (rag.toLowerCase()) {
      case 'red':
        return '#b91c1c';
      case 'amber':
        return '#92400e';
      default:
        return '#15803d';
    }
  }

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  static Future<String> _writeAndOpen(String html, String filename) async {
    return saveTextAndOpen(filename, html);
  }
}
