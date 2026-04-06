import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/html_exporter.dart';

void main() {
  final _now = DateTime(2025, 3, 28);

  // ---------------------------------------------------------------------------
  // buildNarrativeHtml
  // ---------------------------------------------------------------------------

  group('HtmlExporter.buildNarrativeHtml', () {
    test('produces valid HTML structure', () {
      final html = HtmlExporter.buildNarrativeHtml('Project X', []);
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('</html>'));
    });

    test('contains project name in output', () {
      final html = HtmlExporter.buildNarrativeHtml('Alpha Programme', []);
      expect(html, contains('Alpha Programme'));
    });

    test('contains entry body text', () {
      final entry = JournalEntry(
        id: 'e1',
        projectId: 'p1',
        body: 'Discussed the delivery roadmap.',
        entryDate: '2025-03-28',
        parsed: false,
        createdAt: _now,
        updatedAt: _now,
      );
      final html = HtmlExporter.buildNarrativeHtml('P', [entry]);
      expect(html, contains('Discussed the delivery roadmap.'));
    });

    test('contains entry date', () {
      final entry = JournalEntry(
        id: 'e1',
        projectId: 'p1',
        body: 'Body',
        entryDate: '2025-11-15',
        parsed: false,
        createdAt: _now,
        updatedAt: _now,
      );
      final html = HtmlExporter.buildNarrativeHtml('P', [entry]);
      expect(html, contains('2025-11-15'));
    });

    test('includes entry title when present', () {
      final entry = JournalEntry(
        id: 'e1',
        projectId: 'p1',
        title: 'Sprint Review',
        body: 'We reviewed sprint goals.',
        entryDate: '2025-03-01',
        parsed: false,
        createdAt: _now,
        updatedAt: _now,
      );
      final html = HtmlExporter.buildNarrativeHtml('P', [entry]);
      expect(html, contains('Sprint Review'));
    });

    test('includes meeting context when present', () {
      final entry = JournalEntry(
        id: 'e1',
        projectId: 'p1',
        body: 'Notes from meeting.',
        entryDate: '2025-02-01',
        parsed: false,
        meetingContext: 'Weekly Governance Call',
        createdAt: _now,
        updatedAt: _now,
      );
      final html = HtmlExporter.buildNarrativeHtml('P', [entry]);
      expect(html, contains('Weekly Governance Call'));
    });

    test('escapes HTML special characters in body', () {
      final entry = JournalEntry(
        id: 'e1',
        projectId: 'p1',
        body: '<script>alert(1)</script>',
        entryDate: '2025-01-01',
        parsed: false,
        createdAt: _now,
        updatedAt: _now,
      );
      final html = HtmlExporter.buildNarrativeHtml('P', [entry]);
      expect(html, isNot(contains('<script>')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('escapes ampersand in project name', () {
      final html = HtmlExporter.buildNarrativeHtml('R&D Programme', []);
      expect(html, contains('R&amp;D Programme'));
    });

    test('multiple entries all appear in output', () {
      final entries = [
        JournalEntry(
            id: 'e1',
            projectId: 'p1',
            body: 'First entry',
            entryDate: '2025-01-01',
            parsed: false,
            createdAt: _now,
            updatedAt: _now),
        JournalEntry(
            id: 'e2',
            projectId: 'p1',
            body: 'Second entry',
            entryDate: '2025-01-02',
            parsed: false,
            createdAt: _now,
            updatedAt: _now),
      ];
      final html = HtmlExporter.buildNarrativeHtml('P', entries);
      expect(html, contains('First entry'));
      expect(html, contains('Second entry'));
    });
  });

  // ---------------------------------------------------------------------------
  // buildRaidHtml
  // ---------------------------------------------------------------------------

  group('HtmlExporter.buildRaidHtml', () {
    final risk = Risk(
      id: 'r1',
      projectId: 'p1',
      ref: 'RS01',
      description: 'Server outage risk',
      likelihood: 'high',
      impact: 'high',
      status: 'open',
      source: 'manual',
      createdAt: _now,
      updatedAt: _now,
    );

    final assumption = Assumption(
      id: 'a1',
      projectId: 'p1',
      ref: 'AS01',
      description: 'Funding will be secured',
      status: 'open',
      source: 'manual',
      createdAt: _now,
      updatedAt: _now,
    );

    test('produces valid HTML structure', () {
      final html = HtmlExporter.buildRaidHtml('P', [], [], [], []);
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('</html>'));
    });

    test('contains project name', () {
      final html = HtmlExporter.buildRaidHtml('Alpha Project', [], [], [], []);
      expect(html, contains('Alpha Project'));
    });

    test('contains risk description', () {
      final html = HtmlExporter.buildRaidHtml('P', [risk], [], [], []);
      expect(html, contains('Server outage risk'));
    });

    test('contains risk ref', () {
      final html = HtmlExporter.buildRaidHtml('P', [risk], [], [], []);
      expect(html, contains('RS01'));
    });

    test('contains assumption description', () {
      final html = HtmlExporter.buildRaidHtml('P', [], [assumption], [], []);
      expect(html, contains('Funding will be secured'));
    });

    test('all four RAID section headings are present', () {
      final html = HtmlExporter.buildRaidHtml('P', [], [], [], []);
      expect(html.toUpperCase(), contains('RISKS'));
      expect(html.toUpperCase(), contains('ASSUMPTIONS'));
      expect(html.toUpperCase(), contains('ISSUES'));
      expect(html.toUpperCase(), contains('DEPENDENCIES'));
    });

    test('escapes HTML special chars in description', () {
      final xssRisk = Risk(
        id: 'r2',
        projectId: 'p1',
        description: '<b>Bold risk</b>',
        likelihood: 'low',
        impact: 'low',
        status: 'open',
        source: 'manual',
        createdAt: _now,
        updatedAt: _now,
      );
      final html = HtmlExporter.buildRaidHtml('P', [xssRisk], [], [], []);
      expect(html, isNot(contains('<b>Bold risk</b>')));
      expect(html, contains('&lt;b&gt;Bold risk&lt;/b&gt;'));
    });
  });

  // ---------------------------------------------------------------------------
  // buildReportHtml
  // ---------------------------------------------------------------------------

  group('HtmlExporter.buildReportHtml', () {
    final report = StatusReport(
      id: 'rep1',
      projectId: 'p1',
      title: 'Q1 Status Report',
      overallRag: 'green',
      summary: 'All deliverables on track.',
      accomplishments: 'Phase 1 completed.',
      nextSteps: 'Begin phase 2.',
      createdAt: _now,
      updatedAt: _now,
    );

    test('produces valid HTML structure', () {
      final html = HtmlExporter.buildReportHtml(report, 'P');
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('</html>'));
    });

    test('contains report title', () {
      final html = HtmlExporter.buildReportHtml(report, 'My Project');
      expect(html, contains('Q1 Status Report'));
    });

    test('contains project name', () {
      final html = HtmlExporter.buildReportHtml(report, 'My Project');
      expect(html, contains('My Project'));
    });

    test('contains summary text', () {
      final html = HtmlExporter.buildReportHtml(report, 'P');
      expect(html, contains('All deliverables on track.'));
    });

    test('contains accomplishments text', () {
      final html = HtmlExporter.buildReportHtml(report, 'P');
      expect(html, contains('Phase 1 completed.'));
    });

    test('contains next steps text', () {
      final html = HtmlExporter.buildReportHtml(report, 'P');
      expect(html, contains('Begin phase 2.'));
    });

    test('RAG status is included', () {
      final html = HtmlExporter.buildReportHtml(report, 'P');
      expect(html.toLowerCase(), contains('green'));
    });

    test('minimal report (no optional fields) still builds', () {
      final minimal = StatusReport(
        id: 'r2',
        projectId: 'p1',
        title: 'Minimal',
        overallRag: 'amber',
        createdAt: _now,
        updatedAt: _now,
      );
      final html = HtmlExporter.buildReportHtml(minimal, 'P');
      expect(html, contains('Minimal'));
      expect(html.toLowerCase(), contains('amber'));
    });
  });

  // ---------------------------------------------------------------------------
  // buildStakeholderMapHtml
  // ---------------------------------------------------------------------------

  group('HtmlExporter.buildStakeholderMapHtml', () {
    final person = Person(
      id: 'per1',
      projectId: 'p1',
      name: 'Alice Smith',
      personType: 'stakeholder',
      createdAt: _now,
      updatedAt: _now,
    );

    final profile = StakeholderProfile(
      id: 'sp1',
      projectId: 'p1',
      personId: 'per1',
      influence: 'high',
      stance: 'supportive',
      createdAt: _now,
      updatedAt: _now,
    );

    test('produces valid HTML structure', () {
      final html = HtmlExporter.buildStakeholderMapHtml('P', [], []);
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('</html>'));
    });

    test('contains project name', () {
      final html = HtmlExporter.buildStakeholderMapHtml('Beta Programme', [], []);
      expect(html, contains('Beta Programme'));
    });

    test('contains person name', () {
      final html =
          HtmlExporter.buildStakeholderMapHtml('P', [person], [profile]);
      expect(html, contains('Alice Smith'));
    });

    test('person with role shows role in output', () {
      final personWithRole = Person(
        id: 'per2',
        projectId: 'p1',
        name: 'Bob Jones',
        role: 'Programme Director',
        personType: 'stakeholder',
        createdAt: _now,
        updatedAt: _now,
      );
      final profileForBob = StakeholderProfile(
        id: 'sp2',
        projectId: 'p1',
        personId: 'per2',
        influence: 'high',
        stance: 'neutral',
        createdAt: _now,
        updatedAt: _now,
      );
      final html = HtmlExporter.buildStakeholderMapHtml(
          'P', [personWithRole], [profileForBob]);
      expect(html, contains('Bob Jones'));
      expect(html, contains('Programme Director'));
    });

    test('escapes special chars in person name', () {
      final xssPerson = Person(
        id: 'per3',
        projectId: 'p1',
        name: 'O\'<script>Brien',
        personType: 'stakeholder',
        createdAt: _now,
        updatedAt: _now,
      );
      final xssProfile = StakeholderProfile(
        id: 'sp3',
        projectId: 'p1',
        personId: 'per3',
        influence: 'low',
        stance: 'unknown',
        createdAt: _now,
        updatedAt: _now,
      );
      final html =
          HtmlExporter.buildStakeholderMapHtml('P', [xssPerson], [xssProfile]);
      expect(html, isNot(contains('<script>')));
    });

    test('empty persons list still builds', () {
      final html = HtmlExporter.buildStakeholderMapHtml('P', [], []);
      expect(html, contains('Stakeholder Map'));
    });
  });
}
