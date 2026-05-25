import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/shared/widgets/role_picker_field.dart';

Future<void> _project(AppDatabase db, String id) async {
  await db.projectDao.upsertProject(ProjectsCompanion.insert(
    id: id,
    name: 'Test',
  ));
}

Future<void> _person(
  AppDatabase db, {
  required String projectId,
  required String name,
  String? role,
}) async {
  await db.peopleDao.upsertPerson(PersonsCompanion.insert(
    id: 'p-$name',
    projectId: projectId,
    name: name,
    role: Value(role),
  ));
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() async => db.close());

  group('collectRoleSuggestions', () {
    test('empty project still returns scaffold roles', () async {
      const pid = 'p-empty';
      await _project(db, pid);
      final out = await collectRoleSuggestions(db: db, projectId: pid);
      expect(out, isNotEmpty);
      // Scaffold contains canonical PMI-style roles; ensure something familiar
      // is present without coupling to the full list.
      expect(out.map((r) => r.toLowerCase()),
          contains('programme sponsor'));
    });

    test('person.role values lead, scaffold follows', () async {
      const pid = 'p-roles';
      await _project(db, pid);
      await _person(db, projectId: pid, name: 'Alice', role: 'Tribe Lead');
      await _person(db, projectId: pid, name: 'Bob', role: 'Programme Sponsor');
      final out = await collectRoleSuggestions(db: db, projectId: pid);
      // Person-supplied custom role appears first.
      expect(out.first, 'Tribe Lead');
      // Then scaffold roles, deduped — the person-supplied 'Programme Sponsor'
      // should appear once, not twice.
      final pmCount = out
          .where((r) => r.toLowerCase() == 'programme sponsor')
          .length;
      expect(pmCount, 1);
    });

    test('dedupes case-insensitively across people', () async {
      const pid = 'p-dedup';
      await _project(db, pid);
      await _person(db, projectId: pid, name: 'Alice', role: 'BA');
      await _person(db, projectId: pid, name: 'Bob', role: 'ba');
      await _person(db, projectId: pid, name: 'Cara', role: 'Ba');
      final out = await collectRoleSuggestions(db: db, projectId: pid);
      final baCount = out.where((r) => r.toLowerCase() == 'ba').length;
      expect(baCount, 1);
      // Preserves the first-seen casing.
      expect(out.first, 'BA');
    });

    test('skips null and empty roles', () async {
      const pid = 'p-skip';
      await _project(db, pid);
      await _person(db, projectId: pid, name: 'Alice', role: null);
      await _person(db, projectId: pid, name: 'Bob', role: '');
      await _person(db, projectId: pid, name: 'Cara', role: '   ');
      final out = await collectRoleSuggestions(db: db, projectId: pid);
      // No spurious empty entries leaking through.
      expect(out.any((r) => r.trim().isEmpty), isFalse);
    });
  });
}
