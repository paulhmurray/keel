part of '../database.dart';

@DriftAccessor(tables: [Persons, StakeholderProfiles, ColleagueProfiles])
class PeopleDao extends DatabaseAccessor<AppDatabase> with _$PeopleDaoMixin {
  PeopleDao(super.db);

  // ---- Persons ----

  Stream<List<Person>> watchPersonsForProject(String projectId) {
    return (select(persons)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Stream<List<Person>> watchPersonsByType(String projectId, String personType) {
    return (select(persons)
          ..where((t) =>
              t.projectId.equals(projectId) & t.personType.equals(personType))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<List<Person>> getPersonsForProject(String projectId) {
    return (select(persons)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<Person?> getPersonById(String id) {
    return (select(persons)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertPerson(PersonsCompanion entry) {
    return into(persons).insert(entry);
  }

  Future<bool> updatePerson(PersonsCompanion entry) {
    return update(persons).replace(entry);
  }

  Future<int> deletePerson(String id) {
    return (delete(persons)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertPerson(PersonsCompanion entry) {
    return into(persons).insertOnConflictUpdate(entry);
  }

  // ---- StakeholderProfiles ----

  Stream<List<StakeholderProfile>> watchStakeholdersForProject(
      String projectId) {
    return (select(stakeholderProfiles)
          ..where((t) => t.projectId.equals(projectId)))
        .watch();
  }

  Future<List<StakeholderProfile>> getStakeholdersForProject(String projectId) {
    return (select(stakeholderProfiles)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
  }

  Future<StakeholderProfile?> getStakeholderById(String id) {
    return (select(stakeholderProfiles)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<StakeholderProfile?> getStakeholderByPersonId(String personId) {
    return (select(stakeholderProfiles)
          ..where((t) => t.personId.equals(personId)))
        .getSingleOrNull();
  }

  Future<void> insertStakeholder(StakeholderProfilesCompanion entry) {
    return into(stakeholderProfiles).insert(entry);
  }

  Future<bool> updateStakeholder(StakeholderProfilesCompanion entry) {
    return update(stakeholderProfiles).replace(entry);
  }

  Future<int> deleteStakeholder(String id) {
    return (delete(stakeholderProfiles)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertStakeholder(StakeholderProfilesCompanion entry) {
    return into(stakeholderProfiles).insertOnConflictUpdate(entry);
  }

  // ---- ColleagueProfiles ----

  Stream<List<ColleagueProfile>> watchColleaguesForProject(String projectId) {
    return (select(colleagueProfiles)
          ..where((t) => t.projectId.equals(projectId)))
        .watch();
  }

  Future<List<ColleagueProfile>> getColleaguesForProject(String projectId) {
    return (select(colleagueProfiles)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
  }

  Future<ColleagueProfile?> getColleagueById(String id) {
    return (select(colleagueProfiles)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<ColleagueProfile?> getColleagueByPersonId(String personId) {
    return (select(colleagueProfiles)
          ..where((t) => t.personId.equals(personId)))
        .getSingleOrNull();
  }

  Future<void> insertColleague(ColleagueProfilesCompanion entry) {
    return into(colleagueProfiles).insert(entry);
  }

  Future<bool> updateColleague(ColleagueProfilesCompanion entry) {
    return update(colleagueProfiles).replace(entry);
  }

  Future<int> deleteColleague(String id) {
    return (delete(colleagueProfiles)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertColleague(ColleagueProfilesCompanion entry) {
    return into(colleagueProfiles).insertOnConflictUpdate(entry);
  }
}
