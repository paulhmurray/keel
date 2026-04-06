import 'dart:convert';

import 'package:archive/archive.dart';

import '../database/database.dart';
import '../platform/web_download.dart';
import 'html_exporter.dart';
import 'pdf_exporter.dart';

class HandoverExporter {
  static Future<String> exportHandoverPack({
    required String projectName,
    required List<Risk> risks,
    required List<Assumption> assumptions,
    required List<Issue> issues,
    required List<ProgramDependency> dependencies,
    required List<JournalEntry> entries,
    required List<Person> persons,
    required List<StakeholderProfile> stakeholders,
    StatusReport? latestReport,
  }) async {
    final archive = Archive();

    // RAID log (HTML + PDF)
    final raidHtml = HtmlExporter.buildRaidHtml(
        projectName, risks, assumptions, issues, dependencies);
    _addText(archive, 'raid_log.html', raidHtml);
    final raidPdf = await PdfExporter.buildRaidBytes(
      projectName: projectName,
      risks: risks,
      assumptions: assumptions,
      issues: issues,
      dependencies: dependencies,
    );
    _addBytes(archive, 'raid_log.pdf', raidPdf);

    // Programme narrative (HTML only if entries exist)
    if (entries.isNotEmpty) {
      final narrativeHtml =
          HtmlExporter.buildNarrativeHtml(projectName, entries);
      _addText(archive, 'programme_narrative.html', narrativeHtml);
    }

    // Stakeholder map (HTML if stakeholders exist)
    if (stakeholders.isNotEmpty) {
      final mapHtml = HtmlExporter.buildStakeholderMapHtml(
          projectName, persons, stakeholders);
      _addText(archive, 'stakeholder_map.html', mapHtml);
    }

    // Latest status report (HTML + PDF if available)
    if (latestReport != null) {
      final reportHtml =
          HtmlExporter.buildReportHtml(latestReport, projectName);
      _addText(archive, 'status_report.html', reportHtml);
      final reportPdf = await PdfExporter.buildReportBytes(
          report: latestReport, projectName: projectName);
      _addBytes(archive, 'status_report.pdf', reportPdf);
    }

    // README
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final readme = '''KEEL HANDOVER PACK
$projectName
Generated: $date

CONTENTS
--------
${latestReport != null ? '* status_report.html  -- Latest status report (HTML)\n* status_report.pdf   -- Latest status report (PDF)\n' : ''}* raid_log.html        -- Full RAID log (HTML)
* raid_log.pdf         -- Full RAID log (PDF)
${entries.isNotEmpty ? '* programme_narrative.html -- Programme journal narrative (HTML)\n' : ''}${stakeholders.isNotEmpty ? '* stakeholder_map.html -- Stakeholder influence/stance map (HTML)\n' : ''}
HOW TO USE
----------
Open .html files in any web browser.
Open .pdf files in any PDF viewer.
''';
    _addText(archive, 'README.txt', readme);

    final zipBytes = ZipEncoder().encode(archive)!;
    final filename = 'keel_handover_${_slug(projectName)}_$date.zip';
    return saveAndOpen(filename, zipBytes, mimeType: 'application/zip');
  }

  static void _addText(Archive archive, String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static void _addBytes(Archive archive, String name, List<int> bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}
