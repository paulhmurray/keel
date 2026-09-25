/// Applies a "Planview Risks" sheet to a project's risk register.
///
/// Reading the workbook and deciding what each row does live in
/// [planview_risk_sheet.dart]; this file is the write side, kept
/// separate so the decision can be dry-run and unit-tested without a
/// workbook or a file on disk.
library;

import 'package:drift/drift.dart' show Value;
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import 'planview_risk_sheet.dart';

/// Reads the "Planview Risks" sheet into rows; the header row is found
/// by shape (an R-ref in column A), so a title line above it is fine.
List<PlanviewRiskRow> readPlanviewRows(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables['Planview Risks'];
  if (sheet == null) {
    throw StateError('No "Planview Risks" sheet in workbook. Sheets: '
        '${excel.tables.keys.join(', ')}');
  }
  final out = <PlanviewRiskRow>[];
  for (final row in sheet.rows) {
    final cells = row.map((c) => c?.value?.toString()).toList();
    final parsed = PlanviewRiskRow.fromCells(cells);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

class PlanviewImportResult {
  final int updated;
  final int created;
  final int renumbered;
  const PlanviewImportResult(
      {required this.updated, required this.created, required this.renumbered});
}

/// Writes [plan] to [db] in one transaction. Sheet fields overwrite
/// their Keel counterparts; fields the sheet does not carry (status,
/// rationales, closure, source, cascade markers, created date) are kept
/// from the existing row, or defaulted for a new one.
Future<PlanviewImportResult> applyPlanviewImport(
  AppDatabase db, {
  required String projectId,
  required List<PlanviewMatch> plan,
  DateTime? now,
}) async {
  final stamp = now ?? DateTime.now();
  var updated = 0, created = 0, renumbered = 0;
  await db.transaction(() async {
    for (final m in plan) {
      if (m.kind == PlanviewMatchKind.renumber) {
        await (db.update(db.risks)..where((t) => t.id.equals(m.existing!.id)))
            .write(RisksCompanion(
          ref: Value(m.newRefForExisting),
          updatedAt: Value(stamp),
        ));
        renumbered++;
      }
      final target = m.kind == PlanviewMatchKind.update ? m.existing : null;
      final id = target?.id ?? const Uuid().v4();
      final r = m.row;
      await db.raidDao.upsertRisk(RisksCompanion(
        id: Value(id),
        projectId: Value(projectId),
        ref: Value(r.ref),
        title: Value(r.title.isEmpty ? null : r.title),
        description: Value(r.description),
        likelihood: Value(r.likelihood),
        impact: Value(r.consequence),
        likelihoodTarget: Value(r.likelihoodTarget),
        impactTarget: Value(r.consequenceTarget),
        strategy: Value(r.strategy),
        mitigation: Value(r.treatmentPlan),
        owner: Value(r.owner),
        assignee: Value(r.assignee),
        steerco: Value(r.steerco),
        enterpriseRiskLink: Value(r.enterpriseRiskLink),
        dueDate: Value(r.dueDate),
        lastReviewedAt: Value(r.lastReview),
        nextReviewAt: Value(r.nextReview),
        statusNote: Value(r.statusNote),
        status: Value(target?.status ?? 'open'),
        likelihoodRationale: Value(target?.likelihoodRationale),
        impactRationale: Value(target?.impactRationale),
        closedAt: Value(target?.closedAt),
        closureNote: Value(target?.closureNote),
        source: Value(target?.source ?? 'document'),
        sourceNote: Value(target?.sourceNote ??
            'Imported from Planview Risks sheet '
                '${stamp.toIso8601String().substring(0, 10)}'),
        escalatedAt: Value(target?.escalatedAt),
        sourceProjectId: Value(target?.sourceProjectId),
        createdAt: Value(target?.createdAt ??
            (r.raisedOn != null ? DateTime.parse(r.raisedOn!) : stamp)),
        updatedAt: Value(stamp),
      ));
      if (target != null) {
        updated++;
      } else {
        created++;
      }
    }
  });
  return PlanviewImportResult(
      updated: updated, created: created, renumbered: renumbered);
}
