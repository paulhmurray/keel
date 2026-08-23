import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';

void main() {
  late AppDatabase db;
  const pid = 'p1';

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.upsertProject(ProjectsCompanion.insert(
      id: pid,
      name: 'Finance Test',
    ));
  });
  tearDown(() async => db.close());

  Future<String> firstCategoryId() async =>
      (await db.financeDao.getCategories(pid)).first.id;

  group('FinanceDao — categories', () {
    test('seedDefaultCategories seeds once, idempotently', () async {
      await db.financeDao.seedDefaultCategories(pid);
      await db.financeDao.seedDefaultCategories(pid);
      final cats = await db.financeDao.getCategories(pid);
      expect(cats.map((c) => c.name).toList(),
          ['People', 'Vendor', 'Technology', 'Other', 'Contingency']);
    });

    test('rename audits old and new value', () async {
      await db.financeDao.seedDefaultCategories(pid);
      final id = await firstCategoryId();
      await db.financeDao.renameCategory(id, 'Staff', changedBy: 'Paul');
      final log = await db.financeDao.getAuditLog(pid);
      final entry = log.firstWhere((e) => e.field == 'name');
      expect(entry.oldValue, 'People');
      expect(entry.newValue, 'Staff');
      expect(entry.changedBy, 'Paul');
    });

    test('delete blocked while a budget line references it', () async {
      await db.financeDao.seedDefaultCategories(pid);
      final catId = await firstCategoryId();
      final budgetId = await db.financeDao
          .createBudget(projectId: pid, name: 'FY26 Budget', currency: 'AUD');
      await db.financeDao.upsertLine(
        id: 'l1',
        projectId: pid,
        budgetId: budgetId,
        costCategoryId: catId,
        financialYear: 'FY26',
        amountMinor: 100000,
      );
      expect(await db.financeDao.deleteCategory(catId), isFalse);
      await db.financeDao.deleteLine('l1');
      expect(await db.financeDao.deleteCategory(catId), isTrue);
    });
  });

  group('FinanceDao — budget lifecycle', () {
    test('create → approve supersedes previous approved', () async {
      final b1 = await db.financeDao
          .createBudget(projectId: pid, name: 'v1', currency: 'AUD');
      await db.financeDao.approveBudget(b1, approvedBy: 'Sponsor');
      final b2 = await db.financeDao
          .createBudget(projectId: pid, name: 'v2', currency: 'AUD');
      await db.financeDao.approveBudget(b2, approvedBy: 'Sponsor');

      final approved = await db.financeDao.getApprovedBudget(pid);
      expect(approved!.id, b2);
      expect((await db.financeDao.getBudgetById(b1))!.status, 'superseded');
      // Exactly one approved budget at any time.
      final all = await db.financeDao.getBudgets(pid);
      expect(all.where((b) => b.status == 'approved').length, 1);
    });

    test('approving a non-draft throws', () async {
      final b1 = await db.financeDao
          .createBudget(projectId: pid, name: 'v1', currency: 'AUD');
      await db.financeDao.approveBudget(b1);
      expect(() => db.financeDao.approveBudget(b1), throwsStateError);
    });

    test('approved budgets reject line edits and deletion', () async {
      await db.financeDao.seedDefaultCategories(pid);
      final catId = await firstCategoryId();
      final b1 = await db.financeDao
          .createBudget(projectId: pid, name: 'v1', currency: 'AUD');
      await db.financeDao.upsertLine(
        id: 'l1',
        projectId: pid,
        budgetId: b1,
        costCategoryId: catId,
        financialYear: 'FY26',
        amountMinor: 100000,
      );
      await db.financeDao.approveBudget(b1);
      expect(
          () => db.financeDao.upsertLine(
                id: 'l2',
                projectId: pid,
                budgetId: b1,
                costCategoryId: catId,
                financialYear: 'FY26',
                amountMinor: 5,
              ),
          throwsStateError);
      expect(() => db.financeDao.deleteLine('l1'), throwsStateError);
      expect(() => db.financeDao.deleteDraftBudget(b1), throwsStateError);
    });

    test('createDraftFrom copies every line to a new draft', () async {
      await db.financeDao.seedDefaultCategories(pid);
      final cats = await db.financeDao.getCategories(pid);
      final b1 = await db.financeDao
          .createBudget(projectId: pid, name: 'v1', currency: 'GBP');
      for (var i = 0; i < 3; i++) {
        await db.financeDao.upsertLine(
          id: 'l$i',
          projectId: pid,
          budgetId: b1,
          costCategoryId: cats[i].id,
          financialYear: 'FY2${6 + i}',
          amountMinor: (i + 1) * 1000,
        );
      }
      await db.financeDao.approveBudget(b1);
      final b2 = await db.financeDao.createDraftFrom(b1, name: 'v2');

      final draft = (await db.financeDao.getBudgetById(b2))!;
      expect(draft.status, 'draft');
      expect(draft.currency, 'GBP');
      final copied = await db.financeDao.getLines(b2);
      expect(copied.length, 3);
      expect(copied.map((l) => l.amountMinor).toList()..sort(),
          [1000, 2000, 3000]);
      // Source untouched.
      expect((await db.financeDao.getLines(b1)).length, 3);
    });
  });

  group('FinanceDao — audit trail', () {
    test('every mutation writes audit entries', () async {
      await db.financeDao.seedDefaultCategories(pid);
      final catId = await firstCategoryId();
      final b1 = await db.financeDao.createBudget(
          projectId: pid, name: 'v1', currency: 'AUD', changedBy: 'Paul');
      await db.financeDao.upsertLine(
        id: 'l1',
        projectId: pid,
        budgetId: b1,
        costCategoryId: catId,
        financialYear: 'FY26',
        amountMinor: 100000,
        changedBy: 'Paul',
      );
      await db.financeDao.upsertLine(
        id: 'l1',
        projectId: pid,
        budgetId: b1,
        costCategoryId: catId,
        financialYear: 'FY26',
        amountMinor: 250000,
        changedBy: 'Paul',
      );
      await db.financeDao.approveBudget(b1, changedBy: 'Paul');

      final log = await db.financeDao.getAuditLog(pid);
      // 5 category seeds + budget created + line created + line amount
      // change + budget approved.
      expect(log.length, 9);
      final amountChange = log.firstWhere(
          (e) => e.entityType == 'BudgetLine' && e.field == 'amountMinor');
      expect(amountChange.oldValue, '100000');
      expect(amountChange.newValue, '250000');
      final approval = log.firstWhere(
          (e) => e.entityType == 'ProjectBudget' && e.field == 'status');
      expect(approval.oldValue, 'draft');
      expect(approval.newValue, 'approved');
    });

    test('unchanged line upsert writes no audit entry', () async {
      await db.financeDao.seedDefaultCategories(pid);
      final catId = await firstCategoryId();
      final b1 = await db.financeDao
          .createBudget(projectId: pid, name: 'v1', currency: 'AUD');
      await db.financeDao.upsertLine(
        id: 'l1',
        projectId: pid,
        budgetId: b1,
        costCategoryId: catId,
        financialYear: 'FY26',
        amountMinor: 100000,
      );
      final before = (await db.financeDao.getAuditLog(pid)).length;
      await db.financeDao.upsertLine(
        id: 'l1',
        projectId: pid,
        budgetId: b1,
        costCategoryId: catId,
        financialYear: 'FY26',
        amountMinor: 100000,
      );
      expect((await db.financeDao.getAuditLog(pid)).length, before);
    });
  });

  group('BudgetTotals', () {
    test('integer sums by category, FY, and workstream are exact', () async {
      await db.financeDao.seedDefaultCategories(pid);
      final cats = await db.financeDao.getCategories(pid);
      final b1 = await db.financeDao
          .createBudget(projectId: pid, name: 'v1', currency: 'AUD');
      // Amounts chosen to expose float error if any crept in (0.1+0.2).
      final amounts = [10, 20, 30, 1000001, 999999];
      for (var i = 0; i < amounts.length; i++) {
        await db.financeDao.upsertLine(
          id: 'l$i',
          projectId: pid,
          budgetId: b1,
          costCategoryId: cats[i % 2].id,
          workstreamId: i.isEven ? 'ws1' : null,
          financialYear: i < 3 ? 'FY26' : 'FY27',
          amountMinor: amounts[i],
        );
      }
      final totals = await db.financeDao.getTotals(b1);
      expect(totals.totalMinor, 2000060);
      expect(totals.byFinancialYear['FY26'], 60);
      expect(totals.byFinancialYear['FY27'], 2000000);
      expect(totals.byCategoryId[cats[0].id], 10 + 30 + 999999);
      expect(totals.byCategoryId[cats[1].id], 20 + 1000001);
      expect(totals.byWorkstreamId['ws1'], 10 + 30 + 999999);
      expect(totals.byWorkstreamId[''], 20 + 1000001);
      // Grand total equals the sum of every breakdown, exactly.
      expect(totals.byFinancialYear.values.reduce((a, b) => a + b),
          totals.totalMinor);
      expect(totals.byCategoryId.values.reduce((a, b) => a + b),
          totals.totalMinor);
    });
  });
}
