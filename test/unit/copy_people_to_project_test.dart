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
    String personType = 'stakeholder',
    String? email,
  }) {
    return db.peopleDao.insertPerson(PersonsCompanion.insert(
      id: id,
      projectId: projectId,
      name: name,
      email: Value(email),
      personType: Value(personType),
    ));
  }

  group('AppDatabase.copyPeopleToProject', () {
    test('copies persons of every type into the target project', () async {
      await insertProject('src', 'Source');
      await insertProject('dst', 'Target');
      await insertPerson('p1', 'src', 'Alice', personType: 'stakeholder');
      await insertPerson('p2', 'src', 'Bob', personType: 'colleague');
      await insertPerson('p3', 'src', 'Carol', personType: 'exec');
      await insertPerson('p4', 'src', 'Dave', personType: 'vendor');

      await db.copyPeopleToProject(
        sourceProjectId: 'src',
        targetProjectId: 'dst',
      );

      final dstPeople = await db.peopleDao.getPersonsForProject('dst');
      expect(dstPeople, hasLength(4));
      expect(
        dstPeople.map((p) => p.personType).toSet(),
        {'stakeholder', 'colleague', 'exec', 'vendor'},
      );
      // Names preserved.
      expect(
        dstPeople.map((p) => p.name).toSet(),
        {'Alice', 'Bob', 'Carol', 'Dave'},
      );
      // New ids, not the originals.
      expect(
        dstPeople.map((p) => p.id).toSet().intersection(
              {'p1', 'p2', 'p3', 'p4'},
            ),
        isEmpty,
      );
    });

    test('leaves the source project untouched', () async {
      await insertProject('src', 'Source');
      await insertProject('dst', 'Target');
      await insertPerson('p1', 'src', 'Alice');

      await db.copyPeopleToProject(
        sourceProjectId: 'src',
        targetProjectId: 'dst',
      );

      final srcPeople = await db.peopleDao.getPersonsForProject('src');
      expect(srcPeople, hasLength(1));
      expect(srcPeople.first.id, 'p1');
      expect(srcPeople.first.name, 'Alice');
    });

    test('rewrites personId FKs on stakeholder profiles', () async {
      await insertProject('src', 'Source');
      await insertProject('dst', 'Target');
      await insertPerson('p1', 'src', 'Alice');
      await db.peopleDao.insertStakeholder(StakeholderProfilesCompanion.insert(
        id: 'sp1',
        projectId: 'src',
        personId: 'p1',
        influence: const Value('high'),
        interest: const Value('high'),
      ));

      await db.copyPeopleToProject(
        sourceProjectId: 'src',
        targetProjectId: 'dst',
      );

      final dstPeople = await db.peopleDao.getPersonsForProject('dst');
      final newAlice = dstPeople.firstWhere((p) => p.name == 'Alice');
      final dstSps = await db.peopleDao.getStakeholdersForProject('dst');
      expect(dstSps, hasLength(1));
      expect(dstSps.first.personId, newAlice.id);
      expect(dstSps.first.influence, 'high');
      expect(dstSps.first.id, isNot('sp1'));
    });

    test('copies stakeholder and team roles, preserving nullable personId',
        () async {
      await insertProject('src', 'Source');
      await insertProject('dst', 'Target');
      await insertPerson('p1', 'src', 'Alice');
      // Assigned role.
      await db.stakeholderRoleDao.upsert(StakeholderRolesCompanion.insert(
        id: 'sr1',
        projectId: 'src',
        roleName: 'Sponsor',
        roleType: 'accountable',
        personId: const Value('p1'),
        sortOrder: const Value(1),
      ));
      // Unassigned (scaffold) role.
      await db.stakeholderRoleDao.upsert(StakeholderRolesCompanion.insert(
        id: 'sr2',
        projectId: 'src',
        roleName: 'Steering Committee',
        roleType: 'accountable',
        sortOrder: const Value(2),
      ));
      await db.teamRoleDao.upsert(TeamRolesCompanion.insert(
        id: 'tr1',
        projectId: 'src',
        roleName: 'BA Lead',
        teamGroup: 'business_analysis',
        personId: const Value('p1'),
      ));

      await db.copyPeopleToProject(
        sourceProjectId: 'src',
        targetProjectId: 'dst',
      );

      final dstPeople = await db.peopleDao.getPersonsForProject('dst');
      final newAliceId = dstPeople.firstWhere((p) => p.name == 'Alice').id;

      final dstSrs = await db.stakeholderRoleDao.getForProject('dst');
      expect(dstSrs, hasLength(2));
      final sponsor = dstSrs.firstWhere((r) => r.roleName == 'Sponsor');
      expect(sponsor.personId, newAliceId);
      final unassigned =
          dstSrs.firstWhere((r) => r.roleName == 'Steering Committee');
      expect(unassigned.personId, isNull);

      final dstTrs = await db.teamRoleDao.getForProject('dst');
      expect(dstTrs, hasLength(1));
      expect(dstTrs.first.personId, newAliceId);
      expect(dstTrs.first.teamGroup, 'business_analysis');
    });

    test('copies colleague profiles with rewritten FK', () async {
      await insertProject('src', 'Source');
      await insertProject('dst', 'Target');
      await insertPerson('p1', 'src', 'Bob', personType: 'colleague');
      await db.peopleDao.insertColleague(ColleagueProfilesCompanion.insert(
        id: 'cp1',
        projectId: 'src',
        personId: 'p1',
        workingStyle: const Value('async-first'),
        directReport: const Value(true),
      ));

      await db.copyPeopleToProject(
        sourceProjectId: 'src',
        targetProjectId: 'dst',
      );

      final dstPeople = await db.peopleDao.getPersonsForProject('dst');
      final newBobId = dstPeople.firstWhere((p) => p.name == 'Bob').id;
      final dstCps = await db.peopleDao.getColleaguesForProject('dst');
      expect(dstCps, hasLength(1));
      expect(dstCps.first.personId, newBobId);
      expect(dstCps.first.workingStyle, 'async-first');
      expect(dstCps.first.directReport, isTrue);
    });
  });
}
