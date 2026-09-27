// Diagnostic: replay the cascade for a project against a DB file the way
// the shell does at launch, and report what landed on the channel. Never
// point it at the live DB while Keel is open — copy it first.
//
//   KEEL_DB=/path/copy.db KEEL_PROJECT=<projectId> KEEL_PROGRAMME=<id> \
//     flutter test tool/cascade_replay_probe.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_service.dart';
import 'package:keel/core/cascade/cascade_sync.dart';
import 'package:keel/core/cascade/composite_cascade_gateway.dart';
import 'package:keel/core/database/database.dart';

void main() {
  test('cascade replay probe', () async {
    final env = Platform.environment;
    final dbPath = env['KEEL_DB'];
    final projectId = env['KEEL_PROJECT'];
    final programmeId = env['KEEL_PROGRAMME'];
    if (dbPath == null || projectId == null || programmeId == null) {
      print('Set KEEL_DB, KEEL_PROJECT, KEEL_PROGRAMME.');
      return;
    }
    final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
    addTearDown(db.close);

    Future<void> counts(String label) async {
      final rows = await db.customSelect(
          'select item_kind k, count(*) n, sum(deleted) d from cascade_items group by k').get();
      print('$label: ${rows.map((r) => '${r.data['k']}=${r.data['n']}(-${r.data['d']})').join(', ')}');
    }

    await counts('before');
    final repaired = await db.programmeLinksDao.repairSameMachineLinks();
    print('repaired link rows: $repaired');
    final links = await db.programmeLinksDao.getLinksForEntity(projectId);
    for (final l in links) {
      print('link ${l.ownerKind} status=${l.status} level=${l.shareLevel} partner=${l.partnerLocalId}');
    }
    final cascade = CascadeService(db,
        gateway: CompositeCascadeGateway(db, remote: null));
    try {
      await reconcileCascade(db: db, cascade: cascade, projectId: projectId);
    } catch (e, st) {
      print('PROJECT reconcile threw: $e\n$st');
    }
    await counts('after project push');
    try {
      final n = await reconcileCascade(
          db: db, cascade: cascade, projectId: programmeId);
      print('programme applied $n');
    } catch (e, st) {
      print('PROGRAMME reconcile threw: $e\n$st');
    }
    final acts = await db.programmeGanttDao.getActivitiesForProject(programmeId);
    print('programme activities: ${acts.length}, cascaded: '
        '${acts.where((a) => a.sourceProjectId != null).length}');
    final risks = await db.raidDao.getRisksForProject(programmeId);
    print('programme risks: ${risks.length}, cascaded: '
        '${risks.where((r) => r.sourceProjectId != null).length}');
    print('programme finance: own budgets '
        '${(await db.financeDao.getBudgets(programmeId)).length}, cascaded budgets '
        '${(await db.financeDao.getCascadedBudgets(programmeId)).length}, '
        'cascaded snapshots '
        '${(await db.financeDao.getCascadedSnapshots(programmeId)).length}, '
        'cascaded actuals '
        '${(await db.financeDao.getCascadedActuals(programmeId)).length}, '
        'cascaded categories '
        '${(await db.financeDao.getCascadedCategories(programmeId)).length}');
    print('project finance: approved '
        '${(await db.financeDao.getApprovedBudget(projectId))?.name}, snapshots '
        '${(await db.financeDao.getSnapshots(projectId)).map((s) => '${s.period}:${s.status}').join(' ')}');
  });
}
