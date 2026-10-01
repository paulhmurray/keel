import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/pdf_exporter.dart';
import 'package:keel/core/people/person_workload.dart';

/// A person's workload reconciles two ownership styles: FK ids on plan /
/// milestone rows and free-text owner names on the registers. Matching
/// is by id or by normalised name; nothing else in the project leaks in.
void main() {
  late AppDatabase db;
  late Person sam;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'proj', name: 'TAC'));
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'other', name: 'Other'));
    await db.peopleDao.insertPerson(const PersonsCompanion(
      id: Value('sam'),
      projectId: Value('proj'),
      name: Value('Sam Patel'),
      role: Value('Project Manager'),
      organisation: Value('Claims'),
    ));
    sam = (await db.peopleDao.getPersonsForProject('proj')).single;

    // Risk owned by exact name.
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r1'), projectId: Value('proj'), ref: Value('R1'),
      title: Value('Vendor slips'), description: Value('Vendor may slip'),
      owner: Value('Sam Patel'), dueDate: Value('2026-09-01'),
      mitigation: Value('Weekly checkpoint'),
    ));
    // Risk where Sam is the assignee, name spaced and cased differently.
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r2'), projectId: Value('proj'), ref: Value('R2'),
      description: Value('Data migration'), owner: Value('Someone Else'),
      assignee: Value('  sam   PATEL '), status: Value('accepted'),
    ));
    // Risk in another project with the same owner name — must not leak.
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r3'), projectId: Value('other'), ref: Value('R9'),
      description: Value('Foreign risk'), owner: Value('Sam Patel'),
    ));
    // Action owned by someone else.
    await db.actionsDao.upsertAction(const ProjectActionsCompanion(
      id: Value('a1'), projectId: Value('proj'), ref: Value('A1'),
      description: Value('Not Sam'), owner: Value('Jo Bloggs'),
    ));
    // Action owned by Sam, open, due in the future.
    await db.actionsDao.upsertAction(const ProjectActionsCompanion(
      id: Value('a2'), projectId: Value('proj'), ref: Value('A2'),
      description: Value('Confirm interface spec'), owner: Value('Sam Patel'),
      dueDate: Value('2026-12-01'),
    ));
    // Dependency Sam chases on our side.
    await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
      id: Value('d1'), projectId: Value('proj'), ref: Value('D1'),
      description: Value('Claims API ready'), owner: Value('sam patel'),
      counterparty: Value('Claims platform'), dueDate: Value('2026-11-15'),
    ));
    // Milestone by FK.
    await db.milestonesDao.upsert(const MilestonesCompanion(
      id: Value('m1'), projectId: Value('proj'), name: Value('Go-live'),
      date: Value('2027-01-10'), ownerId: Value('sam'),
    ));
    // Plan activities: one owned by FK, one by name, one contributed to.
    await db.programmeGanttDao
        .upsertWorkPackage(const TimelineWorkPackagesCompanion(
      id: Value('wp1'), projectId: Value('proj'), name: Value('Build'),
      sortOrder: Value(0),
    ));
    await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('t1'), workPackageId: Value('wp1'), projectId: Value('proj'),
      name: Value('Owned by id'), ownerId: Value('sam'), sortOrder: Value(0),
    ));
    await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('t2'), workPackageId: Value('wp1'), projectId: Value('proj'),
      name: Value('Owned by name'), owner: Value('SAM PATEL'),
      sortOrder: Value(1),
    ));
    await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('t3'), workPackageId: Value('wp1'), projectId: Value('proj'),
      name: Value('Helping out'), owner: Value('Jo Bloggs'),
      contributorIds: Value('["x","sam"]'), sortOrder: Value(2),
    ));
    // Decision Sam makes.
    await db.decisionsDao.upsertDecision(const DecisionsCompanion(
      id: Value('dc1'), projectId: Value('proj'), ref: Value('DC1'),
      description: Value('Pick the vendor'), decisionMaker: Value('Sam Patel'),
      status: Value('decided'),
    ));
  });
  tearDown(() => db.close());

  test('name matching is trimmed, case-folded and whitespace-collapsed', () {
    expect(PersonWorkload.normaliseName('  Sam   PATEL '), 'sam patel');
    expect(PersonWorkload.nameMatches(sam, 'sam patel'), isTrue);
    expect(PersonWorkload.nameMatches(sam, 'Sam'), isFalse);
    expect(PersonWorkload.nameMatches(sam, null), isFalse);
  });

  test('contributor ids parse from JSON and tolerate garbage', () {
    expect(PersonWorkload.contributorIdsOf(_activity('["a","b"]')), ['a', 'b']);
    expect(PersonWorkload.contributorIdsOf(_activity(null)), isEmpty);
    expect(PersonWorkload.contributorIdsOf(_activity('not json')), isEmpty);
  });

  test('load gathers every register by id or name, scoped to the project',
      () async {
    final w = await PersonWorkload.load(db, sam);

    expect(w[WorkloadKind.risk].map((i) => i.id), ['r1', 'r2']);
    expect(w[WorkloadKind.risk].first.role, WorkloadRole.owner);
    expect(w[WorkloadKind.risk].first.detail, 'Mitigation: Weekly checkpoint');
    expect(w[WorkloadKind.risk].last.role, WorkloadRole.assignee);
    expect(w[WorkloadKind.risk].last.isClosed, isTrue,
        reason: 'accepted is terminal for a risk');

    expect(w[WorkloadKind.action].map((i) => i.id), ['a2']);
    expect(w[WorkloadKind.dependency].single.qualifier,
        'Inbound with Claims platform');
    expect(w[WorkloadKind.milestone].single.dueDate, '2027-01-10');
    expect(w[WorkloadKind.planActivity].map((i) => i.id), ['t1', 't2']);
    expect(w[WorkloadKind.contribution].single.id, 't3');
    expect(w[WorkloadKind.contribution].single.role, WorkloadRole.contributor);
    expect(w[WorkloadKind.decision].single.isClosed, isTrue);
    expect(w[WorkloadKind.issue], isEmpty);
    expect(w.all.map((i) => i.id), isNot(contains('r3')));
  });

  test('buckets split overdue / open / closed against a given day', () async {
    final w = await PersonWorkload.load(db, sam);
    final b = w.buckets(WorkloadKind.risk, '2026-09-30');
    expect(b.overdue.map((i) => i.id), ['r1']);
    expect(b.open, isEmpty);
    expect(b.closed.map((i) => i.id), ['r2']);
    expect(w.overdueCount('2026-09-30'), 1);
    expect(w.openCount, 7);
    expect(w.populatedKinds.first, WorkloadKind.risk);
    expect(w.populatedKinds, isNot(contains(WorkloadKind.issue)));
  });

  test('an unrelated person has an empty workload', () async {
    await db.peopleDao.insertPerson(const PersonsCompanion(
      id: Value('nobody'), projectId: Value('proj'), name: Value('Nobody'),
    ));
    final nobody = (await db.peopleDao.getPersonsForProject('proj'))
        .firstWhere((p) => p.id == 'nobody');
    final w = await PersonWorkload.load(db, nobody);
    expect(w.isEmpty, isTrue);
    expect(w.populatedKinds, isEmpty);
  });

  test('the brief PDF renders with and without closed items', () async {
    final w = await PersonWorkload.load(db, sam);
    final open = await PdfExporter.buildPersonBriefBytes(
      workload: w,
      projectName: 'TAC',
      preparedBy: 'Paul',
      now: DateTime(2026, 9, 30),
    );
    final withClosed = await PdfExporter.buildPersonBriefBytes(
      workload: w,
      projectName: 'TAC',
      includeClosed: true,
      now: DateTime(2026, 9, 30),
    );
    expect(open, isNotEmpty);
    expect(withClosed.length, greaterThan(open.length),
        reason: 'closed rows add content');

    final empty = PersonWorkload.build(person: sam);
    expect(
        await PdfExporter.buildPersonBriefBytes(
            workload: empty, projectName: 'TAC'),
        isNotEmpty);
  });
}

TimelineActivity _activity(String? contributorIds) => TimelineActivity(
      id: 'x',
      workPackageId: 'wp',
      projectId: 'proj',
      name: 'x',
      activityType: 'activity',
      status: 'not_started',
      isCritical: false,
      isBaseline: false,
      sortOrder: 0,
      contributorIds: contributorIds,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
