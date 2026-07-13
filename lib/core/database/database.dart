import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'connection.dart';

part 'database.g.dart';
part 'daos/project_dao.dart';
part 'daos/programme_dao.dart';
part 'daos/programme_links_dao.dart';
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
part 'daos/action_comments_dao.dart';
part 'daos/journal_series_dao.dart';
part 'daos/canvas_cards_dao.dart';
part 'daos/canvas_templates_dao.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

class Projects extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get startDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  // Distinguishes a regular project from a programme. Programmes have
  // the same surfaces but bespoke UI in places (status reports show
  // project RAGs, charter lists linked projects, etc.) and accept
  // cascaded items from linked child projects.
  //   'project'   — default for existing rows
  //   'programme' — manages a portfolio of linked projects
  TextColumn get kind =>
      text().withDefault(const Constant('project'))();
  // Set on a project row to indicate which programme it cascades up to.
  // Always null for programme-kind rows. Populated in Phase B when the
  // linking flow lands.
  TextColumn get parentProgrammeId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// One side of a programme ↔ project link. Each side of a link stores
/// its own row pointing at the shared [code]. On a single-machine
/// install (programme + project both local), one logical link is two
/// rows in the same DB — [partnerLocalId] is populated and the link
/// activates as soon as the second side redeems the code. On a
/// multi-machine install, only the local side has a row until the
/// server-side handshake lands (Phase C); the row sits at
/// `status='pending_remote'` until then.
class ProgrammeLinks extends Table {
  TextColumn get id => text()();
  // The local entity (this side of the link) — a project or programme
  // row on this machine.
  TextColumn get ownerEntityId => text().references(Projects, #id)();
  TextColumn get ownerKind => text()(); // 'project' | 'programme'
  // The partner kind is the opposite of [ownerKind]. Stored explicitly
  // so a programme row can quickly enumerate its linked projects (and
  // vice versa) without a JOIN on Projects.
  TextColumn get partnerKind => text()(); // 'project' | 'programme'
  // Cached partner name for display when the partner is remote and we
  // don't have a row to read from.
  TextColumn get partnerName => text().nullable()();
  // Populated when the partner exists on this machine — the project or
  // programme row's id. Null while we're waiting for the other machine
  // to redeem the code.
  TextColumn get partnerLocalId => text().nullable()();
  // Shared identifier — what fly.io routes on. The server sees this.
  TextColumn get code => text()();
  // Per-link 256-bit secret (base64url) used to derive the AES key that
  // encrypts cascade payloads end-to-end. Shared party-to-party alongside
  // the code but NEVER sent to the server, so the server stores only
  // ciphertext. Null on legacy links created before E2E cascade.
  TextColumn get linkSecret => text().nullable()();
  // 'pending_remote' — waiting for the other machine to redeem
  // 'active'         — both sides confirmed (single-machine link or
  //                    successful cross-machine handshake)
  // 'revoked'        — manually broken from either side
  TextColumn get status =>
      text().withDefault(const Constant('pending_remote'))();
  // True when this side generated the code (vs received it). Cosmetic
  // — lets settings show the host/joiner distinction.
  BoolColumn get generatedHere =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Same-machine cascade channel — a local mirror of the server's
/// `cascaded_items` table. When a project and a programme live in the
/// same install, the link activates locally (partnerLocalId set on both
/// sides) but there's no sync server in the loop. This table is the
/// transport: [LocalCascadeGateway] writes pushed items here keyed by
/// the link [code], and the programme's pull reads them back. Rows are
/// upserted on (code, itemKind, itemId); a tombstone sets [deleted].
class CascadeItems extends Table {
  // The shared link code both sides hold. Push writes under it; pull
  // reads everything under it — exactly how the remote channel keys.
  TextColumn get code => text()();
  // The source project that emitted the item (cascade attribution).
  TextColumn get sourceEntityId => text()();
  TextColumn get itemKind => text()(); // CascadeKinds.* string
  TextColumn get itemId => text()();
  // JSON-encoded payload map — the same shape the remote channel carries.
  TextColumn get payload => text()();
  // Soft-delete tombstone. Pull applies these as removals so an
  // unescalated / deleted item disappears from the programme side.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {code, itemKind, itemId};
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
  TextColumn get likelihoodRationale => text().nullable()();
  TextColumn get impactRationale => text().nullable()();
  TextColumn get mitigation => text().nullable()();
  TextColumn get owner => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get sourceNote => text().nullable()();
  // Programme-cascade markers (Phase C.2). escalatedAt non-null
  // means the PM has flagged this risk as a candidate to push up to
  // any linked programme. sourceProjectId non-null means this row
  // arrived via cascade on the programme side — read-only.
  DateTimeColumn get escalatedAt => dateTime().nullable()();
  TextColumn get sourceProjectId => text().nullable()();
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
  // See Risks for the same markers + semantics.
  DateTimeColumn get escalatedAt => dateTime().nullable()();
  TextColumn get sourceProjectId => text().nullable()();
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
  DateTimeColumn get escalatedAt => dateTime().nullable()();
  TextColumn get sourceProjectId => text().nullable()();
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
  DateTimeColumn get escalatedAt => dateTime().nullable()();
  TextColumn get sourceProjectId => text().nullable()();
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
  // Cascade markers (Phase C.6). escalatedAt non-null = PM has
  // flagged for programme visibility; sourceProjectId non-null =
  // arrived via cascade and is read-only on this side.
  DateTimeColumn get escalatedAt => dateTime().nullable()();
  TextColumn get sourceProjectId => text().nullable()();
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
  // Category of person within this project — colleague | exec | vendor.
  // (Legacy databases may contain 'stakeholder'; the v26 migration converts
  // those to 'colleague' and sets isStakeholder = true.)
  TextColumn get personType =>
      text().withDefault(const Constant('colleague'))();
  // Orthogonal flag: is this person a project stakeholder (someone whose
  // engagement we want to track in influence/interest/stance terms)?
  BoolColumn get isStakeholder =>
      boolean().withDefault(const Constant(false))();
  // Cascade origin marker (Phase C.5). Non-null = this person arrived
  // from a linked project; read-only on this side. The cached source
  // name labels them in lists without a cross-machine join.
  TextColumn get sourceProjectId => text().nullable()();
  TextColumn get sourceProjectName => text().nullable()();
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
  // Set when this profile arrived via cascade alongside its person
  // (programme side). Read-only; null for native rows.
  TextColumn get sourceProjectId => text().nullable()();
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
  // Cascade marker (programme side) — the role slot arrived from a linked
  // project's People overview; read-only. Null for native rows.
  TextColumn get sourceProjectId => text().nullable()();
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
  // Cascade marker (programme side); null for native rows.
  TextColumn get sourceProjectId => text().nullable()();
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
  // Cascade origin marker (programme side). Read-only; null for native.
  TextColumn get sourceProjectId => text().nullable()();
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
  TextColumn get planActivityId => text().nullable()(); // FK → TimelineActivities
  TextColumn get parentActionId => text().nullable()(); // self-ref, one level deep
  // Cascade markers (Phase C.6). Same semantics as Decisions /
  // RAID — PM-flagged escalations push to linked programmes; the
  // source pointer makes the row read-only on the receiving side.
  DateTimeColumn get escalatedAt => dateTime().nullable()();
  TextColumn get sourceProjectId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ActionComments extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get actionId => text().references(ProjectActions, #id)();
  TextColumn get content => text()();
  BoolColumn get isCompletion => boolean().withDefault(const Constant(false))();
  TextColumn get authorName => text().nullable()();
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
  BoolColumn get isFavourite => boolean().withDefault(const Constant(false))();
  TextColumn get seriesId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Backing table for [JournalSeries] (the data class). Named with the
/// '...Defs' suffix only because Drift's auto-pluraliser mangles "Series"
/// into "Sery" — we name the row class explicitly via [DataClassName].
@DataClassName('JournalSeries')
class JournalSeriesDefs extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  /// Free-text hint like 'daily', 'weekly', 'fortnightly'. Informational
  /// only — we don't schedule anything off it.
  TextColumn get cadenceHint => text().nullable()();
  /// Optional hex colour for series cards (e.g. '#3B82F6').
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
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

// ---------------------------------------------------------------------------
// Canvas — PM's strategic thinking surface (replaces Schedule)
// ---------------------------------------------------------------------------

/// A single card on the Canvas. Cards are loose by design — most have just
/// a title and a few notes. Some link to formal items (RAID, action,
/// decision, milestone, activity) or carry a colour/size, but none of
/// that is required.
class CanvasCards extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();

  TextColumn get title => text()();
  TextColumn get body => text().nullable()();

  /// this_week | next_30_days | horizon
  TextColumn get band =>
      text().withDefault(const Constant('this_week'))();

  /// Free positioning within band (pixels from band origin).
  IntColumn get positionX => integer().withDefault(const Constant(16))();
  IntColumn get positionY => integer().withDefault(const Constant(16))();

  /// Optional visual grouping. null = default (no colour band).
  /// Allowed values: amber | green | red | blue | purple
  TextColumn get colour => text().nullable()();

  /// small | medium | large
  TextColumn get size =>
      text().withDefault(const Constant('medium'))();

  /// Optional self-dated range. ISO YYYY-MM-DD strings, both nullable.
  /// When [startDate] is set without [endDate], the card is treated as
  /// a single-point card on the calendar. When both are set, the card
  /// renders as a bar across the inclusive range.
  TextColumn get startDate => text().nullable()();
  TextColumn get endDate => text().nullable()();

  /// How long this piece of work is expected to take, in calendar days.
  /// Used when the user drags an undated card onto the calendar to
  /// pre-populate a sensible range. Null = no estimate (the drop UI
  /// falls back to a 7-day default).
  IntColumn get effortDays => integer().nullable()();

  /// Tags derived from `#tagname` patterns in the body, stored as a
  /// JSON-serialised array of lowercased strings. Updated by the editor
  /// save flow; the body remains the source of truth.
  TextColumn get tags => text().nullable()();

  /// Optional link to a formal item.
  /// linkedItemType ∈ risk | assumption | issue | dependency
  ///                 | decision | action | milestone | activity | journal
  TextColumn get linkedItemType => text().nullable()();
  TextColumn get linkedItemId => text().nullable()();

  /// Set when the card has been promoted to a formal programme item.
  /// promotedToType uses the same enum as linkedItemType (no 'journal').
  DateTimeColumn get promotedAt => dateTime().nullable()();
  TextColumn get promotedToType => text().nullable()();
  TextColumn get promotedToId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A template instance — a SWOT, pre-mortem, retrospective, etc. — that
/// the user has created for a project. The structure varies per type
/// (stored as JSON in [content]); the registry in
/// `lib/features/canvas/templates/template_registry.dart` defines the
/// schema for each type.
class CanvasTemplates extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();

  /// One of: pre_mortem | swot | retrospective | stakeholder_map |
  /// raci_matrix | user_story_map. See TemplateRegistry.
  TextColumn get templateType => text()();

  /// User-given name (e.g. "Q3 SWOT", "TAC Integration User Story Map").
  TextColumn get name => text()();

  /// Template-specific JSON-serialised content. Each template type
  /// owns its own JSON schema; see TemplateRegistry for shape.
  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Directional arrows between two Canvas cards (A → B means A precedes B).
class CanvasSequences extends Table {
  TextColumn get id => text().named('id')();
  TextColumn get projectId => text().references(Projects, #id)();
  @ReferenceName('outgoingSequences')
  TextColumn get fromCardId => text().references(CanvasCards, #id)();
  @ReferenceName('incomingSequences')
  TextColumn get toCardId => text().references(CanvasCards, #id)();
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
  // Cascade origin marker (Phase C.3). Status reports cascade
  // automatically on save — saving a status report IS the publish
  // moment — so this column is the programme-side flag that says
  // "this report came from a linked project; the canonical version
  // lives on the source PM's machine". Read-only on the programme
  // side; locally-authored programme reports leave it null.
  TextColumn get sourceProjectId => text().nullable()();
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
  // Populated when this WP cascaded into the row from a linked
  // upstream project (programme-side rows only). Holds the SOURCE
  // project's id — i.e. the project the cascade originated from on
  // the other PM's machine. Null = native WP authored on this
  // install; cascaded rows are rendered read-only and tagged with the
  // upstream project's name in the Plan view.
  TextColumn get sourceProjectId => text().nullable()();
  // Cascaded span (programme-side rows only). Only WP HEADERS cascade —
  // the underlying activities stay private to the source project — so a
  // cascaded WP has no activities to derive a bar from. At push time the
  // source PM's app computes the WP's overall span from its activities
  // and converts it to absolute dates (using that project's month-0
  // anchor); these columns store the result so the programme can draw a
  // swimlane bar mapped onto its own timeline. Null on native rows and
  // on cascaded WPs whose source had no dated activities.
  TextColumn get cascadeStartDate => text().nullable()();
  TextColumn get cascadeEndDate => text().nullable()();
  // Raw month indices of the same span, carried alongside the absolute
  // dates. Used to draw the bar when neither project has set a calendar
  // anchor (month0Date) — the common relative-axis case — where the
  // dates can't be computed but the axes are assumed aligned (M0=M0).
  IntColumn get cascadeStartMonth => integer().nullable()();
  IntColumn get cascadeEndMonth => integer().nullable()();
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
  // JSON arrays for secondary contributors e.g. '["Alice","Bob"]'
  TextColumn get contributors => text().nullable()();
  TextColumn get contributorIds => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TimelineDependencies extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  // For internal deps this is the upstream activity id. For external
  // deps (dependencyType == 'external') the upstream activity isn't in
  // the plan, so this column stores an empty string and the human label
  // lives in [externalLabel] instead.
  TextColumn get fromActivityId => text()();
  TextColumn get toActivityId => text()();
  // finish_to_start | start_to_start | finish_to_finish | external
  TextColumn get dependencyType =>
      text().withDefault(const Constant('finish_to_start'))();
  TextColumn get notes => text().nullable()();
  // Free-text label for external dependencies, e.g. "Vendor X delivery"
  // or "Legal sign-off". Non-null implies an external dep; the painter
  // anchors the arrow to the left of the target row rather than to a
  // source row that doesn't exist.
  TextColumn get externalLabel => text().nullable()();
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

  // Rich-snapshot fields — added schema v19. All nullable so old snapshots
  // (and snapshots taken without a configured narrative) round-trip cleanly.
  // Stored as JSON so we don't need a relational schema for snapshot detail.
  TextColumn get narrative => text().nullable()();
  // [{id, name, rag}]
  TextColumn get workstreamHealthJson => text().nullable()();
  // [{id, ref, description, likelihood, impact}]
  TextColumn get topRisksJson => text().nullable()();
  // [{id, name, owner, dueLabel}]
  TextColumn get upcomingMilestonesJson => text().nullable()();
  // [{id, ref, description, dueDate, owner}]
  TextColumn get pendingDecisionsJson => text().nullable()();
  // {stageId, stageName, status}
  TextColumn get playbookStageJson => text().nullable()();

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
  // Cascade origin marker (Phase C.4). Non-null = this row arrived
  // from a linked project; on the programme side it sits alongside
  // the programme's own native charter (which has sourceProjectId
  // NULL). Read-only on this side. Plus a cached source name so the
  // programme-side UI can label the cascaded card without joining
  // back to the Projects table on a different machine.
  TextColumn get sourceProjectId => text().nullable()();
  TextColumn get sourceProjectName => text().nullable()();
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
    ProgrammeLinks,
    CascadeItems,
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
    ActionComments,
    JournalSeriesDefs,
    CanvasCards,
    CanvasSequences,
    CanvasTemplates,
  ],
  daos: [
    ProjectDao,
    ProgrammeDao,
    ProgrammeLinksDao,
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
    ActionCommentsDao,
    JournalSeriesDao,
    CanvasCardsDao,
    CanvasTemplatesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openAppConnection());
  AppDatabase.memory() : super(openMemoryConnection());

  /// Test-only: wrap an arbitrary executor so migration tests can point at
  /// a hand-seeded old-schema database file.
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 46;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Idempotent DDL. `m.createTable`/`m.addColumn` build from the
          // CURRENT schema, so a table created in an early migration step
          // already carries columns that LATER steps then try to add —
          // which throws "duplicate column" and aborts the whole upgrade
          // (and a re-run then hits "table already exists"). Swallowing
          // those specific no-op errors makes upgrades from any old
          // schema — and recovery from a half-applied one — safe.
          Future<void> ensureTable(TableInfo table) async {
            try {
              await m.createTable(table);
            } catch (_) {}
          }
          Future<void> ensureColumn(
              TableInfo table, GeneratedColumn column) async {
            try {
              await m.addColumn(table, column);
            } catch (_) {}
          }

          if (from < 2) {
            await ensureColumn(persons, persons.phone);
            await ensureColumn(persons, persons.teamsHandle);
            await ensureColumn(persons, persons.personType);
            await ensureColumn(colleagueProfiles, colleagueProfiles.team);
            await ensureColumn(
                colleagueProfiles, colleagueProfiles.directReport);
          }
          if (from < 3) {
            await ensureColumn(projects, projects.startDate);
          }
          if (from < 4) {
            await ensureTable(journalEntries);
            await ensureTable(journalEntryLinks);
          }
          if (from < 5) {
            await ensureColumn(workstreams, workstreams.lane);
            await ensureColumn(workstreams, workstreams.startDate);
            await ensureColumn(workstreams, workstreams.endDate);
            await ensureTable(workstreamLinks);
          }
          if (from < 6) {
            await ensureTable(glossaryEntries);
          }
          if (from < 7) {
            await ensureTable(actionCategories);
            await ensureColumn(projectActions, projectActions.categoryId);
            await ensureColumn(projectActions, projectActions.recurrenceGroupId);
            await ensureColumn(projectActions, projectActions.linkedActionId);
          }
          if (from < 8) {
            await ensureColumn(projectActions, projectActions.outcome);
          }
          if (from < 9) {
            await ensureTable(organisations);
            await ensureTable(playbooks);
            await ensureTable(playbookStages);
            await ensureTable(stageTemplates);
            await ensureTable(projectPlaybooks);
            await ensureTable(projectStageProgresses);
          }
          if (from < 10) {
            await ensureTable(stakeholderRoles);
            await ensureTable(teamRoles);
          }
          if (from < 11) {
            await ensureTable(milestones);
            await ensureTable(workstreamActivities);
          }
          if (from < 12) {
            await ensureTable(timelineWorkPackages);
            await ensureTable(timelineActivities);
            await ensureTable(timelineDependencies);
            await ensureTable(programmeHeaders);
            await ensureTable(projectScopes);
            await ensureTable(integrationDomains);
            await ensureTable(prioritisationSources);
          }
          if (from < 13) {
            // Guard: if upgrading from <12, createTable(timelineActivities)
            // already ran with the current schema which includes status.
            try {
              await ensureColumn(timelineActivities, timelineActivities.status);
            } catch (_) {}
          }
          if (from < 14) {
            // Guard: same issue — stakeholderRoles created at v10 with
            // current schema already includes these columns.
            try {
              await ensureColumn(stakeholderRoles, stakeholderRoles.functionalArea);
            } catch (_) {}
            try {
              await ensureColumn(stakeholderRoles, stakeholderRoles.integrationRelevance);
            } catch (_) {}
            try {
              await ensureColumn(stakeholderRoles, stakeholderRoles.priority);
            } catch (_) {}
            try {
              await ensureColumn(stakeholderRoles, stakeholderRoles.engagementStatus);
            } catch (_) {}
            try {
              await ensureColumn(stakeholderRoles, stakeholderRoles.gapFlag);
            } catch (_) {}
            try {
              await ensureColumn(stakeholderRoles, stakeholderRoles.gapDescription);
            } catch (_) {}
          }
          if (from < 15) {
            await ensureTable(statusSnapshots);
          }
          if (from < 16) {
            await ensureTable(projectCharters);
            await ensureTable(programmeOverviewStates);
          }
          if (from < 17) {
            await ensureColumn(timelineActivities, timelineActivities.contributors);
            await ensureColumn(timelineActivities, timelineActivities.contributorIds);
          }
          if (from < 18) {
            await ensureColumn(projectActions, projectActions.planActivityId);
          }
          if (from < 19) {
            // Rich-snapshot fields. All nullable; old snapshots stay valid.
            await ensureColumn(statusSnapshots, statusSnapshots.narrative);
            await ensureColumn(
                statusSnapshots, statusSnapshots.workstreamHealthJson);
            await ensureColumn(statusSnapshots, statusSnapshots.topRisksJson);
            await ensureColumn(
                statusSnapshots, statusSnapshots.upcomingMilestonesJson);
            await ensureColumn(
                statusSnapshots, statusSnapshots.pendingDecisionsJson);
            await ensureColumn(
                statusSnapshots, statusSnapshots.playbookStageJson);
          }
          if (from < 20) {
            await ensureColumn(risks, risks.likelihoodRationale);
            await ensureColumn(risks, risks.impactRationale);
          }
          if (from < 21) {
            await ensureColumn(projectActions, projectActions.parentActionId);
          }
          if (from < 22) {
            await ensureTable(actionComments);
          }
          if (from < 23) {
            await ensureColumn(journalEntries, journalEntries.isFavourite);
          }
          if (from < 24) {
            // Series feature was rolled back briefly. Drop the seriesId
            // column and journal_series_defs table that were introduced in
            // v23. Guarded because a fresh DB at v24 never created either.
            try {
              await customStatement(
                  'ALTER TABLE journal_entries DROP COLUMN series_id');
            } catch (_) {}
            try {
              await customStatement(
                  'DROP TABLE IF EXISTS journal_series_defs');
            } catch (_) {}
          }
          if (from < 25) {
            // Series feature re-instated. Re-add the column + table that
            // v24 dropped. Guarded so a DB that never ran v23/v24 (fresh
            // install at v25) still works via createAll().
            try {
              await ensureColumn(journalEntries, journalEntries.seriesId);
            } catch (_) {}
            try {
              await ensureTable(journalSeriesDefs);
            } catch (_) {}
          }
          if (from < 26) {
            // Split 'stakeholder' out of personType. Existing stakeholder
            // rows become colleague + isStakeholder=true so their data and
            // any StakeholderProfile rows remain valid.
            await ensureColumn(persons, persons.isStakeholder);
            await customStatement(
              "UPDATE persons SET person_type = 'colleague', "
              "is_stakeholder = 1 WHERE person_type = 'stakeholder'",
            );
          }
          if (from < 27) {
            // Canvas tables — replaces the old Schedule view. No data to
            // migrate.
            await ensureTable(canvasCards);
            await ensureTable(canvasSequences);
          }
          if (from < 28) {
            // Native date range on Canvas cards — lets a card sit on the
            // calendar without needing a linked dated item.
            await ensureColumn(canvasCards, canvasCards.startDate);
            await ensureColumn(canvasCards, canvasCards.endDate);
          }
          if (from < 29) {
            // Effort estimate (days) — used when dragging an undated
            // card onto the calendar to pre-populate a sensible range.
            await ensureColumn(canvasCards, canvasCards.effortDays);
          }
          if (from < 30) {
            // Tags column — parsed from `#tag` patterns in card bodies
            // and stored as a JSON array string. Phase 1 of Canvas v2.
            await ensureColumn(canvasCards, canvasCards.tags);
          }
          if (from < 31) {
            // CanvasTemplates — SWOT, pre-mortem, etc. Phase 2 of v2.
            await ensureTable(canvasTemplates);
          }
          if (from < 32) {
            // External dependencies — nullable label on dep rows so the
            // upstream "activity" can live outside the plan (vendor
            // deliveries, regulatory approvals, other teams' milestones).
            await ensureColumn(
                timelineDependencies, timelineDependencies.externalLabel);
          }
          if (from < 33) {
            // Programme-vs-project distinction. Existing rows all
            // become kind='project' by the column's default; Phase B
            // populates parentProgrammeId via the linking flow.
            await ensureColumn(projects, projects.kind);
            await ensureColumn(projects, projects.parentProgrammeId);
          }
          if (from < 34) {
            // Programme ↔ project links. Each side of a link stores
            // its own row keyed by a shared code.
            await ensureTable(programmeLinks);
          }
          if (from < 35) {
            // Cascade origin marker on work packages — populated when
            // a WP arrives via a programme link (read-only on the
            // programme side); null for native rows.
            await ensureColumn(
                timelineWorkPackages, timelineWorkPackages.sourceProjectId);
          }
          if (from < 36) {
            // RAID cascade markers (Phase C.2). escalatedAt = PM has
            // flagged this row for programme visibility; sourceProjectId
            // = row arrived via cascade and is read-only on this side.
            await ensureColumn(risks, risks.escalatedAt);
            await ensureColumn(risks, risks.sourceProjectId);
            await ensureColumn(assumptions, assumptions.escalatedAt);
            await ensureColumn(assumptions, assumptions.sourceProjectId);
            await ensureColumn(issues, issues.escalatedAt);
            await ensureColumn(issues, issues.sourceProjectId);
            await ensureColumn(
                programDependencies, programDependencies.escalatedAt);
            await ensureColumn(programDependencies,
                programDependencies.sourceProjectId);
          }
          if (from < 37) {
            // Status-report cascade marker (Phase C.3). Auto-cascade
            // on save; column flags cascaded rows on the programme
            // side as read-only.
            await ensureColumn(
                statusReports, statusReports.sourceProjectId);
          }
          if (from < 38) {
            // Charter cascade markers (Phase C.4). The cached source
            // name lets the programme-side card render attribution
            // without a cross-machine join.
            await ensureColumn(
                projectCharters, projectCharters.sourceProjectId);
            await ensureColumn(
                projectCharters, projectCharters.sourceProjectName);
          }
          if (from < 39) {
            // Person cascade markers (Phase C.5). Same pattern as
            // charter — cached source name avoids cross-machine joins.
            await ensureColumn(persons, persons.sourceProjectId);
            await ensureColumn(persons, persons.sourceProjectName);
          }
          if (from < 40) {
            // Actions + Decisions cascade markers (Phase C.6).
            await ensureColumn(projectActions, projectActions.escalatedAt);
            await ensureColumn(
                projectActions, projectActions.sourceProjectId);
            await ensureColumn(decisions, decisions.escalatedAt);
            await ensureColumn(decisions, decisions.sourceProjectId);
          }
          if (from < 41) {
            // Same-machine cascade channel. Lets a project and a
            // programme in one install exchange cascaded items without
            // a sync server in the loop (LocalCascadeGateway).
            await ensureTable(cascadeItems);
          }
          if (from < 42) {
            // Cascaded WP span — lets the programme draw a swimlane bar
            // for a cascaded WP whose activities stayed private.
            await ensureColumn(
                timelineWorkPackages, timelineWorkPackages.cascadeStartDate);
            await ensureColumn(
                timelineWorkPackages, timelineWorkPackages.cascadeEndDate);
          }
          if (from < 43) {
            // Raw month-index span — fallback bar placement when no
            // calendar anchor exists to derive absolute dates.
            await ensureColumn(timelineWorkPackages,
                timelineWorkPackages.cascadeStartMonth);
            await ensureColumn(
                timelineWorkPackages, timelineWorkPackages.cascadeEndMonth);
          }
          if (from < 44) {
            // Cascade markers on people profiles so a programme can show
            // stakeholder influence/interest/stance + colleague team
            // across all linked projects.
            await ensureColumn(stakeholderProfiles,
                stakeholderProfiles.sourceProjectId);
            await ensureColumn(
                colleagueProfiles, colleagueProfiles.sourceProjectId);
          }
          if (from < 45) {
            // Cascade markers on the coverage/role matrices so a
            // programme can render each project's full People overview.
            await ensureColumn(
                stakeholderRoles, stakeholderRoles.sourceProjectId);
            await ensureColumn(teamRoles, teamRoles.sourceProjectId);
          }
          if (from < 46) {
            // Per-link secret for E2E-encrypting cascade payloads.
            await ensureColumn(programmeLinks, programmeLinks.linkSecret);
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
      // Canvas — sequences reference cards, so delete sequences first.
      await (delete(canvasSequences)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(canvasCards)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(canvasTemplates)..where((t) => t.projectId.equals(projectId))).go();
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
      await (delete(journalSeriesDefs)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(contextEntries)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(glossaryEntries)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(inboxItems)..where((t) => t.projectId.equals(projectId))).go();
      await (delete(actionCategories)..where((t) => t.projectId.equals(projectId))).go();
      // Action comments reference actions; delete them first.
      await actionCommentsDao.deleteAllForProject(projectId);
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

  /// Copies people-related data from [sourceProjectId] into [targetProjectId].
  /// Copies Persons (all types — stakeholder, colleague, exec, vendor),
  /// StakeholderProfiles, StakeholderRoles, TeamRoles and ColleagueProfiles.
  /// New IDs are generated and FK references are rewritten. Source project
  /// is not modified.
  Future<void> copyPeopleToProject({
    required String sourceProjectId,
    required String targetProjectId,
  }) async {
    const uuid = Uuid();
    await transaction(() async {
      // Persons → build oldId → newId map for FK rewrites.
      final sourcePersons = await (select(persons)
            ..where((t) => t.projectId.equals(sourceProjectId)))
          .get();
      final personIdMap = <String, String>{};
      for (final p in sourcePersons) {
        final newId = uuid.v4();
        personIdMap[p.id] = newId;
        await into(persons).insert(PersonsCompanion.insert(
          id: newId,
          projectId: targetProjectId,
          name: p.name,
          email: Value(p.email),
          role: Value(p.role),
          organisation: Value(p.organisation),
          phone: Value(p.phone),
          teamsHandle: Value(p.teamsHandle),
          personType: Value(p.personType),
          isStakeholder: Value(p.isStakeholder),
        ));
      }

      final sps = await (select(stakeholderProfiles)
            ..where((t) => t.projectId.equals(sourceProjectId)))
          .get();
      for (final sp in sps) {
        final newPersonId = personIdMap[sp.personId];
        if (newPersonId == null) continue;
        await into(stakeholderProfiles)
            .insert(StakeholderProfilesCompanion.insert(
          id: uuid.v4(),
          projectId: targetProjectId,
          personId: newPersonId,
          influence: Value(sp.influence),
          interest: Value(sp.interest),
          stance: Value(sp.stance),
          engagementStrategy: Value(sp.engagementStrategy),
          notes: Value(sp.notes),
        ));
      }

      final srs = await (select(stakeholderRoles)
            ..where((t) => t.projectId.equals(sourceProjectId)))
          .get();
      for (final sr in srs) {
        await into(stakeholderRoles).insert(StakeholderRolesCompanion.insert(
          id: uuid.v4(),
          projectId: targetProjectId,
          roleName: sr.roleName,
          roleType: sr.roleType,
          personId: Value(
              sr.personId == null ? null : personIdMap[sr.personId]),
          isScaffold: Value(sr.isScaffold),
          isApplicable: Value(sr.isApplicable),
          sortOrder: Value(sr.sortOrder),
          notes: Value(sr.notes),
          functionalArea: Value(sr.functionalArea),
          integrationRelevance: Value(sr.integrationRelevance),
          priority: Value(sr.priority),
          engagementStatus: Value(sr.engagementStatus),
          gapFlag: Value(sr.gapFlag),
          gapDescription: Value(sr.gapDescription),
        ));
      }

      final trs = await (select(teamRoles)
            ..where((t) => t.projectId.equals(sourceProjectId)))
          .get();
      for (final tr in trs) {
        await into(teamRoles).insert(TeamRolesCompanion.insert(
          id: uuid.v4(),
          projectId: targetProjectId,
          roleName: tr.roleName,
          teamGroup: tr.teamGroup,
          personId: Value(
              tr.personId == null ? null : personIdMap[tr.personId]),
          isScaffold: Value(tr.isScaffold),
          isApplicable: Value(tr.isApplicable),
          sortOrder: Value(tr.sortOrder),
          notes: Value(tr.notes),
        ));
      }

      final cps = await (select(colleagueProfiles)
            ..where((t) => t.projectId.equals(sourceProjectId)))
          .get();
      for (final cp in cps) {
        final newPersonId = personIdMap[cp.personId];
        if (newPersonId == null) continue;
        await into(colleagueProfiles)
            .insert(ColleagueProfilesCompanion.insert(
          id: uuid.v4(),
          projectId: targetProjectId,
          personId: newPersonId,
          workingStyle: Value(cp.workingStyle),
          preferences: Value(cp.preferences),
          notes: Value(cp.notes),
          team: Value(cp.team),
          directReport: Value(cp.directReport),
        ));
      }
    });
  }
}

// Connection is provided by the platform-conditional connection.dart module.
