import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/export/ms_project_state.dart';
import 'package:keel/core/import/json_importer.dart';

/// The Microsoft Project UIDs must ride the sync blob, or the other
/// machine's next export renumbers every task.
void main() {
  late AppDatabase src;
  late AppDatabase dst;

  setUp(() async {
    src = AppDatabase.memory();
    dst = AppDatabase.memory();
    await src.into(src.projects).insert(
        ProjectsCompanion.insert(id: 'p1', name: 'Sync MSP'));
    await src.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion(
      id: const Value('h1'),
      projectId: const Value('p1'),
      month0Date: const Value('2026-04-01'),
      msProjectState: Value(const MsProjectState(
        taskUids: {'act1': 7},
        nextTaskUid: 8,
      ).encode()),
    ));
  });

  tearDown(() async {
    await src.close();
    await dst.close();
  });

  test('the export UIDs survive export → import', () async {
    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);
    final h = (await dst.programmeGanttDao.getHeader('p1'))!;
    final state = MsProjectState.decode(h.msProjectState);
    expect(state.taskUids, {'act1': 7});
    expect(state.nextTaskUid, 8);
  });

  test('a pull from a machine without the field keeps our UIDs', () async {
    // dst already exported (it has UIDs); src runs an older build.
    await dst.into(dst.projects).insert(
        ProjectsCompanion.insert(id: 'p1', name: 'Sync MSP'));
    await dst.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion(
      id: const Value('h1'),
      projectId: const Value('p1'),
      msProjectState: Value(const MsProjectState(
        taskUids: {'act1': 7, 'act2': 9},
        nextTaskUid: 10,
      ).encode()),
    ));
    final blob = jsonDecode(
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src))
        as Map<String, dynamic>;
    _strip(blob, 'ms_project_state');
    await JsonImporter.importFromString(jsonEncode(blob), dst);
    final h = (await dst.programmeGanttDao.getHeader('p1'))!;
    expect(h.month0Date, '2026-04-01', reason: 'the rest of the header imports');
    expect(MsProjectState.decode(h.msProjectState).taskUids,
        {'act1': 7, 'act2': 9});
  });

  test('a pull from a machine that never exported keeps our UIDs', () async {
    await dst.into(dst.projects).insert(
        ProjectsCompanion.insert(id: 'p1', name: 'Sync MSP'));
    await dst.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion(
      id: const Value('h1'),
      projectId: const Value('p1'),
      msProjectState: Value(const MsProjectState(taskUids: {'x': 3}).encode()),
    ));
    await src.programmeGanttDao.upsertHeader(const ProgrammeHeadersCompanion(
      id: Value('h1'),
      projectId: Value('p1'),
      msProjectState: Value(null),
    ));
    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);
    final h = (await dst.programmeGanttDao.getHeader('p1'))!;
    expect(MsProjectState.decode(h.msProjectState).taskUids, {'x': 3});
  });
}

void _strip(Object? node, String key) {
  if (node is Map) {
    node.remove(key);
    for (final v in node.values) {
      _strip(v, key);
    }
  } else if (node is List) {
    for (final v in node) {
      _strip(v, key);
    }
  }
}
