import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../shared/theme/keel_colors.dart';

import '../../core/cascade/cascade_service.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/programme/coverage_calculator.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../programme/overview/coverage_indicator.dart';
import '../programme/overview/stakeholder_section.dart';
import '../programme/overview/team_section.dart';

class PeopleView extends StatefulWidget {
  const PeopleView({super.key});

  @override
  State<PeopleView> createState() => _PeopleViewState();
}

class _PeopleViewState extends State<PeopleView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final projectId = provider.currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project to view people.'));
    }
    final db = context.read<AppDatabase>();

    // Programmes pull in each linked project's People-Overview layout
    // (coverage + stakeholder-role + team-role matrices) as a read-only
    // panel, one per project.
    if (provider.isProgramme) {
      return _ProgrammePeopleView(programmeId: projectId, db: db);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              const Icon(Icons.group, color: KColors.amber, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text('People',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showPersonForm(
                    context, projectId, db, null, null,
                    defaultIsStakeholder: false),
                icon: const Icon(Icons.person_add_outlined, size: 16),
                label: const Text('Add Person'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: KColors.border)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Stakeholders'),
              Tab(text: 'Team / Colleagues'),
              Tab(text: 'Executives'),
              Tab(text: 'Vendors'),
            ],
            indicatorColor: KColors.amber,
            labelColor: KColors.amber,
            unselectedLabelColor: KColors.textDim,
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _PeopleOverviewTab(projectId: projectId, db: db),
              _PersonsList(
                projectId: projectId,
                db: db,
                source: _PersonSource.stakeholderFlag,
                emptyMessage: 'No stakeholders flagged yet.',
                onEdit: (p) => _showPersonForm(context, projectId, db, p,
                    p.personType,
                    defaultIsStakeholder: true),
                onAdd: () => _showPersonForm(context, projectId, db, null, null,
                    defaultIsStakeholder: true),
              ),
              _PersonsList(
                projectId: projectId,
                db: db,
                source: _PersonSource.type('colleague'),
                emptyMessage: 'No team members added yet.',
                onEdit: (p) => _showPersonForm(
                    context, projectId, db, p, 'colleague',
                    defaultIsStakeholder: p.isStakeholder),
                onAdd: () => _showPersonForm(
                    context, projectId, db, null, 'colleague',
                    defaultIsStakeholder: false),
              ),
              _PersonsList(
                projectId: projectId,
                db: db,
                source: _PersonSource.type('exec'),
                emptyMessage: 'No executives added yet.',
                onEdit: (p) => _showPersonForm(
                    context, projectId, db, p, 'exec',
                    defaultIsStakeholder: p.isStakeholder),
                onAdd: () => _showPersonForm(
                    context, projectId, db, null, 'exec',
                    defaultIsStakeholder: false),
              ),
              _PersonsList(
                projectId: projectId,
                db: db,
                source: _PersonSource.type('vendor'),
                emptyMessage: 'No vendors added yet.',
                onEdit: (p) => _showPersonForm(
                    context, projectId, db, p, 'vendor',
                    defaultIsStakeholder: p.isStakeholder),
                onAdd: () => _showPersonForm(
                    context, projectId, db, null, 'vendor',
                    defaultIsStakeholder: false),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPersonForm(
    BuildContext context,
    String projectId,
    AppDatabase db,
    Person? person,
    String? defaultType, {
    required bool defaultIsStakeholder,
  }) {
    showDialog(
      context: context,
      builder: (_) => _PersonFormDialog(
        projectId: projectId,
        db: db,
        person: person,
        defaultType: defaultType ?? 'colleague',
        defaultIsStakeholder: defaultIsStakeholder,
      ),
    );
  }
}

/// Where a `_PersonsList` pulls its rows from — either a `personType`
/// category, or "everyone flagged as a stakeholder".
class _PersonSource {
  final String? personType;
  final bool stakeholderOnly;

  const _PersonSource._({this.personType, required this.stakeholderOnly});

  factory _PersonSource.type(String type) =>
      _PersonSource._(personType: type, stakeholderOnly: false);

  static const stakeholderFlag = _PersonSource._(stakeholderOnly: true);
}

// ---------------------------------------------------------------------------
// Overview tab — stakeholder roles, team roles, coverage indicator
// ---------------------------------------------------------------------------

class _PeopleOverviewTab extends StatelessWidget {
  final String projectId;
  final AppDatabase db;

  const _PeopleOverviewTab({required this.projectId, required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StakeholderRole>>(
      stream: db.stakeholderRoleDao.watchForProject(projectId),
      builder: (context, srSnap) {
        return StreamBuilder<List<TeamRole>>(
          stream: db.teamRoleDao.watchForProject(projectId),
          builder: (context, trSnap) {
            return StreamBuilder<List<Person>>(
              stream: db.peopleDao.watchPersonsForProject(projectId),
              builder: (context, pSnap) {
                final stakeholderRoles = srSnap.data ?? [];
                final teamRoles = trSnap.data ?? [];
                final persons = pSnap.data ?? [];

                final stakeholderCoverage =
                    CoverageCalculator.forStakeholders(stakeholderRoles);
                final teamCoverage =
                    CoverageCalculator.forTeam(teamRoles);

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverageIndicator(
                        stakeholders: stakeholderCoverage,
                        team: teamCoverage,
                      ),
                      const _OverviewSectionLabel('STAKEHOLDERS'),
                      const SizedBox(height: 8),
                      StakeholderSection(
                        projectId: projectId,
                        db: db,
                        roles: stakeholderRoles,
                        persons: persons,
                      ),
                      const SizedBox(height: 24),
                      const _OverviewSectionLabel('TEAM'),
                      const SizedBox(height: 8),
                      TeamSection(
                        projectId: projectId,
                        db: db,
                        roles: teamRoles,
                        persons: persons,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _OverviewSectionLabel extends StatelessWidget {
  final String text;
  const _OverviewSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: KColors.textDim,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
      ),
    );
  }
}

class _PersonsList extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final _PersonSource source;
  final String emptyMessage;
  final void Function(Person) onEdit;
  final VoidCallback onAdd;

  const _PersonsList({
    required this.projectId,
    required this.db,
    required this.source,
    required this.emptyMessage,
    required this.onEdit,
    required this.onAdd,
  });

  Stream<List<Person>> _stream() {
    if (source.stakeholderOnly) {
      return db.peopleDao.watchStakeholderPersons(projectId);
    }
    return db.peopleDao.watchPersonsByType(projectId, source.personType!);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Person>>(
      stream: _stream(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final persons = snap.data!;
        if (persons.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  emptyMessage,
                  style: const TextStyle(color: KColors.textDim),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.person_add_outlined, size: 14),
                  label: const Text('Add'),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: persons.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) => _PersonCard(
            person: persons[i],
            db: db,
            projectId: projectId,
            onEdit: () => onEdit(persons[i]),
          ),
        );
      },
    );
  }
}

class _PersonCard extends StatelessWidget {
  final Person person;
  final AppDatabase db;
  final String projectId;
  final VoidCallback onEdit;

  const _PersonCard({
    required this.person,
    required this.db,
    required this.projectId,
    required this.onEdit,
  });

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// CascadeService for the delete-tombstone path. Mirrors the helper
  /// on the form save handler.
  CascadeService _cascadeForRow(BuildContext context) =>
      buildCascadeService(context);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => _PersonDetailDialog(
            person: person,
            db: db,
            projectId: projectId,
          ),
        ),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: KColors.blueDim,
                radius: 22,
                child: Text(
                  _initials(person.name),
                  style: const TextStyle(
                    color: KColors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Builder(builder: (ctx) {
                          final myName = ctx
                              .read<SettingsProvider>()
                              .settings
                              .myName;
                          if (myName.isEmpty || person.name != myName) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: KColors.phosDim,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'YOU',
                              style: TextStyle(
                                color: KColors.phosphor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                    if (person.role != null && person.role!.isNotEmpty)
                      Text(
                        person.role!,
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 12),
                      ),
                    if (person.organisation != null &&
                        person.organisation!.isNotEmpty)
                      Text(
                        person.organisation!,
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 12),
                      ),
                  ],
                ),
              ),
              // Profile badges via FutureBuilder
              if (person.isStakeholder)
                FutureBuilder<StakeholderProfile?>(
                  future: db.peopleDao.getStakeholderByPersonId(person.id),
                  builder: (ctx, snap) {
                    final profile = snap.data;
                    if (profile == null) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (profile.influence != null)
                          _Badge(
                            label: profile.influence!,
                            color: _influenceColor(profile.influence!),
                          ),
                        const SizedBox(width: 6),
                        if (profile.stance != null)
                          _Badge(
                            label: profile.stance!,
                            color: _stanceColor(profile.stance!),
                          ),
                      ],
                    );
                  },
                ),
              const SizedBox(width: 8),
              if (person.email != null && person.email!.isNotEmpty)
                Flexible(
                  child: Text(
                    person.email!,
                    style: const TextStyle(
                        color: KColors.textDim, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: 8),
              if (person.sourceProjectId != null) ...[
                // Cascaded — read-only. Show a PROJ tag with the
                // source project name so the programme manager knows
                // who they're looking at and where the canonical
                // record lives.
                Tooltip(
                  message:
                      'Cascaded from ${person.sourceProjectName ?? "a linked project"} — read-only',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KColors.surface2,
                      border: Border.all(
                          color: KColors.border2, width: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      person.sourceProjectName != null
                          ? 'PROJ · ${person.sourceProjectName}'
                          : 'PROJ',
                      style: const TextStyle(
                        color: KColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: KColors.red),
                  onPressed: () async {
                    // Tombstone the cascade copies first so the
                    // programme sees the removal reliably.
                    await _cascadeForRow(context).deletePerson(
                      projectId: person.projectId,
                      personId: person.id,
                    );
                    await db.peopleDao.deletePerson(person.id);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _influenceColor(String influence) {
    switch (influence) {
      case 'high':
        return KColors.red;
      case 'medium':
        return KColors.amber;
      default:
        return KColors.textDim;
    }
  }

  Color _stanceColor(String stance) {
    switch (stance) {
      case 'sponsor':
      case 'supporter':
        return KColors.phosphor;
      case 'resistant':
        return KColors.red;
      case 'neutral':
        return KColors.textDim;
      default:
        return KColors.textMuted;
    }
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Person detail dialog
// ---------------------------------------------------------------------------

class _PersonDetailDialog extends StatelessWidget {
  final Person person;
  final AppDatabase db;
  final String projectId;

  const _PersonDetailDialog({
    required this.person,
    required this.db,
    required this.projectId,
  });

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: KColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: KColors.blueDim,
                    radius: 28,
                    child: Text(
                      _initials(person.name),
                      style: const TextStyle(
                          color: KColors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        if (person.role != null && person.role!.isNotEmpty)
                          Text(person.role!,
                              style: const TextStyle(
                                  color: KColors.textDim, fontSize: 13)),
                        if (person.organisation != null &&
                            person.organisation!.isNotEmpty)
                          Text(person.organisation!,
                              style: const TextStyle(
                                  color: KColors.textDim, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Contact + profile
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Contact info
                    if (person.email != null ||
                        person.phone != null ||
                        person.teamsHandle != null) ...[
                      const _SectionHeader('Contact'),
                      const SizedBox(height: 8),
                      if (person.email != null && person.email!.isNotEmpty)
                        _InfoRow(Icons.email_outlined, person.email!),
                      if (person.phone != null && person.phone!.isNotEmpty)
                        _InfoRow(Icons.phone_outlined, person.phone!),
                      if (person.teamsHandle != null &&
                          person.teamsHandle!.isNotEmpty)
                        _InfoRow(Icons.chat_outlined, person.teamsHandle!),
                      const SizedBox(height: 16),
                    ],
                    // Profile section
                    if (person.isStakeholder)
                      FutureBuilder<StakeholderProfile?>(
                        future: db.peopleDao
                            .getStakeholderByPersonId(person.id),
                        builder: (ctx, snap) {
                          final p = snap.data;
                          if (p == null) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader('Stakeholder Profile'),
                              const SizedBox(height: 8),
                              if (p.influence != null)
                                _InfoRow(Icons.trending_up_outlined,
                                    'Influence: ${p.influence}'),
                              if (p.stance != null)
                                _InfoRow(Icons.sentiment_satisfied_outlined,
                                    'Stance: ${p.stance}'),
                              if (p.engagementStrategy != null &&
                                  p.engagementStrategy!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Engagement strategy',
                                          style: TextStyle(
                                              color: KColors.textDim,
                                              fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(p.engagementStrategy!,
                                          style: const TextStyle(
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              if (p.notes != null && p.notes!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Notes',
                                          style: TextStyle(
                                              color: KColors.textDim,
                                              fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(p.notes!,
                                          style: const TextStyle(
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 16),
                            ],
                          );
                        },
                      ),
                    if (person.personType == 'colleague')
                      FutureBuilder<ColleagueProfile?>(
                        future:
                            db.peopleDao.getColleagueByPersonId(person.id),
                        builder: (ctx, snap) {
                          final p = snap.data;
                          if (p == null) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader('Colleague Profile'),
                              const SizedBox(height: 8),
                              if (p.team != null && p.team!.isNotEmpty)
                                _InfoRow(Icons.group_outlined,
                                    'Team: ${p.team}'),
                              if (p.directReport)
                                const _InfoRow(Icons.person_pin_outlined,
                                    'Direct report'),
                              if (p.workingStyle != null &&
                                  p.workingStyle!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Working style',
                                          style: TextStyle(
                                              color: KColors.textDim,
                                              fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(p.workingStyle!,
                                          style: const TextStyle(
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              if (p.notes != null && p.notes!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Notes',
                                          style: TextStyle(
                                              color: KColors.textDim,
                                              fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(p.notes!,
                                          style: const TextStyle(
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 16),
                            ],
                          );
                        },
                      ),
                    // Actions
                    const _SectionHeader('Actions & Commitments'),
                    const SizedBox(height: 8),
                    StreamBuilder<List<ProjectAction>>(
                      stream: db.actionsDao
                          .watchActionsForOwner(projectId, person.name),
                      builder: (ctx, snap) {
                        if (!snap.hasData) {
                          return const SizedBox(
                              height: 40,
                              child: Center(
                                  child: CircularProgressIndicator()));
                        }
                        final actions = snap.data!;
                        if (actions.isEmpty) {
                          return const Text('No actions assigned.',
                              style: TextStyle(color: KColors.textDim));
                        }
                        final today = DateTime.now()
                            .toIso8601String()
                            .substring(0, 10);
                        final overdue = actions
                            .where((a) =>
                                a.dueDate != null &&
                                a.dueDate!.compareTo(today) < 0 &&
                                a.status != 'closed')
                            .toList();
                        final open = actions
                            .where((a) =>
                                a.status != 'closed' &&
                                (a.dueDate == null ||
                                    a.dueDate!.compareTo(today) >= 0))
                            .toList();
                        final closed = actions
                            .where((a) => a.status == 'closed')
                            .toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (overdue.isNotEmpty) ...[
                              const Text('OVERDUE',
                                  style: TextStyle(
                                      color: KColors.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              ...overdue.map((a) => _ActionRow(
                                  action: a, db: db, isOverdue: true)),
                              const SizedBox(height: 8),
                            ],
                            if (open.isNotEmpty) ...[
                              const Text('OPEN',
                                  style: TextStyle(
                                      color: KColors.textDim,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              ...open.map((a) => _ActionRow(
                                  action: a, db: db, isOverdue: false)),
                              const SizedBox(height: 8),
                            ],
                            if (closed.isNotEmpty) ...[
                              const Text('COMPLETED',
                                  style: TextStyle(
                                      color: KColors.phosphor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              ...closed.map((a) => _ActionRow(
                                  action: a, db: db, isOverdue: false)),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: KColors.amber,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: KColors.border)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: KColors.textDim),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final ProjectAction action;
  final AppDatabase db;
  final bool isOverdue;

  const _ActionRow(
      {required this.action, required this.db, required this.isOverdue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            action.status == 'closed'
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            size: 16,
            color: action.status == 'closed'
                ? KColors.phosphor
                : isOverdue
                    ? KColors.red
                    : KColors.textDim,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              action.description,
              style: TextStyle(
                fontSize: 13,
                decoration: action.status == 'closed'
                    ? TextDecoration.lineThrough
                    : null,
                color: action.status == 'closed'
                    ? KColors.textDim
                    : isOverdue
                        ? KColors.red
                        : null,
              ),
            ),
          ),
          if (action.dueDate != null)
            Text(
              du.formatDate(action.dueDate),
              style: TextStyle(
                fontSize: 11,
                color: isOverdue
                    ? KColors.red
                    : KColors.textDim,
              ),
            ),
          if (action.status != 'closed')
            IconButton(
              icon: const Icon(Icons.check, size: 16),
              tooltip: 'Mark closed',
              onPressed: () => db.actionsDao.upsertAction(
                ProjectActionsCompanion(
                  id: Value(action.id),
                  projectId: Value(action.projectId),
                  description: Value(action.description),
                  status: const Value('closed'),
                  updatedAt: Value(DateTime.now()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Person form dialog
// ---------------------------------------------------------------------------

class _PersonFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Person? person;
  final String defaultType;
  final bool defaultIsStakeholder;

  const _PersonFormDialog({
    required this.projectId,
    required this.db,
    this.person,
    required this.defaultType,
    required this.defaultIsStakeholder,
  });

  @override
  State<_PersonFormDialog> createState() => _PersonFormDialogState();
}

class _PersonFormDialogState extends State<_PersonFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _roleCtrl;
  late TextEditingController _orgCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _teamsCtrl;
  late String _personType;
  late bool _isStakeholder;

  // Stakeholder fields
  late TextEditingController _engagementCtrl;
  late TextEditingController _stakeholderNotesCtrl;
  String _influence = 'medium';
  String _interest = 'medium';
  String _stance = 'unknown';

  // Colleague fields
  late TextEditingController _teamCtrl;
  late TextEditingController _workingStyleCtrl;
  late TextEditingController _colleagueNotesCtrl;
  bool _directReport = false;

  // Category is now one of three; "stakeholder" is the orthogonal flag below.
  final _personTypes = ['colleague', 'exec', 'vendor'];
  final _influences = ['high', 'medium', 'low'];
  final _interests = ['high', 'medium', 'low'];
  final _stances = ['sponsor', 'supporter', 'neutral', 'resistant', 'unknown'];

  String _normaliseType(String raw) {
    // Legacy 'stakeholder' values fold into colleague + isStakeholder=true.
    if (raw == 'stakeholder') return 'colleague';
    if (_personTypes.contains(raw)) return raw;
    return 'colleague';
  }

  @override
  void initState() {
    super.initState();
    final p = widget.person;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _emailCtrl = TextEditingController(text: p?.email ?? '');
    _roleCtrl = TextEditingController(text: p?.role ?? '');
    _orgCtrl = TextEditingController(text: p?.organisation ?? '');
    _phoneCtrl = TextEditingController(text: p?.phone ?? '');
    _teamsCtrl = TextEditingController(text: p?.teamsHandle ?? '');
    _personType = _normaliseType(p?.personType ?? widget.defaultType);
    _isStakeholder = p?.isStakeholder ?? widget.defaultIsStakeholder;

    _engagementCtrl = TextEditingController();
    _stakeholderNotesCtrl = TextEditingController();
    _teamCtrl = TextEditingController();
    _workingStyleCtrl = TextEditingController();
    _colleagueNotesCtrl = TextEditingController();

    // Load profile data if editing
    if (p != null) {
      _loadProfile(p.id);
    }
  }

  Future<void> _loadProfile(String personId) async {
    final sp =
        await widget.db.peopleDao.getStakeholderByPersonId(personId);
    final cp = await widget.db.peopleDao.getColleagueByPersonId(personId);
    if (!mounted) return;
    setState(() {
      if (sp != null) {
        _influence = sp.influence ?? 'medium';
        _interest = sp.interest ?? 'medium';
        _stance = sp.stance ?? 'unknown';
        _engagementCtrl.text = sp.engagementStrategy ?? '';
        _stakeholderNotesCtrl.text = sp.notes ?? '';
      }
      if (cp != null) {
        _teamCtrl.text = cp.team ?? '';
        _directReport = cp.directReport;
        _workingStyleCtrl.text = cp.workingStyle ?? '';
        _colleagueNotesCtrl.text = cp.notes ?? '';
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _roleCtrl.dispose();
    _orgCtrl.dispose();
    _phoneCtrl.dispose();
    _teamsCtrl.dispose();
    _engagementCtrl.dispose();
    _stakeholderNotesCtrl.dispose();
    _teamCtrl.dispose();
    _workingStyleCtrl.dispose();
    _colleagueNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final id = widget.person?.id ?? const Uuid().v4();
    await widget.db.peopleDao.upsertPerson(
      PersonsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        name: Value(_nameCtrl.text.trim()),
        email: Value(_emailCtrl.text.trim().isEmpty
            ? null
            : _emailCtrl.text.trim()),
        role: Value(
            _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim()),
        organisation: Value(
            _orgCtrl.text.trim().isEmpty ? null : _orgCtrl.text.trim()),
        phone: Value(
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
        teamsHandle: Value(
            _teamsCtrl.text.trim().isEmpty ? null : _teamsCtrl.text.trim()),
        personType: Value(_personType),
        isStakeholder: Value(_isStakeholder),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (_isStakeholder) {
      final existing =
          await widget.db.peopleDao.getStakeholderByPersonId(id);
      final spId = existing?.id ?? const Uuid().v4();
      await widget.db.peopleDao.upsertStakeholder(
        StakeholderProfilesCompanion(
          id: Value(spId),
          projectId: Value(widget.projectId),
          personId: Value(id),
          influence: Value(_influence),
          interest: Value(_interest),
          stance: Value(_stance),
          engagementStrategy: Value(_engagementCtrl.text.trim().isEmpty
              ? null
              : _engagementCtrl.text.trim()),
          notes: Value(_stakeholderNotesCtrl.text.trim().isEmpty
              ? null
              : _stakeholderNotesCtrl.text.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
    if (_personType == 'colleague') {
      final existing =
          await widget.db.peopleDao.getColleagueByPersonId(id);
      final cpId = existing?.id ?? const Uuid().v4();
      await widget.db.peopleDao.upsertColleague(
        ColleagueProfilesCompanion(
          id: Value(cpId),
          projectId: Value(widget.projectId),
          personId: Value(id),
          team: Value(
              _teamCtrl.text.trim().isEmpty ? null : _teamCtrl.text.trim()),
          directReport: Value(_directReport),
          workingStyle: Value(_workingStyleCtrl.text.trim().isEmpty
              ? null
              : _workingStyleCtrl.text.trim()),
          notes: Value(_colleagueNotesCtrl.text.trim().isEmpty
              ? null
              : _colleagueNotesCtrl.text.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    // Cascade to active programme links — auto-publish on save.
    if (mounted) {
      final fresh = await widget.db.peopleDao.getPersonById(id);
      final projectName = context
              .read<ProjectProvider>()
              .currentProject
              ?.name ??
          'project';
      if (fresh != null && mounted) {
        // ignore: use_build_context_synchronously
        await _cascadeFor(context).pushPerson(
          fresh,
          sourceProjectName: projectName,
        );
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  /// Resolves a CascadeService from the live providers. Same idiom
  /// as the other auto-cascade forms (charter, status reports).
  CascadeService _cascadeFor(BuildContext context) =>
      buildCascadeService(context);

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.person != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Person' : 'New Person'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownField(
                  label: 'Category',
                  value: _personType,
                  items: _personTypes,
                  onChanged: (v) => setState(() => _personType = v!),
                ),
                const SizedBox(height: 6),
                // Stakeholder is orthogonal to category — anyone can be one.
                CheckboxListTile(
                  value: _isStakeholder,
                  onChanged: (v) =>
                      setState(() => _isStakeholder = v ?? false),
                  title: const Text(
                    'Track as project stakeholder',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Shows on the Stakeholders tab and unlocks influence / stance fields.',
                    style: TextStyle(fontSize: 11, color: KColors.textDim),
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _roleCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Role'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _orgCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Organisation'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _emailCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Phone'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _teamsCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Teams handle / Slack'),
                ),
                // Stakeholder-specific fields
                if (_isStakeholder) ...[
                  const SizedBox(height: 16),
                  const Divider(color: KColors.border),
                  const SizedBox(height: 8),
                  const Text('Stakeholder profile',
                      style: TextStyle(
                          color: KColors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownField(
                          label: 'Influence',
                          value: _influence,
                          items: _influences,
                          onChanged: (v) =>
                              setState(() => _influence = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownField(
                          label: 'Interest',
                          value: _interest,
                          items: _interests,
                          onChanged: (v) =>
                              setState(() => _interest = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownField(
                          label: 'Stance',
                          value: _stance,
                          items: _stances,
                          onChanged: (v) => setState(() => _stance = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _engagementCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Engagement strategy'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _stakeholderNotesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
                // Colleague-specific fields
                if (_personType == 'colleague') ...[
                  const SizedBox(height: 16),
                  const Divider(color: KColors.border),
                  const SizedBox(height: 8),
                  const Text('Colleague profile',
                      style: TextStyle(
                          color: KColors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _teamCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Team'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwitchListTile(
                          title: const Text('Direct report',
                              style: TextStyle(fontSize: 13)),
                          value: _directReport,
                          onChanged: (v) =>
                              setState(() => _directReport = v),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _workingStyleCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Working style'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _colleagueNotesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Notes (private)'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

// ===========================================================================
// Programme People overview — one read-only People-Overview panel per
// linked project (coverage + stakeholder-role + team-role matrices).
// ===========================================================================

const _kStakeholderTiers = [
  ('accountable', 'ACCOUNTABLE'),
  ('active', 'ACTIVE'),
  ('affected', 'AFFECTED'),
];

const _kTeamGroups = [
  ('programme_leadership', 'Programme Leadership'),
  ('business_analysis', 'Business Analysis'),
  ('technology', 'Technology'),
  ('specialist', 'Specialist'),
  ('governance', 'Governance'),
];

/// Programme People page: pulls in each linked project's People overview
/// layout as its own read-only panel. Cascaded role matrices + people are
/// grouped by source project; the programme's own native overview (if any)
/// leads.
class _ProgrammePeopleView extends StatelessWidget {
  final String programmeId;
  final AppDatabase db;

  const _ProgrammePeopleView({required this.programmeId, required this.db});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final programmeName = provider.currentProject?.name ?? 'Programme';
    final projectsById = {for (final p in provider.projects) p.id: p};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(children: [
            const Icon(Icons.groups_2_outlined,
                color: KColors.amber, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text('People',
                  style: Theme.of(context).textTheme.headlineSmall,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
        Expanded(
          child: StreamBuilder<List<StakeholderRole>>(
            stream: db.stakeholderRoleDao.watchForProject(programmeId),
            builder: (context, srSnap) {
              return StreamBuilder<List<TeamRole>>(
                stream: db.teamRoleDao.watchForProject(programmeId),
                builder: (context, trSnap) {
                  return StreamBuilder<List<Person>>(
                    stream:
                        db.peopleDao.watchPersonsForProject(programmeId),
                    builder: (context, pSnap) {
                      final sRoles =
                          srSnap.data ?? const <StakeholderRole>[];
                      final tRoles = trSnap.data ?? const <TeamRole>[];
                      final persons = pSnap.data ?? const <Person>[];

                      // Collect source project ids across roles + people.
                      final sourceIds = <String>{
                        for (final r in sRoles)
                          if (r.sourceProjectId != null) r.sourceProjectId!,
                        for (final r in tRoles)
                          if (r.sourceProjectId != null) r.sourceProjectId!,
                        for (final p in persons)
                          if (p.sourceProjectId != null) p.sourceProjectId!,
                      };

                      String nameFor(String id) {
                        final n = projectsById[id]?.name;
                        if (n != null && n.isNotEmpty) return n;
                        final fromPerson = persons
                            .cast<Person?>()
                            .firstWhere(
                                (p) => p!.sourceProjectId == id,
                                orElse: () => null)
                            ?.sourceProjectName;
                        return fromPerson ?? 'Linked project';
                      }

                      final orderedIds = sourceIds.toList()
                        ..sort((a, b) => nameFor(a)
                            .toLowerCase()
                            .compareTo(nameFor(b).toLowerCase()));

                      final nativeS = sRoles
                          .where((r) => r.sourceProjectId == null)
                          .toList();
                      final nativeT = tRoles
                          .where((r) => r.sourceProjectId == null)
                          .toList();
                      final hasNative =
                          nativeS.isNotEmpty || nativeT.isNotEmpty;

                      if (orderedIds.isEmpty && !hasNative) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                                'Link a project and its People overview '
                                'appears here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: KColors.textDim)),
                          ),
                        );
                      }

                      final projectCount =
                          orderedIds.length + (hasNative ? 1 : 0);

                      // Worst-covered project: lowest combined
                      // (stakeholder + team) fill ratio among projects
                      // that actually have role slots configured.
                      ({String label, double pct})? worst;
                      var ranked = 0;
                      void consider(String label,
                          List<StakeholderRole> s, List<TeamRole> t) {
                        final sc = CoverageCalculator.forStakeholders(s);
                        final tc = CoverageCalculator.forTeam(t);
                        final applicable = sc.applicable + tc.applicable;
                        if (applicable == 0) return;
                        ranked++;
                        final pct = (sc.filled + tc.filled) / applicable;
                        if (worst == null || pct < worst!.pct) {
                          worst = (label: label, pct: pct);
                        }
                      }

                      if (hasNative) {
                        consider(programmeName, nativeS, nativeT);
                      }
                      for (final id in orderedIds) {
                        consider(
                          nameFor(id),
                          sRoles
                              .where((r) => r.sourceProjectId == id)
                              .toList(),
                          tRoles
                              .where((r) => r.sourceProjectId == id)
                              .toList(),
                        );
                      }

                      return Column(
                        children: [
                          _PortfolioCoverageStrip(
                            stakeholders:
                                CoverageCalculator.forStakeholders(sRoles),
                            team: CoverageCalculator.forTeam(tRoles),
                            projectCount: projectCount,
                            stakeholderCount:
                                persons.where((p) => p.isStakeholder).length,
                            gapCount:
                                sRoles.where((r) => r.gapFlag).length,
                            // Only worth calling out when ≥2 projects have
                            // matrices to compare.
                            worstLabel: ranked >= 2 ? worst?.label : null,
                            worstPct: ranked >= 2 ? worst?.pct : null,
                          ),
                          Expanded(
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              children: [
                                if (hasNative)
                                  _ProjectOverviewPanel(
                                    label: programmeName,
                                    isCascaded: false,
                                    stakeholderRoles: nativeS,
                                    teamRoles: nativeT,
                                    persons: persons,
                                    initiallyExpanded: true,
                                  ),
                                for (final id in orderedIds)
                                  _ProjectOverviewPanel(
                                    label: nameFor(id),
                                    isCascaded: true,
                                    stakeholderRoles: sRoles
                                        .where((r) => r.sourceProjectId == id)
                                        .toList(),
                                    teamRoles: tRoles
                                        .where((r) => r.sourceProjectId == id)
                                        .toList(),
                                    persons: persons,
                                    initiallyExpanded:
                                        orderedIds.length == 1,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Programme-wide coverage roll-up pinned above the per-project panels.
/// Aggregates filled/applicable role slots across every project so the
/// programme manager gets a one-glance portfolio read.
class _PortfolioCoverageStrip extends StatelessWidget {
  final CoverageResult stakeholders;
  final CoverageResult team;
  final int projectCount;
  final int stakeholderCount;
  final int gapCount;
  final String? worstLabel;
  final double? worstPct;

  const _PortfolioCoverageStrip({
    required this.stakeholders,
    required this.team,
    required this.projectCount,
    required this.stakeholderCount,
    required this.gapCount,
    this.worstLabel,
    this.worstPct,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('PORTFOLIO COVERAGE',
                style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
            const Spacer(),
            Flexible(
              child: Text(
                  '$projectCount project${projectCount == 1 ? '' : 's'}'
                  ' · $stakeholderCount stakeholder${stakeholderCount == 1 ? '' : 's'}'
                  '${gapCount > 0 ? ' · $gapCount gap${gapCount == 1 ? '' : 's'}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: KColors.textMuted, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 12),
          _PortfolioBar(label: 'Stakeholders', result: stakeholders),
          const SizedBox(height: 8),
          _PortfolioBar(label: 'Team', result: team),
          if (worstLabel != null && worstPct != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: KColors.amberDim.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                const Icon(Icons.trending_down,
                    size: 13, color: KColors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(
                          text: 'Lowest coverage: ',
                          style: TextStyle(
                              color: KColors.textDim, fontSize: 11)),
                      TextSpan(
                          text: worstLabel!,
                          style: const TextStyle(
                              color: KColors.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                      TextSpan(
                          text: '  ${(worstPct! * 100).round()}%',
                          style: const TextStyle(
                              color: KColors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PortfolioBar extends StatelessWidget {
  final String label;
  final CoverageResult result;
  const _PortfolioBar({required this.label, required this.result});

  @override
  Widget build(BuildContext context) {
    final pct = result.percentage;
    final color = result.isFull ? KColors.phosphor : KColors.amber;
    return Row(children: [
      SizedBox(
          width: 84,
          child: Text(label,
              style: const TextStyle(color: KColors.text, fontSize: 12))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: KColors.surface2,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 78,
        child: Text(
            result.applicable == 0
                ? 'no roles'
                : '${(pct * 100).round()}%  ${result.filled}/${result.applicable}',
            textAlign: TextAlign.right,
            style: TextStyle(
                color: result.applicable == 0 ? KColors.textMuted : color,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

/// One project's People overview, read-only, collapsible.
class _ProjectOverviewPanel extends StatelessWidget {
  final String label;
  final bool isCascaded;
  final List<StakeholderRole> stakeholderRoles;
  final List<TeamRole> teamRoles;
  final List<Person> persons;
  final bool initiallyExpanded;

  const _ProjectOverviewPanel({
    required this.label,
    required this.isCascaded,
    required this.stakeholderRoles,
    required this.teamRoles,
    required this.persons,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final sCov = CoverageCalculator.forStakeholders(stakeholderRoles);
    final tCov = CoverageCalculator.forTeam(teamRoles);
    final sPct = (sCov.percentage * 100).round();
    final tPct = (tCov.percentage * 100).round();
    final gaps = stakeholderRoles.where((r) => r.gapFlag).length;

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: Icon(isCascaded ? Icons.link : Icons.workspaces_outlined,
              size: 16, color: KColors.textDim),
          title: Text(label,
              style: const TextStyle(
                  color: KColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
          subtitle: Text(
              'Stakeholders $sPct% · Team $tPct%'
              '${gaps > 0 ? ' · $gaps gap${gaps == 1 ? '' : 's'}' : ''}',
              style: const TextStyle(color: KColors.textDim, fontSize: 11)),
          children: [
            CoverageIndicator(stakeholders: sCov, team: tCov),
            const SizedBox(height: 4),
            if (stakeholderRoles.isEmpty && teamRoles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    'No coverage matrix defined in this project yet.',
                    style: TextStyle(color: KColors.textMuted, fontSize: 12)),
              ),
            if (stakeholderRoles.isNotEmpty) ...[
              const _OverviewSectionLabel('STAKEHOLDERS'),
              for (final (type, tierLabel) in _kStakeholderTiers)
                _ReadOnlyTier(
                  label: tierLabel,
                  roles: stakeholderRoles
                      .where((r) => r.roleType == type && r.isApplicable)
                      .toList(),
                  persons: persons,
                ),
            ],
            if (teamRoles.isNotEmpty) ...[
              const SizedBox(height: 12),
              const _OverviewSectionLabel('TEAM'),
              for (final (group, groupLabel) in _kTeamGroups)
                _ReadOnlyTeamGroup(
                  label: groupLabel,
                  roles: teamRoles
                      .where((r) => r.teamGroup == group && r.isApplicable)
                      .toList(),
                  persons: persons,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Read-only tier (accountable/active/affected) of stakeholder role slots.
class _ReadOnlyTier extends StatelessWidget {
  final String label;
  final List<StakeholderRole> roles;
  final List<Person> persons;

  const _ReadOnlyTier(
      {required this.label, required this.roles, required this.persons});

  @override
  Widget build(BuildContext context) {
    if (roles.isEmpty) return const SizedBox.shrink();
    final filled = roles.where((r) => r.personId != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Row(children: [
            Text(label,
                style: const TextStyle(
                    color: KColors.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.15)),
            const Spacer(),
            Flexible(
              child: Text('$filled of ${roles.length} filled',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: KColors.textMuted, fontSize: 10)),
            ),
          ]),
        ),
        for (final role in roles)
          _ReadOnlyRoleRow(
            roleName: role.roleName,
            person: _personFor(role.personId, persons),
            priority: role.priority,
            engagementStatus: role.engagementStatus,
            gapFlag: role.gapFlag,
            gapDescription: role.gapDescription,
          ),
      ],
    );
  }
}

/// Read-only team-group of role slots.
class _ReadOnlyTeamGroup extends StatelessWidget {
  final String label;
  final List<TeamRole> roles;
  final List<Person> persons;

  const _ReadOnlyTeamGroup(
      {required this.label, required this.roles, required this.persons});

  @override
  Widget build(BuildContext context) {
    if (roles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(label,
              style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.15)),
        ),
        for (final role in roles)
          _ReadOnlyRoleRow(
            roleName: role.roleName,
            person: _personFor(role.personId, persons),
          ),
      ],
    );
  }
}

Person? _personFor(String? personId, List<Person> persons) {
  if (personId == null) return null;
  return persons
      .cast<Person?>()
      .firstWhere((p) => p!.id == personId, orElse: () => null);
}

/// A single read-only role slot: filled indicator + role + assignee +
/// engagement/priority/gap chips.
class _ReadOnlyRoleRow extends StatelessWidget {
  final String roleName;
  final Person? person;
  final String? priority;
  final String? engagementStatus;
  final bool gapFlag;
  final String? gapDescription;

  const _ReadOnlyRoleRow({
    required this.roleName,
    required this.person,
    this.priority,
    this.engagementStatus,
    this.gapFlag = false,
    this.gapDescription,
  });

  @override
  Widget build(BuildContext context) {
    final filled = person != null;
    final chips = <Widget>[
      if (priority != null) _miniChip(_priorityLabel(priority!), _priorityColor(priority!)),
      if (engagementStatus != null)
        _miniChip(_engagementLabel(engagementStatus!), _engagementColor(engagementStatus!)),
      if (gapFlag) _miniChip('⚠ GAP', KColors.red),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: filled ? KColors.border2 : KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 8),
          child: Icon(filled ? Icons.circle : Icons.circle_outlined,
              size: 9,
              color: filled ? KColors.phosphor : KColors.textMuted),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(roleName,
                style: TextStyle(
                    color: filled ? KColors.text : KColors.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            if (filled) ...[
              const SizedBox(height: 1),
              Text(
                  [person!.name, person!.role, person!.organisation]
                      .where((s) => s != null && s.isNotEmpty)
                      .join(' · '),
                  style: const TextStyle(color: KColors.textDim, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ] else
              const Text('Unfilled',
                  style: TextStyle(color: KColors.textMuted, fontSize: 11)),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 5),
              Wrap(spacing: 5, runSpacing: 4, children: chips),
            ],
            if (gapFlag && gapDescription != null) ...[
              const SizedBox(height: 3),
              Text(gapDescription!,
                  style: const TextStyle(color: KColors.red, fontSize: 10)),
            ],
          ]),
        ),
      ]),
    );
  }

  static Widget _miniChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      );

  static String _priorityLabel(String p) => switch (p) {
        'critical' => '● Critical',
        'high' => '▲ High',
        'medium' => '◆ Medium',
        _ => '○ Low',
      };
  static Color _priorityColor(String p) => switch (p) {
        'critical' => KColors.red,
        'high' => KColors.amber,
        'medium' => KColors.phosphor,
        _ => KColors.textMuted,
      };
  static String _engagementLabel(String s) => switch (s) {
        'engaged' => '● Engaged',
        'gap_action_required' => '⚠ Gap',
        'not_engaged' => '○ Not engaged',
        'complete' => '✓ Complete',
        _ => '— Not started',
      };
  static Color _engagementColor(String s) => switch (s) {
        'engaged' || 'complete' => KColors.phosphor,
        'gap_action_required' => KColors.red,
        'not_engaged' => KColors.amber,
        _ => KColors.textMuted,
      };
}
