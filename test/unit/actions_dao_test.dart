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
}
