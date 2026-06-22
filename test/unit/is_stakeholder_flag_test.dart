import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertProject(String id, String name) {
    return db.projectDao.insertProject(
      ProjectsCompanion.insert(id: id, name: name),
    );
  }

  Future<void> insertPerson(
    String id,
    String projectId,
    String name, {
    String personType = 'colleague',
    bool isStakeholder = false,
  }) {
    return db.peopleDao.insertPerson(PersonsCompanion.insert(
      id: id,
      projectId: projectId,
      name: name,
      personType: Value(personType),
      isStakeholder: Value(isStakeholder),
    ));
  }

  group('PeopleDao.watchStakeholderPersons', () {
    test('returns only people flagged as stakeholders, across categories',
        () async {
      await insertProject('p', 'P');
      await insertPerson('a', 'p', 'Alice (colleague + stakeholder)',
          personType: 'colleague', isStakeholder: true);
      await insertPerson('b', 'p', 'Bob (colleague, not stakeholder)',
          personType: 'colleague', isStakeholder: false);
      await insertPerson('c', 'p', 'Carol (exec + stakeholder)',
          personType: 'exec', isStakeholder: true);
      await insertPerson('d', 'p', 'Dave (vendor + stakeholder)',
          personType: 'vendor', isStakeholder: true);
      await insertPerson('e', 'p', 'Eve (exec, not stakeholder)',
          personType: 'exec', isStakeholder: false);

      final stakeholders =
          await db.peopleDao.watchStakeholderPersons('p').first;

      expect(stakeholders.map((p) => p.id).toSet(), {'a', 'c', 'd'});
      // Category info is preserved on returned rows — it's still the source
      // of truth for which tab the person appears under.
      expect(
        stakeholders.map((p) => '${p.id}:${p.personType}').toSet(),
        {'a:colleague', 'c:exec', 'd:vendor'},
      );
    });

    test('scopes to the requested project', () async {
      await insertProject('p1', 'One');
      await insertProject('p2', 'Two');
      await insertPerson('s1', 'p1', 'P1 stakeholder',
          personType: 'colleague', isStakeholder: true);
      await insertPerson('s2', 'p2', 'P2 stakeholder',
          personType: 'colleague', isStakeholder: true);

      final p1 = await db.peopleDao.watchStakeholderPersons('p1').first;
      expect(p1.map((p) => p.id), ['s1']);
    });
  });

  group('AppDatabase.copyPeopleToProject — isStakeholder preservation', () {
    test('copies the isStakeholder flag onto the new rows', () async {
      await insertProject('src', 'Source');
      await insertProject('dst', 'Target');
      await insertPerson('p1', 'src', 'Stake-Colleague',
          personType: 'colleague', isStakeholder: true);
      await insertPerson('p2', 'src', 'Plain-Colleague',
          personType: 'colleague', isStakeholder: false);
      await insertPerson('p3', 'src', 'Stake-Exec',
          personType: 'exec', isStakeholder: true);

      await db.copyPeopleToProject(
        sourceProjectId: 'src',
        targetProjectId: 'dst',
      );

      final dst = await db.peopleDao.getPersonsForProject('dst');
      final byName = {for (final p in dst) p.name: p};
      expect(byName['Stake-Colleague']!.isStakeholder, isTrue);
      expect(byName['Plain-Colleague']!.isStakeholder, isFalse);
      expect(byName['Stake-Exec']!.isStakeholder, isTrue);
      expect(byName['Stake-Exec']!.personType, 'exec');
    });
  });

  group('v25→v26 migration logic', () {
    // The migration runs a single UPDATE that splits the legacy
    // person_type='stakeholder' value into person_type='colleague' +
    // is_stakeholder=true. We exercise that SQL directly against a fresh
    // memory DB so the conversion behaviour is locked in.
    test("converts legacy personType='stakeholder' rows correctly",
        () async {
      await insertProject('p', 'P');
      // Sneak a legacy-typed row in by hand. (The Flutter form layer no
      // longer surfaces 'stakeholder' as a category, but on-disk values from
      // pre-v26 databases will look like this.)
      await insertPerson('legacy', 'p', 'Old Stakeholder',
          personType: 'stakeholder', isStakeholder: false);
      // Sanity untouched.
      await insertPerson('untouched', 'p', 'Existing Vendor',
          personType: 'vendor', isStakeholder: false);

      await db.customStatement(
        "UPDATE persons SET person_type = 'colleague', "
        "is_stakeholder = 1 WHERE person_type = 'stakeholder'",
      );

      final all = await db.peopleDao.getPersonsForProject('p');
      final byId = {for (final p in all) p.id: p};
      expect(byId['legacy']!.personType, 'colleague');
      expect(byId['legacy']!.isStakeholder, isTrue);
      expect(byId['untouched']!.personType, 'vendor');
      expect(byId['untouched']!.isStakeholder, isFalse);
    });
  });
}
