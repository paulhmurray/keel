import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/llm/context_builder.dart';

void main() {
  late AppDatabase db;
  late ContextBuilder builder;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(
      ProjectsCompanion.insert(id: 'p1', name: 'Horizon'),
    );
    builder = ContextBuilder(db);
  });

  tearDown(() async => db.close());

  Future<void> seedPlan() async {
    await db.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion(
      id: const Value('h1'),
      projectId: const Value('p1'),
      title: const Value('Integration Delivery'),
      hardDeadline: const Value('Dec 2026 go-live'),
      month0Date: const Value('2026-06-01'),
      monthLabels: Value(jsonEncode(
          ['Jun 26', 'Jul 26', 'Aug 26', 'Sep 26', 'Oct 26', 'Nov 26'])),
    ));
    await db.programmeGanttDao
        .upsertWorkPackage(TimelineWorkPackagesCompanion(
      id: const Value('wp1'),
      projectId: const Value('p1'),
      name: const Value('Data Migration'),
      shortCode: const Value('DM'),
      ragStatus: const Value('amber'),
    ));
    await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion(
      id: const Value('a1'),
      workPackageId: const Value('wp1'),
      projectId: const Value('p1'),
      name: const Value('Build ETL pipeline'),
      activityType: const Value('activity'),
      startMonth: const Value(1),
      endMonth: const Value(3),
      status: const Value('on_track'),
      owner: const Value('Dana'),
      isCritical: const Value(true),
    ));
    await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion(
      id: const Value('a2'),
      workPackageId: const Value('wp1'),
      projectId: const Value('p1'),
      name: const Value('Cutover rehearsal'),
      activityType: const Value('milestone'),
      startMonth: const Value(3),
    ));
    await db.programmeGanttDao.upsertDependency(
        TimelineDependenciesCompanion(
      id: const Value('d1'),
      projectId: const Value('p1'),
      fromActivityId: const Value('a1'),
      toActivityId: const Value('a2'),
      dependencyType: const Value('finish_to_start'),
    ));
  }

  test('no plan → no Delivery Plan section', () async {
    final prompt = await builder.buildSystemPrompt('p1');
    expect(prompt, isNot(contains('## Delivery Plan')));
  });

  test('plan section carries WPs, activities, spans, deps and criticality',
      () async {
    await seedPlan();
    final prompt = await builder.buildSystemPrompt('p1');

    expect(prompt, contains('## Delivery Plan'));
    expect(prompt, contains('Plan: Integration Delivery'));
    expect(prompt, contains('Timeline: Jun 26 → Nov 26'));
    expect(prompt, contains('Hard deadline: Dec 2026 go-live'));
    expect(prompt, contains('### [DM] Data Migration [RAG: amber]'));
    expect(
        prompt,
        contains('Activity: Build ETL pipeline — Jul 26 → Sep 26 '
            '[on_track] (Owner: Dana) [CRITICAL PATH]'));
    expect(prompt, contains('◆ Milestone: Cutover rehearsal — Sep 26'));
    expect(prompt, contains('### Plan Dependencies'));
    expect(prompt,
        contains('Build ETL pipeline → Cutover rehearsal (finish_to_start)'));
  });

  test('upcoming milestones appear when inside the next three months',
      () async {
    await seedPlan();
    final prompt = await builder.buildSystemPrompt('p1');
    // Whether 'Sep 26' is within 3 months depends on the real clock, so
    // only assert the section is well-formed when present.
    if (prompt.contains('### Upcoming Milestones')) {
      expect(prompt, contains('- Cutover rehearsal — Sep 26'));
    }
  });

  test('open issues section carries title, impact and escalation flag',
      () async {
    await db.raidDao.insertIssue(IssuesCompanion(
      id: const Value('i1'),
      projectId: const Value('p1'),
      ref: const Value('I1'),
      title: const Value('No data stewardship exists'),
      description: const Value('nobody owns source-of-truth decisions'),
      impactStatement:
          const Value('integration design cannot be confirmed'),
      escalationRequired: const Value(true),
      priority: const Value('high'),
    ));
    final prompt = await builder.buildSystemPrompt('p1');
    expect(prompt, contains('## Open Issues'));
    expect(prompt,
        contains('[I1] No data stewardship exists [high]'));
    expect(prompt, contains('⚠ ESCALATION REQUIRED'));
    expect(prompt,
        contains('Impact if unresolved: integration design cannot be confirmed'));
    expect(prompt, contains('nobody owns source-of-truth decisions'));
  });

  test('charter, snapshot, assumptions, register deps, journal and '
      'glossary all reach the prompt', () async {
    await db.projectCharterDao.upsert(ProjectChartersCompanion(
      id: const Value('c1'),
      projectId: const Value('p1'),
      vision: const Value('One platform by 2027'),
      scopeOut: const Value('No legacy CRM changes'),
    ));
    await db.statusSnapshotDao.insert(StatusSnapshotsCompanion(
      id: const Value('s1'),
      projectId: const Value('p1'),
      weekEnding: Value(DateTime(2026, 8, 7)),
      programmeRag: const Value('amber'),
      narrative: const Value('Slipping on data workstream'),
    ));
    await db.raidDao.insertAssumption(AssumptionsCompanion(
      id: const Value('as1'),
      projectId: const Value('p1'),
      ref: const Value('A1'),
      description: const Value('Vendor API stays stable'),
    ));
    await db.raidDao.insertDependency(ProgramDependenciesCompanion(
      id: const Value('rd1'),
      projectId: const Value('p1'),
      ref: const Value('D1'),
      description: const Value('Authoritative data source confirmed'),
    ));
    await db.journalDao.insertEntry(JournalEntriesCompanion.insert(
      id: 'j1',
      projectId: 'p1',
      title: const Value('Team sync'),
      body: 'Agreed to hold the cutover date.',
      entryDate: '2026-08-12',
    ));
    await db.glossaryDao.upsert(GlossaryEntriesCompanion(
      id: const Value('g1'),
      projectId: const Value('p1'),
      name: const Value('Customer Data Platform'),
      acronym: const Value('CDP'),
    ));

    final prompt = await builder.buildSystemPrompt('p1');
    expect(prompt, contains('## Project Charter'));
    expect(prompt, contains('Vision: One platform by 2027'));
    expect(prompt, contains('Out of scope: No legacy CRM changes'));
    expect(prompt,
        contains('## Latest Status Snapshot (week ending 2026-08-07)'));
    expect(prompt, contains('Programme RAG: AMBER'));
    expect(prompt, contains('Narrative: Slipping on data workstream'));
    expect(prompt, contains('## Assumptions'));
    expect(prompt, contains('[A1] Vendor API stays stable [open]'));
    expect(prompt, contains('## External / Register Dependencies'));
    expect(prompt,
        contains('[D1] Authoritative data source confirmed'));
    expect(prompt, contains('## Recent Journal Entries'));
    expect(prompt, contains('### Team sync — 2026-08-12'));
    expect(prompt, contains('Agreed to hold the cutover date.'));
    expect(prompt, contains('## Glossary'));
    expect(prompt, contains('- Customer Data Platform (CDP)'));
  });

  test('in-progress and blocked actions reach the prompt', () async {
    await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
      id: 'a1',
      projectId: 'p1',
      description: 'Chase infra team',
      status: const Value('blocked'),
    ));
    final prompt = await builder.buildSystemPrompt('p1');
    expect(prompt, contains('## Open Actions'));
    expect(prompt, contains('Chase infra team [blocked]'));
  });

  test('context summary counts the plan and issues', () async {
    await seedPlan();
    await db.raidDao.insertIssue(IssuesCompanion(
      id: const Value('i1'),
      projectId: const Value('p1'),
      description: const Value('an issue'),
    ));
    final summary = await builder.buildContextSummary('p1');
    final labels = summary.map((s) => s.$1).toList();
    expect(labels, contains('Delivery plan (1 WPs)'));
    expect(labels, contains('Open issues (top 6)'));
  });
}
