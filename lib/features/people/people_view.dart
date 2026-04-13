import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../shared/theme/keel_colors.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/utils/date_utils.dart' as du;

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
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project to view people.'));
    }
    final db = context.read<AppDatabase>();

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
                onPressed: () =>
                    _showPersonForm(context, projectId, db, null, null),
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
              _PersonsList(
                projectId: projectId,
                db: db,
                personType: 'stakeholder',
                onEdit: (p) =>
                    _showPersonForm(context, projectId, db, p, 'stakeholder'),
              ),
              _PersonsList(
                projectId: projectId,
                db: db,
                personType: 'colleague',
                onEdit: (p) =>
                    _showPersonForm(context, projectId, db, p, 'colleague'),
              ),
              _PersonsList(
                projectId: projectId,
                db: db,
                personType: 'exec',
                onEdit: (p) =>
                    _showPersonForm(context, projectId, db, p, 'exec'),
              ),
              _PersonsList(
                projectId: projectId,
                db: db,
                personType: 'vendor',
                onEdit: (p) =>
                    _showPersonForm(context, projectId, db, p, 'vendor'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPersonForm(BuildContext context, String projectId, AppDatabase db,
      Person? person, String? defaultType) {
    showDialog(
      context: context,
      builder: (_) => _PersonFormDialog(
        projectId: projectId,
        db: db,
        person: person,
        defaultType: defaultType ?? 'stakeholder',
      ),
    );
  }
}

class _PersonsList extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final String personType;
  final void Function(Person) onEdit;

  const _PersonsList({
    required this.projectId,
    required this.db,
    required this.personType,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Person>>(
      stream: db.peopleDao.watchPersonsByType(projectId, personType),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final persons = snap.data!;
        if (persons.isEmpty) {
          return Center(
            child: Text(
              switch (personType) {
                'stakeholder' => 'No stakeholders added yet.',
                'colleague' => 'No team members added yet.',
                'exec' => 'No executives added yet.',
                'vendor' => 'No vendors added yet.',
                _ => 'No people added yet.',
              },
              style: const TextStyle(color: KColors.textDim),
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
                                fontSize: 9,
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
              if (person.personType == 'stakeholder')
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
                Text(
                  person.email!,
                  style: const TextStyle(
                      color: KColors.textDim, fontSize: 12),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: KColors.red),
                onPressed: () => db.peopleDao.deletePerson(person.id),
              ),
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
                    if (person.personType == 'stakeholder')
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

  const _PersonFormDialog({
    required this.projectId,
    required this.db,
    this.person,
    required this.defaultType,
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

  // Stakeholder fields
  late TextEditingController _engagementCtrl;
  late TextEditingController _stakeholderNotesCtrl;
  String _influence = 'medium';
  String _stance = 'unknown';

  // Colleague fields
  late TextEditingController _teamCtrl;
  late TextEditingController _workingStyleCtrl;
  late TextEditingController _colleagueNotesCtrl;
  bool _directReport = false;

  final _personTypes = ['stakeholder', 'colleague', 'vendor', 'exec'];
  final _influences = ['high', 'medium', 'low'];
  final _stances = ['sponsor', 'supporter', 'neutral', 'resistant', 'unknown'];

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
    _personType = p?.personType ?? widget.defaultType;

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
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (_personType == 'stakeholder') {
      final existing =
          await widget.db.peopleDao.getStakeholderByPersonId(id);
      final spId = existing?.id ?? const Uuid().v4();
      await widget.db.peopleDao.upsertStakeholder(
        StakeholderProfilesCompanion(
          id: Value(spId),
          projectId: Value(widget.projectId),
          personId: Value(id),
          influence: Value(_influence),
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
    } else if (_personType == 'colleague') {
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

    if (mounted) Navigator.of(context).pop();
  }

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
                  label: 'Type',
                  value: _personType,
                  items: _personTypes,
                  onChanged: (v) => setState(() => _personType = v!),
                ),
                const SizedBox(height: 12),
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
                if (_personType == 'stakeholder') ...[
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
