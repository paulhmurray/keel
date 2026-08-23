part of '../database.dart';

/// Default cost categories seeded per project on first use of Finance.
const kDefaultCostCategories = [
  'People',
  'Vendor',
  'Technology',
  'Other',
  'Contingency',
];

/// Pure integer rollups over a budget's lines. All sums are exact —
/// there are no divisions or percentages in v1, so "matches Excel to
/// the cent" reduces to: totals equal the sum of lines, always.
class BudgetTotals {
  final int totalMinor;
  final Map<String, int> byCategoryId;
  final Map<String, int> byFinancialYear;
  final Map<String, int> byWorkstreamId; // key '' = unassigned

  BudgetTotals._(this.totalMinor, this.byCategoryId, this.byFinancialYear,
      this.byWorkstreamId);

  factory BudgetTotals.fromLines(List<BudgetLine> lines) {
    return BudgetTotals._sum(lines.map(
        (l) => (l.costCategoryId, l.workstreamId, l.financialYear, l.amountMinor)));
  }

  factory BudgetTotals.fromForecastLines(List<ForecastLine> lines) {
    return BudgetTotals._sum(lines.map(
        (l) => (l.costCategoryId, l.workstreamId, l.financialYear, l.amountMinor)));
  }

  /// Actuals are keyed by calendar period, not FY — for actuals the
  /// [byFinancialYear] map is keyed by period ('YYYY-MM').
  factory BudgetTotals.fromActualLines(List<ActualLine> lines) {
    return BudgetTotals._sum(lines
        .map((l) => (l.costCategoryId, l.workstreamId, l.period, l.amountMinor)));
  }

  factory BudgetTotals._sum(
      Iterable<(String, String?, String, int)> cells) {
    var total = 0;
    final byCat = <String, int>{};
    final byKey = <String, int>{};
    final byWs = <String, int>{};
    for (final (cat, ws, key, minor) in cells) {
      total += minor;
      byCat[cat] = (byCat[cat] ?? 0) + minor;
      byKey[key] = (byKey[key] ?? 0) + minor;
      byWs[ws ?? ''] = (byWs[ws ?? ''] ?? 0) + minor;
    }
    return BudgetTotals._(total, byCat, byKey, byWs);
  }
}

/// Finance data access. Every mutating method writes its own
/// [FinancialAuditLog] entries inside the same transaction as the
/// change — auditing is a DAO responsibility, so no write path can
/// skip it. The `*Raw` upserts exist ONLY for the sync importer, which
/// carries the source machine's audit log in the payload and must not
/// generate fresh entries.
@DriftAccessor(tables: [
  CostCategories,
  ProjectBudgets,
  BudgetLines,
  ForecastSnapshots,
  ForecastLines,
  ActualLines,
  FinancialAuditLog,
])
class FinanceDao extends DatabaseAccessor<AppDatabase>
    with _$FinanceDaoMixin {
  FinanceDao(super.db);

  static const _uuid = Uuid();

  // ── Audit ─────────────────────────────────────────────────────────────

  Future<void> _audit({
    required String projectId,
    required String entityType,
    required String entityId,
    required String field,
    String? oldValue,
    String? newValue,
    String? changedBy,
  }) {
    return into(financialAuditLog).insert(FinancialAuditLogCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      entityType: entityType,
      entityId: entityId,
      field: field,
      oldValue: Value(oldValue),
      newValue: Value(newValue),
      changedBy: Value(changedBy),
    ));
  }

  Stream<List<FinancialAuditLogData>> watchAuditLog(String projectId) {
    return (select(financialAuditLog)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.changedAt)]))
        .watch();
  }

  Future<List<FinancialAuditLogData>> getAuditLog(String projectId) {
    return (select(financialAuditLog)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.changedAt)]))
        .get();
  }

  // ── Cost categories ───────────────────────────────────────────────────

  Stream<List<CostCategory>> watchCategories(String projectId) {
    return (select(costCategories)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<List<CostCategory>> getCategories(String projectId) {
    return (select(costCategories)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// Seeds the default categories if the project has none. Idempotent.
  Future<void> seedDefaultCategories(String projectId, {String? changedBy}) {
    return transaction(() async {
      final existing = await getCategories(projectId);
      if (existing.isNotEmpty) return;
      for (var i = 0; i < kDefaultCostCategories.length; i++) {
        final id = _uuid.v4();
        await into(costCategories).insert(CostCategoriesCompanion.insert(
          id: id,
          projectId: projectId,
          name: kDefaultCostCategories[i],
          sortOrder: Value(i),
        ));
        await _audit(
          projectId: projectId,
          entityType: 'CostCategory',
          entityId: id,
          field: 'created',
          newValue: kDefaultCostCategories[i],
          changedBy: changedBy,
        );
      }
    });
  }

  Future<void> createCategory({
    required String projectId,
    required String name,
    int sortOrder = 0,
    String? changedBy,
  }) {
    return transaction(() async {
      final id = _uuid.v4();
      await into(costCategories).insert(CostCategoriesCompanion.insert(
        id: id,
        projectId: projectId,
        name: name,
        sortOrder: Value(sortOrder),
      ));
      await _audit(
        projectId: projectId,
        entityType: 'CostCategory',
        entityId: id,
        field: 'created',
        newValue: name,
        changedBy: changedBy,
      );
    });
  }

  Future<void> renameCategory(String id, String name, {String? changedBy}) {
    return transaction(() async {
      final row = await (select(costCategories)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      if (row.name == name) return;
      await (update(costCategories)..where((t) => t.id.equals(id))).write(
        CostCategoriesCompanion(
          name: Value(name),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _audit(
        projectId: row.projectId,
        entityType: 'CostCategory',
        entityId: id,
        field: 'name',
        oldValue: row.name,
        newValue: name,
        changedBy: changedBy,
      );
    });
  }

  /// Deletes a category. Returns false (and deletes nothing) if any
  /// budget line references it.
  Future<bool> deleteCategory(String id, {String? changedBy}) {
    return transaction(() async {
      final inUse = await (select(budgetLines)
            ..where((t) => t.costCategoryId.equals(id))
            ..limit(1))
          .get();
      if (inUse.isNotEmpty) return false;
      final row = await (select(costCategories)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return false;
      await (delete(costCategories)..where((t) => t.id.equals(id))).go();
      await _audit(
        projectId: row.projectId,
        entityType: 'CostCategory',
        entityId: id,
        field: 'deleted',
        oldValue: row.name,
        changedBy: changedBy,
      );
      return true;
    });
  }

  // ── Budgets ───────────────────────────────────────────────────────────

  Stream<List<ProjectBudget>> watchBudgets(String projectId) {
    return (select(projectBudgets)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<ProjectBudget>> getBudgets(String projectId) {
    return (select(projectBudgets)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<ProjectBudget?> getBudgetById(String id) {
    return (select(projectBudgets)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<ProjectBudget?> getApprovedBudget(String projectId) {
    return (select(projectBudgets)
          ..where((t) =>
              t.projectId.equals(projectId) & t.status.equals('approved')))
        .getSingleOrNull();
  }

  Future<String> createBudget({
    required String projectId,
    required String name,
    required String currency,
    String? fundingSource,
    String? notes,
    String? changedBy,
  }) {
    return transaction(() async {
      final id = _uuid.v4();
      await into(projectBudgets).insert(ProjectBudgetsCompanion.insert(
        id: id,
        projectId: projectId,
        name: name,
        currency: Value(currency),
        fundingSource: Value(fundingSource),
        notes: Value(notes),
      ));
      await _audit(
        projectId: projectId,
        entityType: 'ProjectBudget',
        entityId: id,
        field: 'created',
        newValue: name,
        changedBy: changedBy,
      );
      return id;
    });
  }

  /// Creates a new draft budget copying every line of [sourceBudgetId].
  /// This is the "new version" flow — the source stays untouched.
  Future<String> createDraftFrom(String sourceBudgetId,
      {String? name, String? changedBy}) {
    return transaction(() async {
      final source = await getBudgetById(sourceBudgetId);
      if (source == null) {
        throw StateError('Source budget not found: $sourceBudgetId');
      }
      final id = await createBudget(
        projectId: source.projectId,
        name: name ?? '${source.name} (draft)',
        currency: source.currency,
        fundingSource: source.fundingSource,
        notes: source.notes,
        changedBy: changedBy,
      );
      final lines = await getLines(sourceBudgetId);
      for (final l in lines) {
        await upsertLine(
          id: _uuid.v4(),
          projectId: l.projectId,
          budgetId: id,
          costCategoryId: l.costCategoryId,
          workstreamId: l.workstreamId,
          financialYear: l.financialYear,
          amountMinor: l.amountMinor,
          notes: l.notes,
          changedBy: changedBy,
        );
      }
      return id;
    });
  }

  /// Edits draft budget metadata. Throws [StateError] on non-drafts.
  Future<void> updateDraftBudget({
    required String id,
    String? name,
    String? currency,
    String? fundingSource,
    String? notes,
    String? changedBy,
  }) {
    return transaction(() async {
      final row = await getBudgetById(id);
      if (row == null) throw StateError('Budget not found: $id');
      if (row.status != 'draft') {
        throw StateError('Only draft budgets can be edited');
      }
      await (update(projectBudgets)..where((t) => t.id.equals(id))).write(
        ProjectBudgetsCompanion(
          name: name != null ? Value(name) : const Value.absent(),
          currency: currency != null ? Value(currency) : const Value.absent(),
          fundingSource: fundingSource != null
              ? Value(fundingSource)
              : const Value.absent(),
          notes: notes != null ? Value(notes) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
      Future<void> auditField(String field, String? oldV, String? newV) {
        if (newV == null || oldV == newV) return Future.value();
        return _audit(
          projectId: row.projectId,
          entityType: 'ProjectBudget',
          entityId: id,
          field: field,
          oldValue: oldV,
          newValue: newV,
          changedBy: changedBy,
        );
      }

      await auditField('name', row.name, name);
      await auditField('currency', row.currency, currency);
      await auditField('fundingSource', row.fundingSource, fundingSource);
      await auditField('notes', row.notes, notes);
    });
  }

  /// Approves a draft budget, superseding any currently-approved budget
  /// for the same project in the same transaction.
  Future<void> approveBudget(String id,
      {String? approvedBy, String? changedBy}) {
    return transaction(() async {
      final row = await getBudgetById(id);
      if (row == null) throw StateError('Budget not found: $id');
      if (row.status != 'draft') {
        throw StateError('Only draft budgets can be approved');
      }
      final current = await getApprovedBudget(row.projectId);
      if (current != null) {
        await (update(projectBudgets)
              ..where((t) => t.id.equals(current.id)))
            .write(ProjectBudgetsCompanion(
          status: const Value('superseded'),
          updatedAt: Value(DateTime.now()),
        ));
        await _audit(
          projectId: row.projectId,
          entityType: 'ProjectBudget',
          entityId: current.id,
          field: 'status',
          oldValue: 'approved',
          newValue: 'superseded',
          changedBy: changedBy,
        );
      }
      await (update(projectBudgets)..where((t) => t.id.equals(id))).write(
        ProjectBudgetsCompanion(
          status: const Value('approved'),
          approvedBy: Value(approvedBy),
          approvedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _audit(
        projectId: row.projectId,
        entityType: 'ProjectBudget',
        entityId: id,
        field: 'status',
        oldValue: 'draft',
        newValue: 'approved',
        changedBy: changedBy,
      );
    });
  }

  /// Deletes a DRAFT budget and its lines. Throws on non-drafts —
  /// approved/superseded budgets are history and never deleted.
  Future<void> deleteDraftBudget(String id, {String? changedBy}) {
    return transaction(() async {
      final row = await getBudgetById(id);
      if (row == null) return;
      if (row.status != 'draft') {
        throw StateError('Only draft budgets can be deleted');
      }
      await (delete(budgetLines)..where((t) => t.budgetId.equals(id))).go();
      await (delete(projectBudgets)..where((t) => t.id.equals(id))).go();
      await _audit(
        projectId: row.projectId,
        entityType: 'ProjectBudget',
        entityId: id,
        field: 'deleted',
        oldValue: row.name,
        changedBy: changedBy,
      );
    });
  }

  // ── Budget lines ──────────────────────────────────────────────────────

  Stream<List<BudgetLine>> watchLines(String budgetId) {
    return (select(budgetLines)
          ..where((t) => t.budgetId.equals(budgetId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<List<BudgetLine>> getLines(String budgetId) {
    return (select(budgetLines)
          ..where((t) => t.budgetId.equals(budgetId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<BudgetTotals> getTotals(String budgetId) async {
    return BudgetTotals.fromLines(await getLines(budgetId));
  }

  /// Inserts or updates a line on a DRAFT budget. Throws [StateError]
  /// when the parent budget is approved/superseded.
  Future<void> upsertLine({
    required String id,
    required String projectId,
    required String budgetId,
    required String costCategoryId,
    String? workstreamId,
    required String financialYear,
    required int amountMinor,
    String? notes,
    String? changedBy,
  }) {
    return transaction(() async {
      final budget = await getBudgetById(budgetId);
      if (budget == null) throw StateError('Budget not found: $budgetId');
      if (budget.status != 'draft') {
        throw StateError('Lines can only be edited on draft budgets');
      }
      final existing = await (select(budgetLines)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      await into(budgetLines).insertOnConflictUpdate(BudgetLinesCompanion(
        id: Value(id),
        projectId: Value(projectId),
        budgetId: Value(budgetId),
        costCategoryId: Value(costCategoryId),
        workstreamId: Value(workstreamId),
        financialYear: Value(financialYear),
        amountMinor: Value(amountMinor),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
      ));
      if (existing == null) {
        await _audit(
          projectId: projectId,
          entityType: 'BudgetLine',
          entityId: id,
          field: 'created',
          newValue: '$amountMinor',
          changedBy: changedBy,
        );
      } else if (existing.amountMinor != amountMinor) {
        await _audit(
          projectId: projectId,
          entityType: 'BudgetLine',
          entityId: id,
          field: 'amountMinor',
          oldValue: '${existing.amountMinor}',
          newValue: '$amountMinor',
          changedBy: changedBy,
        );
      }
    });
  }

  Future<void> deleteLine(String id, {String? changedBy}) {
    return transaction(() async {
      final row = await (select(budgetLines)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return;
      final budget = await getBudgetById(row.budgetId);
      if (budget != null && budget.status != 'draft') {
        throw StateError('Lines can only be deleted on draft budgets');
      }
      await (delete(budgetLines)..where((t) => t.id.equals(id))).go();
      await _audit(
        projectId: row.projectId,
        entityType: 'BudgetLine',
        entityId: id,
        field: 'deleted',
        oldValue: '${row.amountMinor}',
        changedBy: changedBy,
      );
    });
  }

  // ── Forecast snapshots (v2) ──────────────────────────────────────────

  Stream<List<ForecastSnapshot>> watchSnapshots(String projectId) {
    return (select(forecastSnapshots)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.period)]))
        .watch();
  }

  Future<List<ForecastSnapshot>> getSnapshots(String projectId) {
    return (select(forecastSnapshots)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.period)]))
        .get();
  }

  Future<ForecastSnapshot?> getSnapshotById(String id) {
    return (select(forecastSnapshots)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<ForecastSnapshot?> getSnapshotForPeriod(
      String projectId, String period) {
    return (select(forecastSnapshots)
          ..where((t) =>
              t.projectId.equals(projectId) & t.period.equals(period)))
        .getSingleOrNull();
  }

  /// Creates the working snapshot for [period], optionally pre-filled
  /// from the approved budget or another snapshot. One snapshot per
  /// (project, period). The copied lines are NOT individually audited —
  /// the snapshot-created entry marks the copy; subsequent edits audit
  /// normally.
  Future<String> createSnapshot({
    required String projectId,
    required String period,
    bool copyFromBudget = false,
    String? copyFromSnapshotId,
    String? changedBy,
  }) {
    return transaction(() async {
      final existing = await getSnapshotForPeriod(projectId, period);
      if (existing != null) {
        throw StateError('A snapshot for $period already exists');
      }
      final id = _uuid.v4();
      await into(forecastSnapshots).insert(ForecastSnapshotsCompanion.insert(
        id: id,
        projectId: projectId,
        period: period,
      ));

      var cells = <(String, String?, String, int, String?)>[];
      if (copyFromSnapshotId != null) {
        final src = await getForecastLines(copyFromSnapshotId);
        cells = [
          for (final l in src)
            (l.costCategoryId, l.workstreamId, l.financialYear,
                l.amountMinor, l.notes),
        ];
      } else if (copyFromBudget) {
        final budget = await getApprovedBudget(projectId);
        if (budget != null) {
          final src = await getLines(budget.id);
          cells = [
            for (final l in src)
              (l.costCategoryId, l.workstreamId, l.financialYear,
                  l.amountMinor, l.notes),
          ];
        }
      }
      for (final (cat, ws, fy, minor, notes) in cells) {
        await into(forecastLines).insert(ForecastLinesCompanion.insert(
          id: _uuid.v4(),
          projectId: projectId,
          snapshotId: id,
          costCategoryId: cat,
          workstreamId: Value(ws),
          financialYear: fy,
          amountMinor: minor,
          notes: Value(notes),
        ));
      }

      await _audit(
        projectId: projectId,
        entityType: 'ForecastSnapshot',
        entityId: id,
        field: 'created',
        newValue: period,
        changedBy: changedBy,
      );
      return id;
    });
  }

  /// Freezes the month: working → submitted. Submitted snapshots reject
  /// line edits.
  Future<void> submitSnapshot(String id, {String? changedBy}) {
    return transaction(() async {
      final row = await getSnapshotById(id);
      if (row == null) throw StateError('Snapshot not found: $id');
      if (row.status != 'working') {
        throw StateError('Only working snapshots can be submitted');
      }
      await (update(forecastSnapshots)..where((t) => t.id.equals(id)))
          .write(ForecastSnapshotsCompanion(
        status: const Value('submitted'),
        submittedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));
      await _audit(
        projectId: row.projectId,
        entityType: 'ForecastSnapshot',
        entityId: id,
        field: 'status',
        oldValue: 'working',
        newValue: 'submitted',
        changedBy: changedBy,
      );
    });
  }

  /// Un-freezes a submitted snapshot (mistake path). Audited.
  Future<void> reopenSnapshot(String id, {String? changedBy}) {
    return transaction(() async {
      final row = await getSnapshotById(id);
      if (row == null) throw StateError('Snapshot not found: $id');
      if (row.status != 'submitted') {
        throw StateError('Only submitted snapshots can be reopened');
      }
      await (update(forecastSnapshots)..where((t) => t.id.equals(id)))
          .write(ForecastSnapshotsCompanion(
        status: const Value('working'),
        submittedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ));
      await _audit(
        projectId: row.projectId,
        entityType: 'ForecastSnapshot',
        entityId: id,
        field: 'status',
        oldValue: 'submitted',
        newValue: 'working',
        changedBy: changedBy,
      );
    });
  }

  /// Deletes a WORKING snapshot and its lines. Submitted snapshots are
  /// monthly history and never deleted.
  Future<void> deleteWorkingSnapshot(String id, {String? changedBy}) {
    return transaction(() async {
      final row = await getSnapshotById(id);
      if (row == null) return;
      if (row.status != 'working') {
        throw StateError('Only working snapshots can be deleted');
      }
      await (delete(forecastLines)..where((t) => t.snapshotId.equals(id)))
          .go();
      await (delete(forecastSnapshots)..where((t) => t.id.equals(id))).go();
      await _audit(
        projectId: row.projectId,
        entityType: 'ForecastSnapshot',
        entityId: id,
        field: 'deleted',
        oldValue: row.period,
        changedBy: changedBy,
      );
    });
  }

  // ── Forecast lines (v2) ──────────────────────────────────────────────

  Stream<List<ForecastLine>> watchForecastLines(String snapshotId) {
    return (select(forecastLines)
          ..where((t) => t.snapshotId.equals(snapshotId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<List<ForecastLine>> getForecastLines(String snapshotId) {
    return (select(forecastLines)
          ..where((t) => t.snapshotId.equals(snapshotId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<BudgetTotals> getForecastTotals(String snapshotId) async {
    return BudgetTotals.fromForecastLines(
        await getForecastLines(snapshotId));
  }

  /// The forecast-at-completion trend: every snapshot's total, oldest
  /// first — the input for the variance trend chart.
  Future<List<({String period, int totalMinor, bool submitted})>>
      getForecastTrend(String projectId) async {
    final snaps = await getSnapshots(projectId);
    final out = <({String period, int totalMinor, bool submitted})>[];
    for (final s in snaps.reversed) {
      final totals = await getForecastTotals(s.id);
      out.add((
        period: s.period,
        totalMinor: totals.totalMinor,
        submitted: s.status == 'submitted',
      ));
    }
    return out;
  }

  Future<void> upsertForecastLine({
    required String id,
    required String projectId,
    required String snapshotId,
    required String costCategoryId,
    String? workstreamId,
    required String financialYear,
    required int amountMinor,
    String? notes,
    String? changedBy,
  }) {
    return transaction(() async {
      final snap = await getSnapshotById(snapshotId);
      if (snap == null) throw StateError('Snapshot not found: $snapshotId');
      if (snap.status != 'working') {
        throw StateError('Lines can only be edited on working snapshots');
      }
      final existing = await (select(forecastLines)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      await into(forecastLines).insertOnConflictUpdate(ForecastLinesCompanion(
        id: Value(id),
        projectId: Value(projectId),
        snapshotId: Value(snapshotId),
        costCategoryId: Value(costCategoryId),
        workstreamId: Value(workstreamId),
        financialYear: Value(financialYear),
        amountMinor: Value(amountMinor),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
      ));
      if (existing == null) {
        await _audit(
          projectId: projectId,
          entityType: 'ForecastLine',
          entityId: id,
          field: 'created',
          newValue: '$amountMinor',
          changedBy: changedBy,
        );
      } else if (existing.amountMinor != amountMinor) {
        await _audit(
          projectId: projectId,
          entityType: 'ForecastLine',
          entityId: id,
          field: 'amountMinor',
          oldValue: '${existing.amountMinor}',
          newValue: '$amountMinor',
          changedBy: changedBy,
        );
      }
    });
  }

  Future<void> deleteForecastLine(String id, {String? changedBy}) {
    return transaction(() async {
      final row = await (select(forecastLines)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return;
      final snap = await getSnapshotById(row.snapshotId);
      if (snap != null && snap.status != 'working') {
        throw StateError('Lines can only be deleted on working snapshots');
      }
      await (delete(forecastLines)..where((t) => t.id.equals(id))).go();
      await _audit(
        projectId: row.projectId,
        entityType: 'ForecastLine',
        entityId: id,
        field: 'deleted',
        oldValue: '${row.amountMinor}',
        changedBy: changedBy,
      );
    });
  }

  // ── Actuals (v2 — manual entry; CSV import lands in v3) ──────────────

  Stream<List<ActualLine>> watchActuals(String projectId) {
    return (select(actualLines)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.period)]))
        .watch();
  }

  Future<List<ActualLine>> getActuals(String projectId) {
    return (select(actualLines)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.period)]))
        .get();
  }

  /// Actuals totals — [BudgetTotals.byFinancialYear] is keyed by period.
  Future<BudgetTotals> getActualsTotals(String projectId) async {
    return BudgetTotals.fromActualLines(await getActuals(projectId));
  }

  Future<void> upsertActualLine({
    required String id,
    required String projectId,
    required String period,
    required String costCategoryId,
    String? workstreamId,
    required int amountMinor,
    String source = 'manual',
    String? sourceRef,
    String? notes,
    String? changedBy,
  }) {
    return transaction(() async {
      final existing = await (select(actualLines)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      await into(actualLines).insertOnConflictUpdate(ActualLinesCompanion(
        id: Value(id),
        projectId: Value(projectId),
        period: Value(period),
        costCategoryId: Value(costCategoryId),
        workstreamId: Value(workstreamId),
        amountMinor: Value(amountMinor),
        source: Value(source),
        sourceRef: Value(sourceRef),
        enteredBy: Value(changedBy),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
      ));
      if (existing == null) {
        await _audit(
          projectId: projectId,
          entityType: 'ActualLine',
          entityId: id,
          field: 'created',
          newValue: '$amountMinor',
          changedBy: changedBy,
        );
      } else if (existing.amountMinor != amountMinor) {
        await _audit(
          projectId: projectId,
          entityType: 'ActualLine',
          entityId: id,
          field: 'amountMinor',
          oldValue: '${existing.amountMinor}',
          newValue: '$amountMinor',
          changedBy: changedBy,
        );
      }
    });
  }

  Future<void> deleteActualLine(String id, {String? changedBy}) {
    return transaction(() async {
      final row = await (select(actualLines)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return;
      await (delete(actualLines)..where((t) => t.id.equals(id))).go();
      await _audit(
        projectId: row.projectId,
        entityType: 'ActualLine',
        entityId: id,
        field: 'deleted',
        oldValue: '${row.amountMinor}',
        changedBy: changedBy,
      );
    });
  }

  Future<void> setVarianceTolerance(String budgetId, int toleranceBp,
      {String? changedBy}) {
    return transaction(() async {
      final row = await getBudgetById(budgetId);
      if (row == null) throw StateError('Budget not found: $budgetId');
      if (row.varianceToleranceBp == toleranceBp) return;
      await (update(projectBudgets)..where((t) => t.id.equals(budgetId)))
          .write(ProjectBudgetsCompanion(
        varianceToleranceBp: Value(toleranceBp),
        updatedAt: Value(DateTime.now()),
      ));
      await _audit(
        projectId: row.projectId,
        entityType: 'ProjectBudget',
        entityId: budgetId,
        field: 'varianceToleranceBp',
        oldValue: '${row.varianceToleranceBp}',
        newValue: '$toleranceBp',
        changedBy: changedBy,
      );
    });
  }

  // ── Raw upserts — sync importer ONLY (no audit generation) ───────────

  Future<void> upsertCategoryRaw(CostCategoriesCompanion entry) {
    return into(costCategories).insertOnConflictUpdate(entry);
  }

  Future<void> upsertBudgetRaw(ProjectBudgetsCompanion entry) {
    return into(projectBudgets).insertOnConflictUpdate(entry);
  }

  Future<void> upsertLineRaw(BudgetLinesCompanion entry) {
    return into(budgetLines).insertOnConflictUpdate(entry);
  }

  Future<void> upsertAuditRaw(FinancialAuditLogCompanion entry) {
    return into(financialAuditLog).insertOnConflictUpdate(entry);
  }

  Future<void> upsertSnapshotRaw(ForecastSnapshotsCompanion entry) {
    return into(forecastSnapshots).insertOnConflictUpdate(entry);
  }

  Future<void> upsertForecastLineRaw(ForecastLinesCompanion entry) {
    return into(forecastLines).insertOnConflictUpdate(entry);
  }

  Future<void> upsertActualLineRaw(ActualLinesCompanion entry) {
    return into(actualLines).insertOnConflictUpdate(entry);
  }
}
