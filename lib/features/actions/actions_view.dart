import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/source_badge.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../timeline/timeline_chart.dart' show parseHexColor;
import 'action_form.dart';
import 'actions_kanban.dart';

class ActionsView extends StatefulWidget {
  const ActionsView({super.key});

  @override
  State<ActionsView> createState() => _ActionsViewState();
}

class _ActionsViewState extends State<ActionsView> {
  bool _showBoard = false;
  String? _ownerFilter; // null = All
  List<Person> _persons = [];
  String? _projectId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId != _projectId) {
      _projectId = projectId;
      if (projectId != null) {
        _loadPrefs(projectId);
        _loadPersons(projectId);
      }
    }
  }

  Future<void> _loadPrefs(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final board = prefs.getBool('keel_actions_view_board_$projectId') ?? false;
    if (mounted) setState(() => _showBoard = board);
  }

  Future<void> _savePrefs(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keel_actions_view_board_$projectId', _showBoard);
  }

  Future<void> _loadPersons(String projectId) async {
    final db = context.read<AppDatabase>();
    final persons = await db.peopleDao.getPersonsForProject(projectId);
    if (mounted) setState(() => _persons = persons);
  }

  void _toggleView(bool board) {
    setState(() => _showBoard = board);
    if (_projectId != null) _savePrefs(_projectId!);
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(
          child: Text('Select a project to view actions.',
              style: TextStyle(color: KColors.textDim)));
    }

    final db = context.read<AppDatabase>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.check_circle, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('ACTIONS',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) =>
                      ActionFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Action'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Filter / view row
          Row(
            children: [
              _OwnerFilter(
                persons: _persons,
                selected: _ownerFilter,
                onChanged: (v) => setState(() => _ownerFilter = v),
              ),
              const SizedBox(width: 10),
              _ViewToggle(
                showBoard: _showBoard,
                onChanged: _toggleView,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<ActionCategory>>(
              stream: db.actionCategoriesDao.watchForProject(projectId),
              builder: (context, catSnap) {
                final catMap = <String, ActionCategory>{
                  for (final c in catSnap.data ?? []) c.id: c
                };
                return StreamBuilder<List<ProjectAction>>(
                  stream: db.actionsDao.watchActionsForProject(projectId),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    // Apply owner filter
                    final items = _ownerFilter == null
                        ? snap.data!
                        : snap.data!
                            .where((a) => a.owner == _ownerFilter)
                            .toList();

                    if (items.isEmpty && !_showBoard) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 40, color: KColors.textMuted),
                            const SizedBox(height: 12),
                            const Text('No actions yet.',
                                style: TextStyle(color: KColors.textDim)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => ActionFormDialog(
                                    projectId: projectId, db: db),
                              ),
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('Add Action'),
                            ),
                          ],
                        ),
                      );
                    }

                    if (_showBoard) {
                      return ActionsKanban(
                        actions: items,
                        catMap: catMap,
                        db: db,
                        projectId: projectId,
                      );
                    }

                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (ctx, i) => _ActionCard(
                        action: items[i],
                        db: db,
                        projectId: projectId,
                        category: items[i].categoryId != null
                            ? catMap[items[i].categoryId!]
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── View toggle ───────────────────────────────────────────────────────────────

class _ViewToggle extends StatelessWidget {
  final bool showBoard;
  final ValueChanged<bool> onChanged;

  const _ViewToggle({required this.showBoard, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KColors.surface2,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: KColors.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            icon: Icons.list_outlined,
            label: 'List',
            active: !showBoard,
            onTap: () => onChanged(false),
            isFirst: true,
          ),
          _ToggleButton(
            icon: Icons.view_kanban_outlined,
            label: 'Board',
            active: showBoard,
            onTap: () => onChanged(true),
            isFirst: false,
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool isFirst;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? KColors.amber.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(2) : Radius.zero,
            right: isFirst ? Radius.zero : const Radius.circular(2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13, color: active ? KColors.amber : KColors.textDim),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? KColors.amber : KColors.textDim,
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Owner filter ──────────────────────────────────────────────────────────────

class _OwnerFilter extends StatelessWidget {
  final List<Person> persons;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _OwnerFilter({
    required this.persons,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final names = persons.map((p) => p.name).toSet().toList()..sort();
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: KColors.border2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selected,
          isDense: true,
          style: const TextStyle(color: KColors.textDim, fontSize: 11),
          dropdownColor: KColors.surface2,
          icon: const Icon(Icons.expand_more, size: 14, color: KColors.textDim),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All owners',
                  style: TextStyle(color: KColors.textDim, fontSize: 11)),
            ),
            ...names.map((n) => DropdownMenuItem<String?>(
                  value: n,
                  child: Text(n,
                      style:
                          const TextStyle(color: KColors.text, fontSize: 11)),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Action card (list view) ───────────────────────────────────────────────────

Color _actionBarColor(ProjectAction action, ActionCategory? category) {
  if (category != null) return parseHexColor(category.color);
  if (action.status == 'closed') return KColors.phosphor;
  final isOverdue = action.dueDate != null &&
      action.status != 'closed' &&
      action.dueDate!
              .compareTo(DateTime.now().toIso8601String().substring(0, 10)) <
          0;
  if (isOverdue) return KColors.red;
  return KColors.amber;
}

class _ActionCard extends StatelessWidget {
  final ProjectAction action;
  final AppDatabase db;
  final String projectId;
  final ActionCategory? category;

  const _ActionCard({
    required this.action,
    required this.db,
    required this.projectId,
    required this.category,
  });

  bool get _isOverdue {
    if (action.dueDate == null || action.status == 'closed') return false;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return action.dueDate!.compareTo(today) < 0;
  }

  @override
  Widget build(BuildContext context) {
    final barColor = _actionBarColor(action, category);

    return Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => ActionFormDialog(
              projectId: projectId,
              db: db,
              action: action,
              startInViewMode: true),
        ),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category / status colour bar
              Container(
                width: 3,
                height: 48,
                color: barColor,
                margin: const EdgeInsets.only(right: 12),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (action.ref != null) ...[
                          Text(action.ref!,
                              style: const TextStyle(
                                  color: KColors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                        ],
                        // Category pill
                        if (category != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: parseHexColor(category!.color)
                                  .withAlpha(35),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              category!.name,
                              style: TextStyle(
                                color: parseHexColor(category!.color),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        // Recurrence icon
                        if (action.recurrenceGroupId != null) ...[
                          const Tooltip(
                            message: 'Recurring',
                            child: Icon(Icons.repeat,
                                size: 12, color: KColors.textDim),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(action.description,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                  color: KColors.text)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        StatusChip(status: action.status),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (action.owner != null &&
                                  action.owner!.isNotEmpty) ...[
                                const Icon(Icons.person_outline,
                                    size: 11, color: KColors.textDim),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(action.owner!,
                                      style: const TextStyle(
                                          color: KColors.textDim, fontSize: 11),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (action.dueDate != null) ...[
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 11,
                                  color: _isOverdue
                                      ? KColors.red
                                      : KColors.textDim,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  du.formatDate(action.dueDate),
                                  style: TextStyle(
                                    color: _isOverdue
                                        ? KColors.red
                                        : KColors.textDim,
                                    fontSize: 11,
                                    fontWeight: _isOverdue
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        SourceBadge(source: action.source),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 16, color: KColors.textMuted),
                onSelected: (val) async {
                  if (val == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) => ActionFormDialog(
                          projectId: projectId, db: db, action: action),
                    );
                  } else if (val == 'close') {
                    db.actionsDao.upsertAction(
                      ProjectActionsCompanion(
                        id: Value(action.id),
                        projectId: Value(action.projectId),
                        description: Value(action.description),
                        status: const Value('closed'),
                        updatedAt: Value(DateTime.now()),
                      ),
                    );
                  } else if (val == 'delete') {
                    db.actionsDao.deleteAction(action.id);
                  } else if (val == 'delete_series') {
                    db.actionsDao
                        .deleteByRecurrenceGroup(action.recurrenceGroupId!);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                      value: 'close', child: Text('Mark Closed')),
                  const PopupMenuItem(
                      value: 'delete', child: Text('Delete this')),
                  if (action.recurrenceGroupId != null)
                    const PopupMenuItem(
                        value: 'delete_series',
                        child: Text('Delete all in series')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
