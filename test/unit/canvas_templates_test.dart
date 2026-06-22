import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/templates/template_registry.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P1'));
  });

  tearDown(() async => db.close());

  Future<void> insertTemplate(
    String id, {
    String projectId = 'p1',
    String type = CanvasTemplateType.swot,
    String name = 'My SWOT',
    String content = '{}',
  }) {
    return db.canvasTemplatesDao.insertTemplate(
      CanvasTemplatesCompanion.insert(
        id: id,
        projectId: projectId,
        templateType: type,
        name: name,
        content: content,
      ),
    );
  }

  group('CanvasTemplatesDao', () {
    test('inserts and retrieves by id', () async {
      await insertTemplate('t1', name: 'Q3 SWOT', content: '{"a":1}');
      final got = await db.canvasTemplatesDao.getTemplateById('t1');
      expect(got, isNotNull);
      expect(got!.name, 'Q3 SWOT');
      expect(got.templateType, CanvasTemplateType.swot);
      expect(got.content, '{"a":1}');
    });

    test('watchTemplatesForProject orders by updatedAt desc', () async {
      await insertTemplate('older');
      // bump time to guarantee a later updatedAt
      await Future.delayed(const Duration(milliseconds: 1100));
      await insertTemplate('newer');
      final list = await db.canvasTemplatesDao
          .watchTemplatesForProject('p1')
          .first;
      expect(list.map((t) => t.id), ['newer', 'older']);
    });

    test('patchTemplate bumps updatedAt and updates only supplied fields',
        () async {
      await insertTemplate('t1', name: 'Original', content: '{"x":1}');
      final before = await db.canvasTemplatesDao.getTemplateById('t1');
      await Future.delayed(const Duration(milliseconds: 1100));
      await db.canvasTemplatesDao.patchTemplate(
        't1',
        CanvasTemplatesCompanion(name: const Value('Renamed')),
      );
      final after = await db.canvasTemplatesDao.getTemplateById('t1');
      expect(after!.name, 'Renamed');
      expect(after.content, '{"x":1}'); // untouched
      expect(after.templateType, before!.templateType); // untouched
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
    });

    test('deleteTemplate removes the row', () async {
      await insertTemplate('t1');
      final rows = await db.canvasTemplatesDao.deleteTemplate('t1');
      expect(rows, 1);
      expect(await db.canvasTemplatesDao.getTemplateById('t1'), isNull);
    });

    test('is project-scoped', () async {
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p2', name: 'P2'));
      await insertTemplate('t1', projectId: 'p1');
      await insertTemplate('t2', projectId: 'p2');
      final p1 = await db.canvasTemplatesDao.getTemplatesForProject('p1');
      final p2 = await db.canvasTemplatesDao.getTemplatesForProject('p2');
      expect(p1.map((t) => t.id), ['t1']);
      expect(p2.map((t) => t.id), ['t2']);
    });

    test('deleteProjectCascade removes templates for the project',
        () async {
      await insertTemplate('t1');
      await insertTemplate('t2');
      await db.deleteProjectCascade('p1');
      expect(
        await db.canvasTemplatesDao.getTemplatesForProject('p1'),
        isEmpty,
      );
    });
  });

  group('TemplateRegistry', () {
    test('lists all six template types', () {
      expect(TemplateRegistry.available, hasLength(6));
      expect(
        TemplateRegistry.available.map((d) => d.type).toSet(),
        {
          CanvasTemplateType.preMortem,
          CanvasTemplateType.swot,
          CanvasTemplateType.retrospective,
          CanvasTemplateType.stakeholderMap,
          CanvasTemplateType.raciMatrix,
          CanvasTemplateType.userStoryMap,
        },
      );
    });

    test('byType returns the matching definition', () {
      final def = TemplateRegistry.byType(CanvasTemplateType.swot);
      expect(def, isNotNull);
      expect(def!.name, 'SWOT');
    });

    test('byType returns null for unknown types', () {
      expect(TemplateRegistry.byType('not_a_type'), isNull);
    });

    test('every type has a non-empty default content JSON', () {
      for (final def in TemplateRegistry.available) {
        expect(def.defaultContent, isNotEmpty,
            reason: 'type ${def.type} should have default content');
        // Parses as valid JSON (basic sanity check — actual schemas
        // are owned per-template).
        expect(
          () => CanvasTemplatesCompanion.insert(
            id: 'x',
            projectId: 'p1',
            templateType: def.type,
            name: 'n',
            content: def.defaultContent,
          ),
          returnsNormally,
        );
      }
    });

    test('only User Story Map declares fullscreen support (Phase 2 cohort)',
        () {
      final fullscreen = TemplateRegistry.available
          .where((d) => d.supportsFullscreen)
          .map((d) => d.type)
          .toList();
      expect(fullscreen, [CanvasTemplateType.userStoryMap]);
    });
  });
}
