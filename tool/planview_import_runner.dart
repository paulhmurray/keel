// One-off runner: import a workbook's "Planview Risks" sheet into a Keel
// database. Lives under tool/ (not test/) so the suite never picks it
// up; it is written as a flutter_test because the database layer pulls
// in Flutter plugins that plain `dart run` cannot load.
//
//   KEEL_XLSX=/path/plan.xlsx KEEL_DB=/path/keel.db KEEL_PROJECT=<id> \
//     flutter test tool/planview_import_runner.dart            # dry run
//   ... KEEL_APPLY=1 flutter test tool/planview_import_runner.dart  # write
//
// Opening the DB through AppDatabase runs the current schema migration
// first. Back the file up before KEEL_APPLY=1, and close Keel.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/planview_risk_import.dart';
import 'package:keel/core/raid/planview_risk_sheet.dart';
import 'package:keel/core/raid/raid_conversion_service.dart';
import 'package:keel/core/raid/raid_lifecycle.dart';

void main() {
  test('import Planview Risks sheet', () async {
    final env = Platform.environment;
    final xlsx = env['KEEL_XLSX'];
    final dbPath = env['KEEL_DB'];
    final projectId = env['KEEL_PROJECT'];
    final apply = env['KEEL_APPLY'] == '1';
    if (xlsx == null || dbPath == null || projectId == null) {
      print('Set KEEL_XLSX, KEEL_DB and KEEL_PROJECT (and KEEL_APPLY=1 to write).');
      return;
    }

    final rows = readPlanviewRows(File(xlsx).readAsBytesSync());
    print('Sheet rows: ${rows.length}');

    final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
    try {
      final existing = await db.raidDao.getRisksForProject(projectId);
      print('Keel risks in project: ${existing.length}');
      final plan = planPlanviewImport(rows, existing);
      for (final m in plan) {
        switch (m.kind) {
          case PlanviewMatchKind.update:
            print('UPDATE   ${m.row.ref}  ${m.row.title}');
          case PlanviewMatchKind.create:
            print('CREATE   ${m.row.ref}  ${m.row.title}');
          case PlanviewMatchKind.renumber:
            print('RENUMBER ${m.row.ref}: Keel "${_short(m.existing!.description)}" '
                '→ ${m.newRefForExisting}; sheet "${m.row.title}" takes ${m.row.ref}');
        }
      }
      if (!apply) {
        print('\nDry run — nothing written. Set KEEL_APPLY=1 to write.');
        return;
      }
      final result =
          await applyPlanviewImport(db, projectId: projectId, plan: plan);
      print('\nApplied: ${result.updated} updated, ${result.created} created, '
          '${result.renumbered} renumbered.');

      final after = await db.raidDao.getRisksForProject(projectId);
      final counts = <String, int>{};
      for (final r in after) {
        if (r.ref != null) counts[r.ref!] = (counts[r.ref!] ?? 0) + 1;
      }
      final dups = counts.entries.where((e) => e.value > 1).map((e) => e.key);
      if (dups.isNotEmpty) print('WARNING duplicate refs: ${dups.join(', ')}');
      final closed =
          after.where((r) => isTerminalStatus(RaidKind.risk, r.status)).length;
      print('Register now: ${after.length} risks, $closed closed.');
    } finally {
      await db.close();
    }
  });
}

String _short(String s) => s.length > 50 ? '${s.substring(0, 47)}…' : s;
