import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/planview_risk_import.dart';
import 'package:keel/core/raid/planview_risk_sheet.dart';

const _pid = 'p-pv';

PlanviewRiskRow _row(String ref, String title, String desc,
        {String steerco = 'programme', String? owner, String? due}) =>
    PlanviewRiskRow.fromCells([
      ref, steerco, title, desc, owner ?? 'Bart Fine', 'Paul Murray',
      'Likely', 'Major', 'Treat', 'Do the thing', 'Possible', 'Moderate',
      '4 Sep 26', due ?? '30 Sep 26', '9 Sep 26', '23 Sep 26',
      'Open. Note.', 'Strategic Delivery',
    ])!;

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.into(db.projects).insert(
        ProjectsCompanion.insert(id: _pid, name: 'Planview import'));
    // Same risk as sheet R19, older wording, with Keel-only fields set.
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('k19'),
      projectId: Value(_pid),
      ref: Value('R19'),
      description: Value('AWS enterprise connection delivers late March, '
          'leaving less than 2 weeks for production deployment'),
      likelihood: Value('possible'),
      impact: Value('major'),
      likelihoodRationale: Value('Keep me'),
      status: Value('in progress'),
      source: Value('journal'),
    ));
    // Different risk that happens to hold ref R21.
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('k21'),
      projectId: Value(_pid),
      ref: Value('R21'),
      description: Value('Internet connectivity setup (interim) could be '
          'delayed, blocking platform enablement and build work'),
    ));
    // Closed row not in the sheet: must be untouched.
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('k3'),
      projectId: Value(_pid),
      ref: Value('R3'),
      description: Value('Old closed risk'),
      status: Value('closed'),
    ));
  });

  tearDown(() => db.close());

  test('update keeps Keel-only fields, renumber frees the ref, create fills '
      'from the sheet', () async {
    final rows = [
      _row('R19', 'AWS connections land late',
          'Non-prod and prod Transit Gateway both land in March, compressing '
          'test and release into the run-up to SIT.',
          steerco: '▲ ESCALATE'),
      _row('R21', 'Stubs diverge from real endpoints',
          'Integrations built against stubs behave differently against real '
          'endpoints; gaps surface only in the E2E window.'),
      _row('R29', 'Deloitte squad idle on arrival',
          'Deloitte arrives before TAC-side prerequisites are ready.',
          due: '—'),
    ];
    final existing = await db.raidDao.getRisksForProject(_pid);
    final plan = planPlanviewImport(rows, existing);
    final result = await applyPlanviewImport(db,
        projectId: _pid, plan: plan, now: DateTime(2026, 9, 25));

    expect(result.updated, 1);
    expect(result.created, 2);
    expect(result.renumbered, 1);

    final r19 = (await db.raidDao.getRiskById('k19'))!;
    expect(r19.ref, 'R19');
    expect(r19.title, 'AWS connections land late');
    expect(r19.description, contains('Transit Gateway'));
    expect(r19.steerco, isTrue);
    expect(r19.likelihood, 'likely');
    expect(r19.impact, 'major');
    expect(r19.likelihoodTarget, 'possible');
    expect(r19.impactTarget, 'moderate');
    expect(r19.assignee, 'Paul Murray');
    expect(r19.dueDate, '2026-09-30');
    expect(r19.nextReviewAt, '2026-09-23');
    expect(r19.statusNote, 'Open. Note.');
    expect(r19.enterpriseRiskLink, 'Strategic Delivery');
    // Keel-only fields survive.
    expect(r19.likelihoodRationale, 'Keep me');
    expect(r19.status, 'in progress');
    expect(r19.source, 'journal');

    // The old R21 kept its content and moved to the next free number.
    final old21 = (await db.raidDao.getRiskById('k21'))!;
    expect(old21.ref, 'R30');
    expect(old21.description, contains('Internet connectivity'));

    final all = await db.raidDao.getRisksForProject(_pid);
    final new21 = all.singleWhere((r) => r.ref == 'R21');
    expect(new21.title, 'Stubs diverge from real endpoints');
    expect(new21.source, 'document');
    expect(new21.sourceNote, contains('Imported from Planview'));
    expect(new21.createdAt, DateTime(2026, 9, 4)); // raised on

    final new29 = all.singleWhere((r) => r.ref == 'R29');
    expect(new29.dueDate, isNull);

    // Untouched.
    final r3 = (await db.raidDao.getRiskById('k3'))!;
    expect(r3.status, 'closed');
    expect(r3.ref, 'R3');

    // No duplicate refs.
    final refs = all.map((r) => r.ref).toList();
    expect(refs.toSet().length, refs.length);
  });

  test('re-running the same sheet is idempotent', () async {
    final rows = [
      _row('R19', 'AWS connections land late',
          'Non-prod and prod Transit Gateway both land in March, compressing '
          'test and release into the run-up to SIT.'),
    ];
    for (var i = 0; i < 2; i++) {
      final existing = await db.raidDao.getRisksForProject(_pid);
      final plan = planPlanviewImport(rows, existing);
      await applyPlanviewImport(db, projectId: _pid, plan: plan);
    }
    final all = await db.raidDao.getRisksForProject(_pid);
    expect(all.where((r) => r.ref == 'R19'), hasLength(1));
    expect(all, hasLength(3));
  });
}
