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
part 'daos/stakeholder_role_dao.dart';
part 'daos/team_role_dao.dart';
part 'daos/milestones_dao.dart';
part 'daos/workstream_activities_dao.dart';
part 'daos/programme_gantt_dao.dart';
part 'daos/status_snapshot_dao.dart';
part 'daos/project_charter_dao.dart';
part 'daos/programme_overview_state_dao.dart';

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

class StakeholderRoles extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get roleName => text()();
  // accountable | active | affected
  TextColumn get roleType => text()();
  TextColumn get personId => text().nullable()();
  BoolColumn get isScaffold => boolean().withDefault(const Constant(true))();
  BoolColumn get isApplicable => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  // Stakeholder map enhancements
  TextColumn get functionalArea => text().nullable()();
  TextColumn get integrationRelevance => text().nullable()();
  // critical | high | medium | low
  TextColumn get priority => text().nullable()();
  // not_started | engaged | gap_action_required | not_engaged | complete
  TextColumn get engagementStatus => text().nullable()();
  BoolColumn get gapFlag => boolean().withDefault(const Constant(false))();
  TextColumn get gapDescription => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TeamRoles extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get roleName => text()();
  // programme_leadership | business_analysis | technology | specialist | governance
  TextColumn get teamGroup => text()();
  TextColumn get personId => text().nullable()();
  BoolColumn get isScaffold => boolean().withDefault(const Constant(true))();
  BoolColumn get isApplicable => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Milestones extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get name => text()();
  TextColumn get date => text()(); // ISO date string YYYY-MM-DD
  TextColumn get ownerId => text().nullable()(); // FK → Persons (nullable)
  // upcoming | achieved | at_risk | missed
  TextColumn get status => text().withDefault(const Constant('upcoming'))();
  BoolColumn get isHardDeadline => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  TextColumn get workstreamId => text().nullable()(); // FK → Workstreams (nullable)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class WorkstreamActivities extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get workstreamId => text().references(Workstreams, #id)();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get name => text()();
  TextColumn get startDate => text()(); // ISO date string
  TextColumn get endDate => text()(); // ISO date string
  TextColumn get ownerId => text().nullable()(); // FK → Persons (nullable)
  // not_started | in_progress | complete | blocked
  TextColumn get status => text().withDefault(const Constant('not_started'))();
  TextColumn get notes => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
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
// Timeline v2 — Programme Gantt tables
// ---------------------------------------------------------------------------

class TimelineWorkPackages extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get name => text()();
  TextColumn get shortCode => text().nullable()();
  TextColumn get description => text().nullable()();
  // wp1 | wp2 | wp3 | wp4 | mpower | governance | custom
  TextColumn get colourTheme =>
      text().withDefault(const Constant('wp1'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  // green | amber | red | not_started
  TextColumn get ragStatus =>
      text().withDefault(const Constant('not_started'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TimelineActivities extends Table {
  TextColumn get id => text()();
  TextColumn get workPackageId =>
      text().references(TimelineWorkPackages, #id)();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get name => text()();
  TextColumn get owner => text().nullable()();
  TextColumn get ownerId => text().nullable()(); // FK → Persons (nullable)
  // activity | milestone | hard_deadline | dependency_marker | ongoing | gate
  TextColumn get activityType =>
      text().withDefault(const Constant('activity'))();
  IntColumn get startMonth => integer().nullable()();
  IntColumn get endMonth => integer().nullable()();
  TextColumn get startDate => text().nullable()();
  TextColumn get endDate => text().nullable()();
  // not_started | on_track | at_risk | complete | overdue
  TextColumn get status =>
      text().withDefault(const Constant('not_started'))();
  BoolColumn get isCritical =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isBaseline =>
      boolean().withDefault(const Constant(false))();
  IntColumn get baselineStart => integer().nullable()();
  IntColumn get baselineEnd => integer().nullable()();
  TextColumn get cellLabel => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TimelineDependencies extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get fromActivityId => text()();
  TextColumn get toActivityId => text()();
  // finish_to_start | start_to_start | finish_to_finish | external
  TextColumn get dependencyType =>
      text().withDefault(const Constant('finish_to_start'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ProgrammeHeaders extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()(); // one per project
  TextColumn get title => text().nullable()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get hardDeadline => text().nullable()();
  TextColumn get inScope => text().nullable()();
  TextColumn get outOfScope => text().nullable()();
  TextColumn get monthLabels => text().nullable()(); // JSON array of strings
  TextColumn get month0Date => text().nullable()(); // ISO date YYYY-MM-DD
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ProjectScopes extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get inScopeItems => text().nullable()(); // JSON array
  TextColumn get outOfScope => text().nullable()(); // JSON array of strings
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class IntegrationDomains extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get priority => text().nullable()();
  TextColumn get domain => text()();
  TextColumn get likelySystems => text().nullable()();
  TextColumn get prioritySignal => text().nullable()();
  // not_started | in_progress | complete | at_risk
  TextColumn get status =>
      text().withDefault(const Constant('not_started'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class PrioritisationSources extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get sourceName => text()();
  TextColumn get inputType => text().nullable()();
  TextColumn get owner => text().nullable()();
  TextColumn get mechanism => text().nullable()();
  TextColumn get weight => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Status snapshots
// ---------------------------------------------------------------------------

class StatusSnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  // Monday of the week this snapshot covers
  DateTimeColumn get weekEnding => dateTime()();
  // green | amber | red
  TextColumn get programmeRag => text()();
  // JSON map: {wp_id: rag_value}
  TextColumn get workstreamRag => text().withDefault(const Constant('{}'))();
  IntColumn get overdueActionsCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get openActionsCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get pendingDecisionsCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get openRisksCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Charter
// ---------------------------------------------------------------------------

class ProjectCharters extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get vision => text().nullable()();
  TextColumn get objectives => text().nullable()();
  TextColumn get scopeIn => text().nullable()();
  TextColumn get scopeOut => text().nullable()();
  TextColumn get deliveryApproach => text().nullable()();
  TextColumn get successCriteria => text().nullable()();
  TextColumn get keyConstraints => text().nullable()();
  TextColumn get assumptions => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Programme Overview state (cached RAG + narrative)
// ---------------------------------------------------------------------------

class ProgrammeOverviewStates extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  // green | amber | red — null means use computed value
  TextColumn get cachedRag => text().nullable()();
  TextColumn get cachedNarrative => text().nullable()();
  DateTimeColumn get narrativeGeneratedAt => dateTime().nullable()();
  TextColumn get narrativeManualOverride => text().nullable()();
  // green | amber | red — explicit PM override, null = auto
  TextColumn get ragManualOverride => text().nullable()();
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
    StakeholderRoles,
    TeamRoles,
    Milestones,
    WorkstreamActivities,
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
    TimelineWorkPackages,
    TimelineActivities,
    TimelineDependencies,
    ProgrammeHeaders,
    ProjectScopes,
    IntegrationDomains,
    PrioritisationSources,
    StatusSnapshots,
    ProjectCharters,
    ProgrammeOverviewStates,
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
    StakeholderRoleDao,
    TeamRoleDao,
    MilestonesDao,
    WorkstreamActivitiesDao,
    ProgrammeGanttDao,
    StatusSnapshotDao,
    ProjectCharterDao,
    ProgrammeOverviewStateDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openAppConnection());
  AppDatabase.memory() : super(openMemoryConnection());

  @override
  int get schemaVersion => 16;

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
          if (from < 10) {
            await m.createTable(stakeholderRoles);
            await m.createTable(teamRoles);
          }
          if (from < 11) {
            await m.createTable(milestones);
            await m.createTable(workstreamActivities);
          }
          if (from < 12) {
            await m.createTable(timelineWorkPackages);
            await m.createTable(timelineActivities);
            await m.createTable(timelineDependencies);
            await m.createTable(programmeHeaders);
            await m.createTable(projectScopes);
            await m.createTable(integrationDomains);
            await m.createTable(prioritisationSources);
          }
          if (from < 13) {
            await m.addColumn(timelineActivities, timelineActivities.status);
          }
          if (from < 14) {
            await m.addColumn(stakeholderRoles, stakeholderRoles.functionalArea);
            await m.addColumn(stakeholderRoles, stakeholderRoles.integrationRelevance);
            await m.addColumn(stakeholderRoles, stakeholderRoles.priority);
            await m.addColumn(stakeholderRoles, stakeholderRoles.engagementStatus);
            await m.addColumn(stakeholderRoles, stakeholderRoles.gapFlag);
            await m.addColumn(stakeholderRoles, stakeholderRoles.gapDescription);
          }
          if (from < 15) {
            await m.createTable(statusSnapshots);
          }
          if (from < 16) {
            await m.createTable(projectCharters);
            await m.createTable(programmeOverviewStates);
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
      await (delete(stakeholderRoles)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(teamRoles)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(decisions)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(programDependencies)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(issues)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(assumptions)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(risks)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(governanceCadences)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(milestones)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(workstreamActivities)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(workstreams)..where((t) => t.projectId.equals(projectId))).go();
      // Timeline v2
      await (delete(timelineDependencies)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(timelineActivities)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(timelineWorkPackages)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(programmeHeaders)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(projectScopes)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(integrationDomains)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(prioritisationSources)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(statusSnapshots)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(projectCharters)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(programmeOverviewStates)..where((t) => t.projectId.equals(projectId))).go();
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
