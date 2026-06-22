import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/providers/project_provider.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
  });

  tearDown(() async => db.close());

  group('Projects.kind column', () {
    test('newly-inserted row defaults to kind=project', () async {
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'Alpha'));
      final p = (await db.projectDao.getAllProjects()).single;
      expect(p.kind, 'project');
      expect(p.parentProgrammeId, isNull);
    });

    test('explicit kind=programme persists and reads back', () async {
      await db.projectDao.insertProject(
        ProjectsCompanion.insert(
          id: 'prog1',
          name: 'Big Programme',
          kind: const Value('programme'),
        ),
      );
      final p = (await db.projectDao.getAllProjects()).single;
      expect(p.kind, 'programme');
    });

    test('parentProgrammeId is nullable text — round-trips when set',
        () async {
      await db.projectDao.insertProject(
        ProjectsCompanion.insert(
          id: 'prog',
          name: 'Programme',
          kind: const Value('programme'),
        ),
      );
      await db.projectDao.insertProject(
        ProjectsCompanion.insert(
          id: 'child',
          name: 'Linked project',
          parentProgrammeId: const Value('prog'),
        ),
      );
      final child = (await db.projectDao.getAllProjects())
          .firstWhere((p) => p.id == 'child');
      expect(child.parentProgrammeId, 'prog');
    });
  });

  group('ProjectProvider.isProgramme + kind splits', () {
    test('isProgramme reflects the selected project\'s kind', () async {
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p', name: 'Proj'));
      await db.projectDao.insertProject(
        ProjectsCompanion.insert(
          id: 'g',
          name: 'Prog',
          kind: const Value('programme'),
        ),
      );
      final provider = ProjectProvider(db);
      // Wait a microtask for the async load to land.
      await Future<void>.delayed(Duration.zero);

      // Pick the project — isProgramme false.
      provider.selectProjectById('p');
      expect(provider.isProgramme, isFalse);

      // Switch to the programme — isProgramme true.
      provider.selectProjectById('g');
      expect(provider.isProgramme, isTrue);

      provider.dispose();
    });

    test(
        'projectsOnly / programmesOnly split the active project list '
        'by kind', () async {
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P1'));
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p2', name: 'P2'));
      await db.projectDao.insertProject(
        ProjectsCompanion.insert(
          id: 'g1',
          name: 'G1',
          kind: const Value('programme'),
        ),
      );
      final provider = ProjectProvider(db);
      await Future<void>.delayed(Duration.zero);
      expect(provider.projectsOnly.map((p) => p.id), {'p1', 'p2'});
      expect(provider.programmesOnly.map((p) => p.id), {'g1'});
      provider.dispose();
    });

    test('createProgramme stamps kind=programme', () async {
      final provider = ProjectProvider(db);
      await Future<void>.delayed(Duration.zero);
      await provider.createProgramme('TPM Programme');
      await Future<void>.delayed(Duration.zero);
      final rows = await db.projectDao.getAllProjects();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'TPM Programme');
      expect(rows.single.kind, 'programme');
      provider.dispose();
    });

    test(
        'createProject with kind=project (default) and copyPeople from '
        'a programme works — people inheritance is kind-agnostic',
        () async {
      // Seed a programme + people.
      await db.projectDao.insertProject(ProjectsCompanion.insert(
        id: 'prog',
        name: 'Source Programme',
        kind: const Value('programme'),
      ));
      await db.peopleDao.insertPerson(PersonsCompanion.insert(
        id: 'person-1',
        projectId: 'prog',
        name: 'Anna',
      ));

      final provider = ProjectProvider(db);
      await Future<void>.delayed(Duration.zero);
      await provider.createProject(
        'Inheritor',
        copyPeopleFromProjectId: 'prog',
      );
      await Future<void>.delayed(Duration.zero);

      final inheritor = (await db.projectDao.getAllProjects())
          .firstWhere((p) => p.name == 'Inheritor');
      final inheritedPeople =
          await db.peopleDao.getPersonsForProject(inheritor.id);
      expect(inheritedPeople.map((p) => p.name), contains('Anna'));
      provider.dispose();
    });

    test('createProgramme copying people from a project works too',
        () async {
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p', name: 'Source'));
      await db.peopleDao.insertPerson(PersonsCompanion.insert(
        id: 'person-1',
        projectId: 'p',
        name: 'Bart',
      ));

      final provider = ProjectProvider(db);
      await Future<void>.delayed(Duration.zero);
      await provider.createProgramme(
        'New Prog',
        copyPeopleFromProjectId: 'p',
      );
      await Future<void>.delayed(Duration.zero);

      final prog = (await db.projectDao.getAllProjects())
          .firstWhere((p) => p.name == 'New Prog');
      expect(prog.kind, 'programme');
      final peeps = await db.peopleDao.getPersonsForProject(prog.id);
      expect(peeps.map((p) => p.name), contains('Bart'));
      provider.dispose();
    });
  });
}
