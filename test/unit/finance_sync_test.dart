import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/import/json_importer.dart';

void main() {
  late AppDatabase db;
  const pid = 'p-fin';

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.upsertProject(ProjectsCompanion.insert(
      id: pid,
      name: 'Finance Sync Test',
    ));
  });
  tearDown(() async => db.close());

  Future<String> seedAndExport() async {
    await db.financeDao.seedDefaultCategories(pid, changedBy: 'Paul');
    final cats = await db.financeDao.getCategories(pid);
    final b1 = await db.financeDao.createBudget(
        projectId: pid,
        name: 'Approved Business Case v1',
        currency: 'AUD',
        fundingSource: 'Capex pool',
        changedBy: 'Paul');
    await db.financeDao.upsertLine(
      id: 'l1',
      projectId: pid,
      budgetId: b1,
      costCategoryId: cats[0].id,
      workstreamId: 'ws1',
      financialYear: 'FY26',
      amountMinor: 12000000,
      changedBy: 'Paul',
    );
    await db.financeDao.upsertLine(
      id: 'l2',
      projectId: pid,
      budgetId: b1,
      costCategoryId: cats[1].id,
      financialYear: 'FY27',
      amountMinor: 4550,
      notes: 'Vendor SOW',
      changedBy: 'Paul',
    );
    await db.financeDao.approveBudget(b1,
        approvedBy: 'Sponsor', changedBy: 'Paul');
    // v2: a submitted + a working forecast snapshot, and actuals.
    final s1 = await db.financeDao.createSnapshot(
        projectId: pid, period: '2026-06', copyFromBudget: true);
    await db.financeDao.submitSnapshot(s1, changedBy: 'Paul');
    await db.financeDao.createSnapshot(
        projectId: pid, period: '2026-07', copyFromSnapshotId: s1);
    await db.financeDao.upsertActualLine(
      id: 'a1',
      projectId: pid,
      period: '2026-06',
      costCategoryId: cats[0].id,
      amountMinor: 7700,
      notes: 'June payroll',
      changedBy: 'Paul',
    );
    return JsonExporter.exportProjectToString(projectId: pid, db: db);
  }

  test('export → clear → import round-trips every finance row', () async {
    final blob = await seedAndExport();
    final budgetsBefore = await db.financeDao.getBudgets(pid);
    final linesBefore = await db.financeDao.getLines(budgetsBefore.first.id);
    final auditBefore = await db.financeDao.getAuditLog(pid);

    await JsonImporter.importFromString(blob, db);

    final budgetsAfter = await db.financeDao.getBudgets(pid);
    expect(budgetsAfter.length, 1);
    final b = budgetsAfter.first;
    expect(b.name, 'Approved Business Case v1');
    expect(b.status, 'approved');
    expect(b.approvedBy, 'Sponsor');
    expect(b.currency, 'AUD');
    expect(b.fundingSource, 'Capex pool');

    final cats = await db.financeDao.getCategories(pid);
    expect(cats.map((c) => c.name).toList(),
        ['People', 'Vendor', 'Technology', 'Other', 'Contingency']);

    final linesAfter = await db.financeDao.getLines(b.id);
    expect(linesAfter.length, linesBefore.length);
    final l1 = linesAfter.firstWhere((l) => l.id == 'l1');
    expect(l1.amountMinor, 12000000);
    expect(l1.workstreamId, 'ws1');
    expect(l1.financialYear, 'FY26');
    final l2 = linesAfter.firstWhere((l) => l.id == 'l2');
    expect(l2.amountMinor, 4550);
    expect(l2.notes, 'Vendor SOW');

    // v2 tables round-trip: snapshots keep status, lines and actuals
    // land byte-for-byte.
    final snaps = await db.financeDao.getSnapshots(pid);
    expect(snaps.length, 2);
    final submitted = snaps.firstWhere((s) => s.period == '2026-06');
    expect(submitted.status, 'submitted');
    expect(submitted.submittedAt, isNotNull);
    final working = snaps.firstWhere((s) => s.period == '2026-07');
    expect(working.status, 'working');
    expect((await db.financeDao.getForecastTotals(working.id)).totalMinor,
        12004550);
    final actuals = await db.financeDao.getActuals(pid);
    expect(actuals.single.amountMinor, 7700);
    expect(actuals.single.notes, 'June payroll');
    expect(actuals.single.enteredBy, 'Paul');

    // Audit log rides in the blob: identical after import, not regrown.
    final auditAfter = await db.financeDao.getAuditLog(pid);
    expect(auditAfter.length, auditBefore.length);
    expect(auditAfter.map((a) => a.id).toSet(),
        auditBefore.map((a) => a.id).toSet());
    final approval = auditAfter.firstWhere(
        (a) => a.field == 'status' && a.newValue == 'approved');
    expect(approval.changedBy, 'Paul');
  });

  test('import reflects source-side deletions (clear-and-replace)', () async {
    final blob = await seedAndExport();
    // Local machine drifts: an extra draft that the source never had.
    await db.financeDao.createBudget(
        projectId: pid, name: 'Local-only draft', currency: 'AUD');
    expect((await db.financeDao.getBudgets(pid)).length, 2);

    await JsonImporter.importFromString(blob, db);

    final budgets = await db.financeDao.getBudgets(pid);
    expect(budgets.length, 1);
    expect(budgets.first.name, 'Approved Business Case v1');
  });

  test('pre-finance exports import cleanly (no finance key)', () async {
    // Simulate an old blob: current exporter output minus the finance key.
    final blob = await JsonExporter.exportProjectToString(
        projectId: pid, db: db);
    final stripped = blob.replaceFirst(RegExp(r'"finance": \{.*?\n  \},\n', dotAll: true), '');
    await JsonImporter.importFromString(stripped, db);
    expect(await db.financeDao.getBudgets(pid), isEmpty);
    expect(await db.financeDao.getCategories(pid), isEmpty);
  });
}
