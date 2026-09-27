import 'package:drift/drift.dart' show Value;
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

  test('cascaded copies and category merges ride in the blob', () async {
    await db.projectDao.upsertProject(ProjectsCompanion.insert(
        id: 'prog', name: 'Programme', kind: const Value('programme')));
    await db.financeDao.upsertCategoryRaw(const CostCategoriesCompanion(
      id: Value('cascade:cost_category:p1:c1'),
      projectId: Value('prog'),
      name: Value('People'),
      sourceProjectId: Value('p1'),
    ));
    await db.financeDao.upsertBudgetRaw(const ProjectBudgetsCompanion(
      id: Value('cascade:budget:p1:b1'),
      projectId: Value('prog'),
      name: Value('BC'),
      status: Value('approved'),
      sourceProjectId: Value('p1'),
    ));
    await db.financeDao.upsertLineRaw(const BudgetLinesCompanion(
      id: Value('cascade:budget_line:p1:l1'),
      projectId: Value('prog'),
      budgetId: Value('cascade:budget:p1:b1'),
      costCategoryId: Value('cascade:cost_category:p1:c1'),
      financialYear: Value('FY26'),
      amountMinor: Value(777),
      sourceProjectId: Value('p1'),
    ));
    await db.financeDao.mergeCategories(
        programmeId: 'prog',
        sourceCategoryIds: const ['cascade:cost_category:p1:c1'],
        targetName: 'Staff');

    final blob =
        await JsonExporter.exportProjectToString(projectId: 'prog', db: db);
    final other = AppDatabase.memory();
    addTearDown(other.close);
    await JsonImporter.importFromString(blob, other);

    expect(
        (await other.financeDao.getCascadedBudgets('prog')).single.sourceProjectId,
        'p1');
    expect(await other.financeDao.getBudgets('prog'), isEmpty);
    expect(
        (await other.financeDao.getCascadedBudgetLines('prog')).single.amountMinor,
        777);
    expect((await other.financeDao.getCascadedCategories('prog')).single.name,
        'People');
    expect((await other.financeDao.getMerges('prog')).single.targetName, 'Staff');

    // Importing the same blob again replaces rather than duplicates.
    await JsonImporter.importFromString(blob, other);
    expect(await other.financeDao.getCascadedBudgetLines('prog'), hasLength(1));
    expect(await other.financeDao.getCascadedBudgets('prog'), hasLength(1));
    expect(await other.financeDao.getMerges('prog'), hasLength(1));
  });
}
