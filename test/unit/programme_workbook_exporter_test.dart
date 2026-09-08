import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/export/programme_workbook_exporter.dart';
import 'package:keel/core/import/json_importer.dart';

/// Regression suite for the "white text on a white sheet" bug: the
/// workbook used to export Keel's dark-theme colours into Excel, whose
/// ground is white. Every styled cell must now satisfy a contrast
/// invariant — light text only on dark fills, dark text elsewhere,
/// never fg == bg.
void main() {
  late AppDatabase db;
  const projectId = 'p-wb';

  setUp(() async {
    db = AppDatabase.memory();
    await db.into(db.projects).insert(ProjectsCompanion.insert(
          id: projectId,
          name: 'Workbook Test',
        ));

    final dao = db.programmeGanttDao;
    await dao.upsertHeader(ProgrammeHeadersCompanion(
      id: const Value('h1'),
      projectId: const Value(projectId),
      title: const Value('Test Plan'),
      hardDeadline: const Value('Go-live 1 Nov'),
      monthLabels: Value(jsonEncode(['Jan', 'Feb', 'Mar', 'Apr'])),
    ));
    // wp4 is the AMBER theme — the exact fill the old exporter paired
    // with hardcoded white text.
    await dao.upsertWorkPackage(const TimelineWorkPackagesCompanion(
      id: Value('wp-a'),
      projectId: Value(projectId),
      name: Value('Amber package'),
      shortCode: Value('WPA'),
      colourTheme: Value('wp4'),
    ));
    await dao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('a1'),
      workPackageId: Value('wp-a'),
      projectId: Value(projectId),
      name: Value('Build the thing'),
      activityType: Value('activity'),
      startMonth: Value(0),
      endMonth: Value(1),
      isCritical: Value(true),
    ));
    await dao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('a2'),
      workPackageId: Value('wp-a'),
      projectId: Value(projectId),
      name: Value('Ship the thing'),
      activityType: Value('milestone'),
      startMonth: Value(0),
      endMonth: Value(0),
      // A/B/C scenario months with the RAID items driving the spread.
      // Likely is non-adjacent to the anchor so the ┄ thread renders.
      likelyMonth: Value(2),
      safeMonth: Value(3),
      varianceRaidType: Value('risk'),
      varianceRaidId: Value('r1'),
      varianceRaidLinksJson: Value(
          '[{"type":"risk","id":"r1"},{"type":"assumption","id":"as1"}]'),
    ));
    await dao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('a1-task'),
      workPackageId: Value('wp-a'),
      projectId: Value(projectId),
      name: Value('Sub task'),
      activityType: Value('activity'),
      parentActivityId: Value('a1'),
      startMonth: Value(0),
      endMonth: Value(0),
    ));
    await dao.upsertDependency(const TimelineDependenciesCompanion(
      id: Value('d1'),
      projectId: Value(projectId),
      fromActivityId: Value('a1'),
      toActivityId: Value('a2'),
      dependencyType: Value('finish_to_start'),
    ));
    await dao.upsertDependency(const TimelineDependenciesCompanion(
      id: Value('d2'),
      projectId: Value(projectId),
      fromActivityId: Value(''),
      toActivityId: Value('a1'),
      dependencyType: Value('finish_to_start'),
      externalLabel: Value('Vendor API'),
    ));

    // The stakeholder combinations that used to render fg == bg.
    await db.stakeholderRoleDao.upsert(const StakeholderRolesCompanion(
      id: Value('sr1'),
      projectId: Value(projectId),
      roleName: Value('Programme Sponsor'),
      roleType: Value('stakeholder'),
      priority: Value('medium'),
      engagementStatus: Value('engaged'),
    ));

    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r1'),
      projectId: Value(projectId),
      ref: Value('R19'),
      description: Value('Everything is on fire'),
      likelihood: Value('high'),
      impact: Value('high'),
      status: Value('open'),
    ));
    await db.raidDao.upsertAssumption(const AssumptionsCompanion(
      id: Value('as1'),
      projectId: Value(projectId),
      ref: Value('A3'),
      description: Value('AWS lands on time'),
      status: Value('open'),
    ));
  });

  tearDown(() => db.close());

  int? luminance(String hex) {
    if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(hex)) return null;
    final r = int.parse(hex.substring(2, 4), radix: 16);
    final g = int.parse(hex.substring(4, 6), radix: 16);
    final b = int.parse(hex.substring(6, 8), radix: 16);
    return (r * 299 + g * 587 + b * 114) ~/ 1000;
  }

  test('every cell with text is dark ink on a light ground — no light '
      'text exists anywhere in the workbook', () async {
    final bytes = await ProgrammeWorkbookExporter.buildBytes(
      db: db,
      projectId: projectId,
      projectName: 'Workbook Test',
    );
    final excel = Excel.decodeBytes(bytes);
    expect(excel.tables, isNotEmpty);

    var checked = 0;
    for (final entry in excel.tables.entries) {
      for (final (rowIdx, row) in entry.value.rows.indexed) {
        for (final (colIdx, cell) in row.indexed) {
          final style = cell?.cellStyle;
          if (style == null) continue;
          final fg = style.fontColor.colorHex;
          final bg = style.backgroundColor.colorHex;
          final where = '${entry.key} r$rowIdx c$colIdx (fg=$fg bg=$bg)';
          final text = cell?.value?.toString() ?? '';
          // Text-free cells are the gantt bars: pure colour, any fill
          // allowed. Every cell that SAYS something must be dark ink
          // on a light ground — so even a fill that fails to render in
          // someone's spreadsheet app leaves the text readable.
          if (text.isEmpty) continue;
          expect(fg == bg, isFalse, reason: 'fg == bg at $where');
          final bgLum = luminance(bg) ?? 255;
          final fgLum = luminance(fg) ?? 0;
          expect(fgLum, lessThanOrEqualTo(160),
              reason: 'light text at $where');
          expect(bgLum, greaterThanOrEqualTo(150),
              reason: 'dark fill under text at $where');
          checked++;
        }
      }
    }
    // Sanity: the invariant actually ran over a meaningful cell count.
    expect(checked, greaterThan(50));
  });

  test('dependencies surface in the timeline grid via # and AFTER '
      'columns', () async {
    final bytes = await ProgrammeWorkbookExporter.buildBytes(
      db: db,
      projectId: projectId,
      projectName: 'Workbook Test',
    );
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables['Programme Timeline']!;
    final text = sheet.rows
        .expand((r) => r)
        .map((c) => c?.value?.toString() ?? '')
        .toList();
    // a1 depends on the external 'Vendor API'; a2 (milestone) depends
    // on a1, which is activity #1 in WBS render order.
    expect(text, contains('← EXT'));
    expect(text, contains('← 1'));
    expect(text, contains('AFTER'));
  });

  test('plan dependencies ride in their own sheet, external deps labelled',
      () async {
    final bytes = await ProgrammeWorkbookExporter.buildBytes(
      db: db,
      projectId: projectId,
      projectName: 'Workbook Test',
    );
    final excel = Excel.decodeBytes(bytes);
    final deps = excel.tables['Plan Dependencies'];
    expect(deps, isNotNull);

    final text = deps!.rows
        .expand((r) => r)
        .map((c) => c?.value?.toString() ?? '')
        .join('\n');
    expect(text, contains('#1  Build the thing'));
    expect(text, contains('#3  Ship the thing'));
    expect(text, contains('Finish → Start'));
    expect(text, contains('Vendor API (external)'));
  });

  test('timeline sheet name follows the entity kind', () async {
    final programmeBytes = await ProgrammeWorkbookExporter.buildBytes(
        db: db, projectId: projectId, projectName: 'X');
    expect(Excel.decodeBytes(programmeBytes).tables.keys,
        contains('Programme Timeline'));

    final projectBytes = await ProgrammeWorkbookExporter.buildBytes(
        db: db, projectId: projectId, projectName: 'X', isProgramme: false);
    final tables = Excel.decodeBytes(projectBytes).tables.keys;
    expect(tables, contains('Project Timeline'));
    expect(tables, isNot(contains('Programme Timeline')));
  });

  test('scenario dates surface as a register sheet and grid ghosts',
      () async {
    final bytes = await ProgrammeWorkbookExporter.buildBytes(
        db: db, projectId: projectId, projectName: 'X');
    final excel = Excel.decodeBytes(bytes);

    // Register sheet: A/B/C month labels + linked risk ref.
    final register = excel.tables['Milestone Register'];
    expect(register, isNotNull);
    final regText = register!.rows
        .expand((r) => r)
        .map((c) => c?.value?.toString() ?? '')
        .toList();
    expect(regText, contains('Ship the thing'));
    expect(regText, contains('Jan')); // A — anchor (month 0)
    expect(regText, contains('Mar')); // B — likely (month 2)
    expect(regText, contains('Apr')); // C — safe (month 3)
    expect(regText, contains('R19, A3')); // ALL variance drivers

    // Timeline grid: ◇ and ○ ghosts echo the anchor ◆, and the RISK
    // column carries the ref.
    final timeline = excel.tables['Programme Timeline']!;
    final gridText = timeline.rows
        .expand((r) => r)
        .map((c) => c?.value?.toString() ?? '')
        .toList();
    expect(gridText, contains('◇'));
    expect(gridText, contains('○'));
    expect(gridText, contains('┄')); // dotted thread in the gap month
    expect(gridText, contains('R19, A3'));
  });

  test('scenario fields round-trip the sync blob', () async {
    final blob = await JsonExporter.exportProjectToString(
        projectId: projectId, db: db);
    final db2 = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db2.close);
    await JsonImporter.importFromString(blob, db2);

    final acts =
        await db2.programmeGanttDao.getActivitiesForProject(projectId);
    final a2 = acts.firstWhere((a) => a.id == 'a2');
    expect(a2.likelyMonth, 2);
    expect(a2.safeMonth, 3);
    expect(a2.varianceRaidType, 'risk');
    expect(a2.varianceRaidId, 'r1');
    expect(a2.varianceRaidLinksJson,
        '[{"type":"risk","id":"r1"},{"type":"assumption","id":"as1"}]');

    // Regression: the exporter used to omit external_label, so every
    // sync round-trip stripped external deps into corrupt
    // type='external' label=null rows (crashed the predecessors form).
    final deps2 =
        await db2.programmeGanttDao.getDependencies(projectId);
    final ext = deps2.firstWhere((d) => d.id == 'd2');
    expect(ext.externalLabel, 'Vendor API');
    expect(ext.dependencyType, 'finish_to_start');
  });

  test('WBS tasks are indented under their parent activity', () async {
    final bytes = await ProgrammeWorkbookExporter.buildBytes(
        db: db, projectId: projectId, projectName: 'X');
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables['Programme Timeline']!;
    final names = sheet.rows
        .map((r) => r.length > 2 ? r[2]?.value?.toString() ?? '' : '')
        .toList();
    final parentIdx =
        names.indexWhere((n) => n.startsWith('Build the thing'));
    expect(parentIdx, greaterThanOrEqualTo(0));
    expect(names[parentIdx + 1], contains('↳ Sub task'));
  });
}
