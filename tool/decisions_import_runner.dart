// One-off runner: import the "Open decisions" block of a plan workbook's
// "Actions & Decisions" sheet into a Keel project's decision register.
//
//   KEEL_XLSX=/path/plan.xlsx KEEL_DB=/path/keel.db KEEL_PROJECT=<id> \
//     flutter test tool/decisions_import_runner.dart            # dry run
//   ... KEEL_APPLY=1 flutter test tool/decisions_import_runner.dart  # write
//
// Written as a flutter_test (see planview_import_runner.dart for why).
// Back the database up and close Keel before KEEL_APPLY=1.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/decisions_sheet.dart';

List<SheetDecisionRow> readSheetDecisions(List<int> bytes) {
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables['Actions & Decisions'];
  if (sheet == null) {
    throw StateError('No "Actions & Decisions" sheet. Sheets: '
        '${excel.tables.keys.join(', ')}');
  }
  final out = <SheetDecisionRow>[];
  for (final row in sheet.rows) {
    final parsed = SheetDecisionRow.fromCells(
        row.map((c) => c?.value?.toString()).toList());
    if (parsed != null) out.add(parsed);
  }
  return out;
}

void main() {
  test('import Actions & Decisions sheet → decisions', () async {
    final env = Platform.environment;
    final xlsx = env['KEEL_XLSX'];
    final dbPath = env['KEEL_DB'];
    final projectId = env['KEEL_PROJECT'];
    final apply = env['KEEL_APPLY'] == '1';
    if (xlsx == null || dbPath == null || projectId == null) {
      print('Set KEEL_XLSX, KEEL_DB and KEEL_PROJECT (and KEEL_APPLY=1 to write).');
      return;
    }
    final rows = readSheetDecisions(File(xlsx).readAsBytesSync());
    print('Sheet decisions: ${rows.length}');

    final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
    try {
      final existing = await db.decisionsDao.getDecisionsForProject(projectId);
      print('Keel decisions in project: ${existing.length}');
      final plan = planDecisionsImport(rows, existing);
      for (final m in plan) {
        final r = m.row;
        final head = r.description.length > 70
            ? '${r.description.substring(0, 67)}…'
            : r.description;
        switch (m.kind) {
          case DecisionMatchKind.update:
            print('UPDATE ${m.existing!.ref} ← ${r.sheetRef}  "$head"  '
                '(was "${_short(m.existing!.description)}", ${m.existing!.status} → ${r.status})');
          case DecisionMatchKind.create:
            print('CREATE        ← ${r.sheetRef}  "$head"  '
                '[${r.decisionMaker ?? '—'} · by ${r.neededBy ?? '—'}]');
        }
      }
      if (!apply) {
        print('\nDry run — nothing written. Set KEEL_APPLY=1 to write.');
        return;
      }
      final result =
          await applyDecisionsImport(db, projectId: projectId, plan: plan);
      print('\nApplied: ${result.updated} updated, ${result.created} created.');
      final after = await db.decisionsDao.getDecisionsForProject(projectId);
      print('Register now: ${after.length} decisions, '
          '${after.where((d) => d.status == 'pending').length} pending.');
    } finally {
      await db.close();
    }
  });
}

String _short(String s) => s.length > 50 ? '${s.substring(0, 47)}…' : s;
