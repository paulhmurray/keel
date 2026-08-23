import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/finance/budget_grid.dart';

/// Drift's watch streams keep scheduling timers, so pumpAndSettle never
/// settles — same as the canvas widget tests, we use fixed pumps and
/// unmount inside the test body so Drift's deferred stream-close timers
/// fire BEFORE the framework's pending-timer check.
Future<void> runGridTest(
  WidgetTester tester,
  Widget grid,
  Future<void> Function() body,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 900);
  await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: grid)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  try {
    await body();
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  late AppDatabase db;
  const pid = 'p1';
  late ProjectBudget budget;
  late List<CostCategory> categories;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.upsertProject(
        ProjectsCompanion.insert(id: pid, name: 'Grid Test'));
    await db.financeDao.seedDefaultCategories(pid);
    categories = await db.financeDao.getCategories(pid);
    final id = await db.financeDao.createBudget(
        projectId: pid, name: 'Draft', currency: 'GBP');
    budget = (await db.financeDao.getBudgetById(id))!;
  });
  tearDown(() async => db.close());

  Widget grid({bool readOnly = false}) => BudgetGrid(
        db: db,
        projectId: pid,
        budget: budget,
        categories: categories,
        workPackages: const [],
        actor: 'Tester',
        readOnly: readOnly,
      );

  Future<void> seedLine(String catId, int amountMinor) =>
      db.financeDao.upsertLine(
        id: 'l1',
        projectId: pid,
        budgetId: budget.id,
        costCategoryId: catId,
        financialYear: 'FY27',
        amountMinor: amountMinor,
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('typing 120k into a cell commits £120,000 to the line',
      (tester) async {
    final cat = categories.first;
    await seedLine(cat.id, 100);
    await runGridTest(tester, grid(), () async {
      await tester.tap(find.byKey(ValueKey('cell-${cat.id}||FY27')));
      await settle(tester);
      await tester.enterText(
          find.byKey(ValueKey('edit-${cat.id}||FY27')), '120k');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      final lines = await db.financeDao.getLines(budget.id);
      expect(lines.single.amountMinor, 12000000);
    });
  });

  testWidgets('committing a pristine editor writes nothing (no-op nav)',
      (tester) async {
    final cat = categories.first;
    await seedLine(cat.id, 5500);
    final auditBefore = (await db.financeDao.getAuditLog(pid)).length;
    await runGridTest(tester, grid(), () async {
      await tester.tap(find.byKey(ValueKey('cell-${cat.id}||FY27')));
      await settle(tester);
      // Enter without typing — must not delete or rewrite the line.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      final lines = await db.financeDao.getLines(budget.id);
      expect(lines.single.amountMinor, 5500);
      expect((await db.financeDao.getAuditLog(pid)).length, auditBefore);
    });
  });

  testWidgets('clearing a cell deletes its line', (tester) async {
    final cat = categories.first;
    await seedLine(cat.id, 5500);
    await runGridTest(tester, grid(), () async {
      await tester.tap(find.byKey(ValueKey('cell-${cat.id}||FY27')));
      await settle(tester);
      final editField = find.byKey(ValueKey('edit-${cat.id}||FY27'));
      await tester.enterText(editField, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(await db.financeDao.getLines(budget.id), isEmpty);
    });
  });

  testWidgets('read-only grid has no editable cells', (tester) async {
    final cat = categories.first;
    await seedLine(cat.id, 12000000);
    await runGridTest(tester, grid(readOnly: true), () async {
      await tester.tap(find.byKey(ValueKey('cell-${cat.id}||FY27')));
      await settle(tester);
      expect(find.byType(TextField), findsNothing);
      // Amount renders plain (symbol-free cells; totals carry the symbol).
      expect(find.text('120,000'), findsOneWidget);
    });
  });

  testWidgets('invalid input flags the cell and does not commit',
      (tester) async {
    final cat = categories.first;
    await seedLine(cat.id, 5500);
    await runGridTest(tester, grid(), () async {
      await tester.tap(find.byKey(ValueKey('cell-${cat.id}||FY27')));
      await settle(tester);
      await tester.enterText(
          find.byKey(ValueKey('edit-${cat.id}||FY27')), 'not-money');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      // Editor stays open (invalid), line untouched.
      expect(find.byType(TextField), findsOneWidget);
      final lines = await db.financeDao.getLines(budget.id);
      expect(lines.single.amountMinor, 5500);
    });
  });
}
