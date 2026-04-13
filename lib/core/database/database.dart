import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'connection.dart';

part 'database.g.dart';
part 'daos/project_dao.dart';
part 'daos/programme_dao.dart';
part 'daos/raid_dao.dart';
part 'daos/decisions_dao.dart';
part 'daos/people_dao.dart';
part 'daos/actions_dao.dart';
part 'daos/inbox_dao.dart';
part 'daos/context_dao.dart';
part 'daos/reports_dao.dart';
part 'daos/journal_dao.dart';
part 'daos/workstreams_dao.dart';
part 'daos/glossary_dao.dart';
part 'daos/action_categories_dao.dart';
part 'daos/playbook_dao.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

class Projects extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get startDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ProgrammeOverviews extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get vision => text().nullable()();
  TextColumn get objectives => text().nullable()();
  TextColumn get scope => text().nullable()();
  TextColumn get outOfScope => text().nullable()();
  TextColumn get keyMilestones => text().nullable()();
  TextColumn get budget => text().nullable()();
  TextColumn get sponsor => text().nullable()();
  TextColumn get programmeManager => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Workstreams extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get name => text()();
  TextColumn get lane => text().withDefault(const Constant('General'))();
  TextColumn get lead => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('not_started'))();
  TextColumn get startDate => text().nullable()();
  TextColumn get endDate => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class WorkstreamLinks extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get fromId => text()();
  TextColumn get toId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class GovernanceCadences extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get meetingName => text()();
  TextColumn get frequency => text().nullable()();
  TextColumn get chair => text().nullable()();
  TextColumn get myRole => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Risks extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get ref => text().nullable()();
  TextColumn get description => text()();
  TextColumn get likelihood => text().withDefault(const Constant('medium'))();
  TextColumn get impact => text().withDefault(const Constant('medium'))();
  TextColumn get mitigation => text().nullable()();
  TextColumn get owner => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Assumptions extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get ref => text().nullable()();
  TextColumn get description => text()();
  TextColumn get owner => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get validatedBy => text().nullable()();
  DateTimeColumn get validatedAt => dateTime().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Issues extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get ref => text().nullable()();
  TextColumn get description => text()();
  TextColumn get owner => text().nullable()();
  TextColumn get dueDate => text().nullable()();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get resolution => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ProgramDependencies extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get ref => text().nullable()();
  TextColumn get description => text()();
  TextColumn get dependencyType => text().withDefault(const Constant('inbound'))();
  TextColumn get owner => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get dueDate => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Decisions extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get ref => text().nullable()();
  TextColumn get description => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get decisionMaker => text().nullable()();
  TextColumn get dueDate => text().nullable()();
  TextColumn get rationale => text().nullable()();
  TextColumn get outcome => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Persons extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  TextColumn get role => text().nullable()();
  TextColumn get organisation => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get teamsHandle => text().nullable()();
  TextColumn get personType =>
      text().withDefault(const Constant('stakeholder'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class StakeholderProfiles extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get personId => text().references(Persons, #id)();
  TextColumn get influence => text().nullable()();
  TextColumn get interest => text().nullable()();
  TextColumn get stance => text().nullable()();
  TextColumn get engagementStrategy => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ColleagueProfiles extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get personId => text().references(Persons, #id)();
  TextColumn get workingStyle => text().nullable()();
  TextColumn get preferences => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get team => text().nullable()();
  BoolColumn get directReport =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ActionCategories extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get name => text()();
  TextColumn get color => text()(); // hex e.g. '#8B5CF6'
  BoolColumn get isPreset => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class ProjectActions extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get ref => text().nullable()();
  TextColumn get description => text()();
  TextColumn get owner => text().nullable()();
  TextColumn get dueDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceNote => text().nullable()();
  TextColumn get outcome => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get recurrenceGroupId => text().nullable()();
  TextColumn get linkedActionId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class InboxItems extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get content => text()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get status => text().withDefault(const Constant('unprocessed'))();
  TextColumn get tags => text().nullable()();
  TextColumn get linkedItemId => text().nullable()();
  TextColumn get linkedItemType => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ContextEntries extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get entryType => text().withDefault(const Constant('observation'))();
  TextColumn get tags => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class GlossaryEntries extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  // 'system' or 'term'
  TextColumn get type => text().withDefault(const Constant('term'))();
  TextColumn get name => text()();
  TextColumn get acronym => text().nullable()();
  TextColumn get description => text().nullable()();
  // system-only fields
  TextColumn get owner => text().nullable()();
  TextColumn get environment => text().nullable()();
  TextColumn get status => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Documents extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get title => text()();
  TextColumn get content => text().nullable()();
  TextColumn get filePath => text().nullable()();
  TextColumn get documentType => text().nullable()();
  TextColumn get tags => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class JournalEntries extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get title => text().nullable()();
  TextColumn get body => text()();
  TextColumn get entryDate => text()();
  TextColumn get meetingContext => text().nullable()();
  BoolColumn get parsed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get confirmedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class JournalEntryLinks extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get entryId => text().references(JournalEntries, #id)();
  TextColumn get itemType => text()();
  TextColumn get itemId => text()();
  TextColumn get linkType => text().withDefault(const Constant('created'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class StatusReports extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get title => text()();
  TextColumn get period => text().nullable()();
  TextColumn get overallRag => text().withDefault(const Constant('green'))();
  TextColumn get summary => text().nullable()();
  TextColumn get accomplishments => text().nullable()();
  TextColumn get nextSteps => text().nullable()();
  TextColumn get risksHighlighted => text().nullable()();
  TextColumn get content => text().nullable()();
  DateTimeColumn get reportDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Playbook tables
// ---------------------------------------------------------------------------

class Organisations extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get shortName => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Playbooks extends Table {
  TextColumn get id => text()();
  TextColumn get organisationId => text().references(Organisations, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get version => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class PlaybookStages extends Table {
  TextColumn get id => text()();
  TextColumn get playbookId => text().references(Playbooks, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get approverRole => text().nullable()();
  TextColumn get gateCondition => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class StageTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get stageId => text().references(PlaybookStages, #id)();
  TextColumn get name => text()();
  TextColumn get filename => text()();
  TextColumn get filePath => text()();
  // docx | pdf | other
  TextColumn get fileType => text().withDefault(const Constant('other'))();
  // direct | companion
  TextColumn get fillStrategy => text().withDefault(const Constant('companion'))();
  TextColumn get fieldHints => text().nullable()(); // JSON
  DateTimeColumn get uploadedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ProjectPlaybooks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get playbookId => text().references(Playbooks, #id)();
  TextColumn get currentStageId => text().nullable()();
  DateTimeColumn get attachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ProjectStageProgresses extends Table {
  TextColumn get id => text()();
  TextColumn get projectPlaybookId =>
      text().references(ProjectPlaybooks, #id)();
  TextColumn get stageId => text().references(PlaybookStages, #id)();
  // not_started | in_progress | blocked | pending_approval | complete
  TextColumn get status =>
      text().withDefault(const Constant('not_started'))();
  BoolColumn get gateMet => boolean().withDefault(const Constant(false))();
  TextColumn get approvedBy => text().nullable()();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  TextColumn get approvalNotes => text().nullable()();
  TextColumn get evidenceFilename => text().nullable()();
  TextColumn get evidenceFilePath => text().nullable()();
  DateTimeColumn get evidenceUploadedAt => dateTime().nullable()();
  TextColumn get checklist => text().nullable()(); // JSON array
  TextColumn get generatedDocPath => text().nullable()();
  DateTimeColumn get generatedAt => dateTime().nullable()();
  TextColumn get journalEntryId => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(
  tables: [
    Projects,
    ProgrammeOverviews,
    Workstreams,
    WorkstreamLinks,
    GovernanceCadences,
    Risks,
    Assumptions,
    Issues,
    ProgramDependencies,
    Decisions,
    Persons,
    StakeholderProfiles,
    ColleagueProfiles,
    ActionCategories,
    ProjectActions,
    InboxItems,
    ContextEntries,
    GlossaryEntries,
    Documents,
    StatusReports,
    JournalEntries,
    JournalEntryLinks,
    Organisations,
    Playbooks,
    PlaybookStages,
    StageTemplates,
    ProjectPlaybooks,
    ProjectStageProgresses,
  ],
  daos: [
    ProjectDao,
    ProgrammeDao,
    RaidDao,
    DecisionsDao,
    PeopleDao,
    ActionCategoriesDao,
    ActionsDao,
    InboxDao,
    ContextDao,
    GlossaryDao,
    ReportsDao,
    JournalDao,
    WorkstreamsDao,
    PlaybookDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openAppConnection());
  AppDatabase.memory() : super(openMemoryConnection());

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(persons, persons.phone);
            await m.addColumn(persons, persons.teamsHandle);
            await m.addColumn(persons, persons.personType);
            await m.addColumn(colleagueProfiles, colleagueProfiles.team);
            await m.addColumn(
                colleagueProfiles, colleagueProfiles.directReport);
          }
          if (from < 3) {
            await m.addColumn(projects, projects.startDate);
          }
          if (from < 4) {
            await m.createTable(journalEntries);
            await m.createTable(journalEntryLinks);
          }
          if (from < 5) {
            await m.addColumn(workstreams, workstreams.lane);
            await m.addColumn(workstreams, workstreams.startDate);
            await m.addColumn(workstreams, workstreams.endDate);
            await m.createTable(workstreamLinks);
          }
          if (from < 6) {
            await m.createTable(glossaryEntries);
          }
          if (from < 7) {
            await m.createTable(actionCategories);
            await m.addColumn(projectActions, projectActions.categoryId);
            await m.addColumn(projectActions, projectActions.recurrenceGroupId);
            await m.addColumn(projectActions, projectActions.linkedActionId);
          }
          if (from < 8) {
            await m.addColumn(projectActions, projectActions.outcome);
          }
          if (from < 9) {
            await m.createTable(organisations);
            await m.createTable(playbooks);
            await m.createTable(playbookStages);
            await m.createTable(stageTemplates);
            await m.createTable(projectPlaybooks);
            await m.createTable(projectStageProgresses);
          }
        },
      );

  /// Emits once whenever any table in the database is written to.
  Stream<void> watchAnyChange() {
    return tableUpdates().map((_) => null);
  }

  /// Deletes a project and all its associated data across every table.
  Future<void> deleteProjectCascade(String projectId) async {
    await transaction(() async {
      await (delete(statusReports)..where((t) => t.projectId.equals(projectId))).go();
      // Delete journal entry links first (FK reference to journalEntries)
      final journalIds = await (select(journalEntries)
            ..where((t) => t.projectId.equals(projectId)))
          .map((e) => e.id)
          .get();
      if (journalIds.isNotEmpty) {
        await (delete(journalEntryLinks)
              ..where((t) => t.entryId.isIn(journalIds)))
            .go();
      }
      await (delete(journalEntries)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(contextEntries)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(glossaryEntries)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(inboxItems)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(actionCategories)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(projectActions)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(documents)..where((t) => t.projectId.equals(projectId))).go();
      // Profiles reference persons — delete profiles first
      final personIds = await (select(persons)
            ..where((t) => t.projectId.equals(projectId)))
          .map((p) => p.id)
          .get();
      if (personIds.isNotEmpty) {
        await (delete(stakeholderProfiles)
              ..where((t) => t.personId.isIn(personIds)))
            .go();
        await (delete(colleagueProfiles)
              ..where((t) => t.personId.isIn(personIds)))
            .go();
      }
      await (delete(persons)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(decisions)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(programDependencies)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(issues)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(assumptions)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(risks)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(governanceCadences)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(workstreams)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(programmeOverviews)..where((t) => t.projectId.equals(projectId))).go();
      // Playbook progress — delete stage progress before project_playbooks
      final ppIds = await (select(projectPlaybooks)
            ..where((t) => t.projectId.equals(projectId)))
          .map((p) => p.id)
          .get();
      if (ppIds.isNotEmpty) {
        await (delete(projectStageProgresses)
              ..where((t) => t.projectPlaybookId.isIn(ppIds)))
            .go();
      }
      await (delete(projectPlaybooks)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(projects)..where((t) => t.id.equals(projectId))).go();
    });
  }
}

// Connection is provided by the platform-conditional connection.dart module.
