import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';

const _projectId = 'p-test';

Future<void> _seedAction(
  AppDatabase db, {
  required String id,
  String? parentId,
  String status = 'open',
  bool isParent = false,
}) async {
  await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
    id: id,
    projectId: _projectId,
    description: id,
    status: Value(status),
    parentActionId: Value(parentId),
    isParent: Value(isParent),
  ));
}

Future<void> _patch(
        AppDatabase db, String id, ProjectActionsCompanion data) =>
    (db.update(db.projectActions)..where((t) => t.id.equals(id))).write(data);

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.into(db.projects).insert(ProjectsCompanion.insert(
          id: _projectId,
          name: 'Test Project',
        ));
  });

  tearDown(() => db.close());

  group('nestUnder', () {
    test('sets the parent and flags the target as a group parent', () async {
      await _seedAction(db, id: 'target');
      await _seedAction(db, id: 'dragged');

      await db.actionsDao.nestUnder('dragged', 'target');

      final actions = await db.actionsDao.getActionsForProject(_projectId);
      final byId = {for (final a in actions) a.id: a};
      expect(byId['dragged']!.parentActionId, 'target');
      expect(byId['target']!.isParent, isTrue);
    });
  });

  group('setIsParent', () {
    test('toggles the flag', () async {
      await _seedAction(db, id: 'a');
      await db.actionsDao.setIsParent('a', true);
      expect(
          (await db.actionsDao.getActionById('a'))!.isParent, isTrue);
      await db.actionsDao.setIsParent('a', false);
      expect(
          (await db.actionsDao.getActionById('a'))!.isParent, isFalse);
    });
  });

  group('closeActions', () {
    test('closes every open action in the id list', () async {
      await _seedAction(db, id: 'root', isParent: true);
      await _seedAction(db, id: 'task', parentId: 'root');
      await _seedAction(db, id: 'sub', parentId: 'task', status: 'closed');
      await _seedAction(db, id: 'unrelated');

      await db.actionsDao.closeActions(['root', 'task', 'sub']);

      final actions = await db.actionsDao.getActionsForProject(_projectId);
      final byId = {for (final a in actions) a.id: a};
      expect(byId['root']!.status, 'closed');
      expect(byId['task']!.status, 'closed');
      expect(byId['sub']!.status, 'closed');
      expect(byId['unrelated']!.status, 'open');
    });

    test('leaves already-closed rows untouched (no updatedAt churn)',
        () async {
      await _seedAction(db, id: 'done', status: 'closed');
      final before =
          (await db.actionsDao.getActionById('done'))!.updatedAt;
      await db.actionsDao.closeActions(['done']);
      final after =
          (await db.actionsDao.getActionById('done'))!.updatedAt;
      expect(after, before);
    });
  });

  group('setStatus', () {
    test('round-trips a sub-task between closed and open', () async {
      await _seedAction(db, id: 'sub');
      await db.actionsDao.setStatus('sub', 'closed');
      expect((await db.actionsDao.getActionById('sub'))!.status, 'closed');
      await db.actionsDao.setStatus('sub', 'open');
      expect((await db.actionsDao.getActionById('sub'))!.status, 'open');
    });
  });

  group('nextRef', () {
    test('starts at AC1 and continues from the highest existing number',
        () async {
      expect(ActionsDao.nextRef(const []), 'AC1');
      await _seedAction(db, id: 'a');
      await _patch(db, 'a', const ProjectActionsCompanion(ref: Value('AC7')));
      await _seedAction(db, id: 'b');
      await _patch(db, 'b', const ProjectActionsCompanion(ref: Value('AC3')));
      final all = await db.actionsDao.getActionsForProject(_projectId);
      expect(ActionsDao.nextRef(all), 'AC8');
    });
  });

  group('addSubTask', () {
    test('creates an open child under the parent and flags it as a group',
        () async {
      await _seedAction(db, id: 'parent');
      await _patch(
          db,
          'parent',
          const ProjectActionsCompanion(
              ref: Value('AC4'),
              categoryId: Value('cat-x'),
              planActivityId: Value('act-y')));

      final id = await db.actionsDao.addSubTask(
          id: 'child', parentId: 'parent', description: 'Draft the memo');

      expect(id, 'child');
      final child = (await db.actionsDao.getActionById('child'))!;
      expect(child.parentActionId, 'parent');
      expect(child.description, 'Draft the memo');
      expect(child.status, 'open');
      expect(child.ref, 'AC5');
      expect(child.isParent, isFalse);
      // Inherits the grouping context so it lands in the same swimlane
      // and plan link as its parent.
      expect(child.categoryId, 'cat-x');
      expect(child.planActivityId, 'act-y');
      expect((await db.actionsDao.getActionById('parent'))!.isParent, isTrue);
    });

    test('refs keep climbing across successive quick-adds', () async {
      await _seedAction(db, id: 'parent');
      await db.actionsDao.addSubTask(
          id: 'c1', parentId: 'parent', description: 'one');
      await db.actionsDao.addSubTask(
          id: 'c2', parentId: 'parent', description: 'two');
      final c1 = (await db.actionsDao.getActionById('c1'))!;
      final c2 = (await db.actionsDao.getActionById('c2'))!;
      expect(c1.ref, isNot(c2.ref));
    });

    test('a task (child of a top-level action) may hold sub-tasks',
        () async {
      await _seedAction(db, id: 'root', isParent: true);
      await _seedAction(db, id: 'task', parentId: 'root');
      final id = await db.actionsDao.addSubTask(
          id: 'sub', parentId: 'task', description: 'leaf');
      expect(id, 'sub');
      expect((await db.actionsDao.getActionById('task'))!.isParent, isTrue);
    });

    test('a sub-task (depth 2) refuses children — hierarchy is capped',
        () async {
      await _seedAction(db, id: 'root', isParent: true);
      await _seedAction(db, id: 'task', parentId: 'root', isParent: true);
      await _seedAction(db, id: 'sub', parentId: 'task');
      final id = await db.actionsDao.addSubTask(
          id: 'too-deep', parentId: 'sub', description: 'nope');
      expect(id, isNull);
      expect(await db.actionsDao.getActionById('too-deep'), isNull);
      expect((await db.actionsDao.getActionById('sub'))!.isParent, isFalse);
    });

    test('unknown parent returns null and writes nothing', () async {
      final id = await db.actionsDao.addSubTask(
          id: 'x', parentId: 'ghost', description: 'nope');
      expect(id, isNull);
      expect(await db.actionsDao.getActionsForProject(_projectId), isEmpty);
    });
  });
}
