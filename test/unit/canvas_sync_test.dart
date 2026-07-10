import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/import/json_importer.dart';

/// Canvas (cards + sequences + template instances) must ride the project
/// sync so it reaches the owner's other machines. Full round-trip:
/// seed → export → import into a fresh DB → assert everything survived.
void main() {
  test('canvas cards, sequences and templates round-trip through sync',
      () async {
    final src = AppDatabase.memory();
    final dst = AppDatabase.memory();
    addTearDown(src.close);
    addTearDown(dst.close);

    await src.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'Proj'));

    // Two cards, a sequence between them, and a template instance.
    await src.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
      id: 'c1',
      projectId: 'p1',
      title: 'Discovery',
      body: const Value('Kick off #cutover'),
      band: const Value('this_week'),
      tags: const Value('["cutover"]'),
    ));
    await src.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
      id: 'c2',
      projectId: 'p1',
      title: 'Build',
    ));
    await src.canvasCardsDao.addSequence(
      id: 's1',
      projectId: 'p1',
      fromCardId: 'c1',
      toCardId: 'c2',
    );
    await src.canvasTemplatesDao.insertTemplate(
      CanvasTemplatesCompanion.insert(
        id: 't1',
        projectId: 'p1',
        templateType: 'wardley_map',
        name: 'Value chain',
        content: '{"components":[{"id":"u","label":"User"}]}',
      ),
    );

    // Export → import into the fresh DB.
    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);

    final cards = await dst.canvasCardsDao.getCardsForProject('p1');
    expect(cards.map((c) => c.id).toSet(), {'c1', 'c2'});
    final c1 = cards.firstWhere((c) => c.id == 'c1');
    expect(c1.title, 'Discovery');
    expect(c1.body, 'Kick off #cutover');
    expect(c1.tags, '["cutover"]');

    final seqs = await dst.canvasCardsDao.getSequencesForProject('p1');
    expect(seqs, hasLength(1));
    expect(seqs.single.fromCardId, 'c1');
    expect(seqs.single.toCardId, 'c2');

    final templates =
        await dst.canvasTemplatesDao.getTemplatesForProject('p1');
    expect(templates, hasLength(1));
    expect(templates.single.templateType, 'wardley_map');
    expect(templates.single.name, 'Value chain');
    expect(templates.single.content, contains('User'));
  });

  test('re-importing clears canvas rows deleted on the source', () async {
    final src = AppDatabase.memory();
    final dst = AppDatabase.memory();
    addTearDown(src.close);
    addTearDown(dst.close);

    await src.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'Proj'));
    await src.canvasTemplatesDao.insertTemplate(
      CanvasTemplatesCompanion.insert(
          id: 't1', projectId: 'p1', templateType: 'swot', name: 'A',
          content: '{}'),
    );
    // First sync brings the template across.
    await JsonImporter.importFromString(
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src),
        dst);
    expect(await dst.canvasTemplatesDao.getTemplatesForProject('p1'),
        hasLength(1));

    // Delete on the source, then sync again — the destination must drop it.
    await src.canvasTemplatesDao.deleteTemplate('t1');
    await JsonImporter.importFromString(
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src),
        dst);
    expect(await dst.canvasTemplatesDao.getTemplatesForProject('p1'), isEmpty);
  });
}
