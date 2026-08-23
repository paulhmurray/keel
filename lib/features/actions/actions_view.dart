import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/cascade/cascade_service.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/cascaded_source_badge.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/source_badge.dart';
import '../../shared/utils/avatar_utils.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../canvas/canvas_drag_source.dart';
import '../canvas/in_canvas_indicator.dart';
import '../programme/overdue_cascade_panel.dart';
import '../timeline/timeline_chart.dart' show parseHexColor;
import 'action_form.dart';
import 'action_grouping.dart';
import 'actions_kanban.dart';

class ActionsView extends StatefulWidget {
  const ActionsView({super.key});

  @override
  State<ActionsView> createState() => _ActionsViewState();
}

class _ActionsViewState extends State<ActionsView> {
  bool _showBoard = false;
  bool _showOldClosed = false;
  String? _ownerFilter; // null = All; _kUnassignedKey = no owner
  String? _projectId;
  Map<String, String> _planTagMap = {}; // activityId → "[WP] Activity name"
  final Set<String> _collapsedParents = {};

  static const int _closedHideAfterDays = 14;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId != _projectId) {
      _projectId = projectId;
      if (projectId != null) {
        _loadPrefs(projectId);
        _loadPlanTags(projectId);
      }
    }
  }

  Future<void> _loadPrefs(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final board = prefs.getBool('keel_actions_view_board_$projectId') ?? false;
    final showOld =
        prefs.getBool('keel_actions_show_old_closed_$projectId') ?? false;
    if (mounted) {
      setState(() {
        _showBoard = board;
        _showOldClosed = showOld;
      });
    }
  }

  Future<void> _savePrefs(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keel_actions_view_board_$projectId', _showBoard);
    await prefs.setBool(
        'keel_actions_show_old_closed_$projectId', _showOldClosed);
  }

  bool _isOldClosed(ProjectAction a) =>
      isOldClosed(a, hideAfterDays: _closedHideAfterDays);

  /// Everything shown when "show old closed" is off:
  ///   - retired groups (closed parent, all descendants closed) drop
  ///     immediately, board and list alike
  ///   - individually old-closed actions age out after two weeks — except
  ///     a parent that still has visible descendants, which must stay so
  ///     its group keeps its swimlane/heading.
  List<ProjectAction> _visibleActions(List<ProjectAction> all) {
    final byId = {for (final a in all) a.id: a};
    final part = partitionByParent(all);
    final retired = retiredRootIds(all);

    String topRootOf(ProjectAction a) {
      var cursor = a;
      final seen = <String>{cursor.id};
      while (cursor.parentActionId != null) {
        final p = byId[cursor.parentActionId!];
        if (p == null || !seen.add(p.id)) break;
        cursor = p;
      }
      return cursor.id;
    }

    return all.where((a) {
      if (retired.contains(topRootOf(a))) return false;
      if (!_isOldClosed(a)) return true;
      return actionDescendantIds(a.id, part.childrenByParent)
          .any((id) => byId[id] != null && !_isOldClosed(byId[id]!));
    }).toList();
  }

  void _toggleShowOldClosed() {
    setState(() => _showOldClosed = !_showOldClosed);
    if (_projectId != null) _savePrefs(_projectId!);
  }

  Future<void> _loadPlanTags(String projectId) async {
    final db = context.read<AppDatabase>();
    final wps = await db.programmeGanttDao.getWorkPackages(projectId);
    final acts = await db.programmeGanttDao.getActivitiesForProject(projectId);
    if (!mounted) return;
    final tagMap = <String, String>{};
    for (final act in acts) {
      final wp = wps.cast<TimelineWorkPackage?>()
          .firstWhere((w) => w?.id == act.workPackageId, orElse: () => null);
      final label = wp != null ? '[${wp.shortCode ?? wp.name}] ${act.name}' : act.name;
      tagMap[act.id] = label;
    }
    setState(() => _planTagMap = tagMap);
  }

  bool _matchesOwnerFilter(ProjectAction a) {
    if (_ownerFilter == null) return true;
    if (_ownerFilter == _kUnassignedKey) {
      return a.owner == null || a.owner!.trim().isEmpty;
    }
    return a.owner == _ownerFilter;
  }

  Widget _buildBody({
    required BuildContext context,
    required String projectId,
    required AppDatabase db,
    required List<ProjectAction> allActions,
    required Map<String, ActionCategory> catMap,
  }) {
    final part = partitionByParent(allActions);
    final visible = _visibleListItems(part);

    if (visible.isEmpty && !_showBoard) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 40, color: KColors.textMuted),
            const SizedBox(height: 12),
            Text(
              _ownerFilter == null
                  ? 'No actions yet.'
                  : 'No actions for this filter.',
              style: const TextStyle(color: KColors.textDim),
            ),
            const SizedBox(height: 12),
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
      );
    }

    if (_showBoard) {
      return ActionsKanban(
        actions: allActions,
        catMap: catMap,
        db: db,
        projectId: projectId,
        planTagMap: _planTagMap,
        ownerMatches: _matchesOwnerFilter,
        ownerFilterActive: _ownerFilter != null,
      );
    }

    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (ctx, i) {
        final entry = visible[i];
        return Padding(
          padding: EdgeInsets.only(left: entry.depth >= 2 ? 26.0 : 0),
          child: _ActionCard(
          action: entry.action,
          db: db,
          projectId: projectId,
          category: entry.action.categoryId != null
              ? catMap[entry.action.categoryId!]
              : null,
          planTag: entry.action.planActivityId != null
              ? _planTagMap[entry.action.planActivityId!]
              : null,
          isParent: entry.isParent,
          isChild: entry.isChild,
          rollup: entry.rollup,
          isExpanded: entry.isParent
              ? !_collapsedParents.contains(entry.action.id)
              : null,
          onToggleExpand: entry.isParent
              ? () => setState(() {
                    if (_collapsedParents.contains(entry.action.id)) {
                      _collapsedParents.remove(entry.action.id);
                    } else {
                      _collapsedParents.add(entry.action.id);
                    }
                  })
              : null,
          ),
        );
      },
    );
  }

  /// Flattens the partition into the visible list order:
  /// for each visible root, the root card; then if it has children and the
  /// owner filter shows any of them, the matching children indented under it
  /// (unless the parent is collapsed).
  List<_ListEntry> _visibleListItems(
    ({
      List<ProjectAction> roots,
      Map<String, List<ProjectAction>> childrenByParent
    }) part,
  ) {
    final out = <_ListEntry>[];
    for (final root in part.roots) {
      final allChildren = part.childrenByParent[root.id] ?? const [];
      final matchingChildren =
          allChildren.where(_matchesOwnerFilter).toList();
      final rootMatches = _matchesOwnerFilter(root);
      final isParent = allChildren.isNotEmpty;
      // Parent visible if it matches OR has any matching children.
      // Non-parent root visible only if it matches.
      if (!rootMatches && matchingChildren.isEmpty && isParent) continue;
      if (!isParent && !rootMatches) continue;

      // Rollup spans the whole subtree, sub-tasks included.
      final subTasksByTask = {
        for (final c in allChildren)
          c.id: part.childrenByParent[c.id] ?? const <ProjectAction>[],
      };
      out.add(_ListEntry(
        action: root,
        isParent: isParent,
        isChild: false,
        rollup: isParent
            ? rollupFor([
                ...allChildren,
                ...subTasksByTask.values.expand((s) => s),
              ])
            : null,
      ));
      if (isParent && !_collapsedParents.contains(root.id)) {
        for (final c in matchingChildren) {
          out.add(_ListEntry(
              action: c, isParent: false, isChild: true, depth: 1));
          for (final s in (subTasksByTask[c.id] ?? const <ProjectAction>[])
              .where(_matchesOwnerFilter)) {
            out.add(_ListEntry(
                action: s, isParent: false, isChild: true, depth: 2));
          }
        }
      }
    }
    return out;
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
          // Programme-only roll-up. Hidden on project-kind installs;
          // hidden on programme installs with no overdue cascaded
          // actions. Surfaces what's slipping across the portfolio at
          // a glance, above the per-row list.
          const OverdueCascadePanel(kind: OverdueCascadeKind.action),
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
                    final all = snap.data!;
                    final visible =
                        _showOldClosed ? all : _visibleActions(all);
                    final hiddenOldClosed = all.length - visible.length;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _OwnerAvatarFilter(
                                actions: visible,
                                selected: _ownerFilter,
                                onChanged: (v) =>
                                    setState(() => _ownerFilter = v),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ClosedToggle(
                              showOld: _showOldClosed,
                              hiddenCount: hiddenOldClosed,
                              onTap: _toggleShowOldClosed,
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
                          child: _buildBody(
                            context: context,
                            projectId: projectId,
                            db: db,
                            allActions: visible,
                            catMap: catMap,
                          ),
                        ),
                      ],
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

// ── Closed-action toggle ──────────────────────────────────────────────────────

class _ClosedToggle extends StatelessWidget {
  final bool showOld;
  final int hiddenCount;
  final VoidCallback onTap;

  const _ClosedToggle({
    required this.showOld,
    required this.hiddenCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = showOld ? KColors.amber : KColors.textDim;
    return Tooltip(
      message: showOld
          ? 'Click to hide closed groups and closed actions older than 2 weeks'
          : hiddenCount == 0
              ? 'No old closed actions to show'
              : 'Click to show $hiddenCount hidden closed action${hiddenCount == 1 ? '' : 's'} (closed groups and actions older than 2 weeks)',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: showOld
                ? KColors.amber.withValues(alpha: 0.15)
                : KColors.surface2,
            border: Border.all(
              color: showOld ? KColors.amber : KColors.border2,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                showOld ? Icons.visibility : Icons.visibility_off_outlined,
                size: 13,
                color: activeColor,
              ),
              const SizedBox(width: 5),
              Text(
                showOld ? 'Showing old closed' : 'Hiding old closed',
                style: TextStyle(
                  color: activeColor,
                  fontSize: 11,
                  fontWeight:
                      showOld ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (!showOld && hiddenCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: KColors.border2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$hiddenCount',
                    style: const TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
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

// ── Owner avatar filter ───────────────────────────────────────────────────────

const String _kUnassignedKey = '__unassigned__';

class _OwnerAvatarFilter extends StatelessWidget {
  final List<ProjectAction> actions;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _OwnerAvatarFilter({
    required this.actions,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    int unassigned = 0;
    for (final a in actions) {
      final owner = a.owner?.trim();
      if (owner == null || owner.isEmpty) {
        unassigned++;
      } else {
        counts[owner] = (counts[owner] ?? 0) + 1;
      }
    }
    final owners = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _AllPill(
            selected: selected == null,
            count: actions.length,
            onTap: () => onChanged(null),
          ),
          for (final name in owners) ...[
            const SizedBox(width: 6),
            _OwnerAvatarBubble(
              name: name,
              count: counts[name]!,
              isSelected: selected == name,
              onTap: () => onChanged(selected == name ? null : name),
            ),
          ],
          if (unassigned > 0) ...[
            const SizedBox(width: 6),
            _UnassignedBubble(
              count: unassigned,
              isSelected: selected == _kUnassignedKey,
              onTap: () => onChanged(
                  selected == _kUnassignedKey ? null : _kUnassignedKey),
            ),
          ],
        ],
      ),
    );
  }
}

class _AllPill extends StatelessWidget {
  final bool selected;
  final int count;
  final VoidCallback onTap;

  const _AllPill({
    required this.selected,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: selected ? 'Showing all actions' : 'Show all actions',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? KColors.amber.withValues(alpha: 0.18)
                : KColors.surface2,
            border: Border.all(
              color: selected ? KColors.amber : KColors.border2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_outlined,
                size: 13,
                color: selected ? KColors.amber : KColors.textDim,
              ),
              const SizedBox(width: 5),
              Text(
                'All · $count',
                style: TextStyle(
                  color: selected ? KColors.amber : KColors.textDim,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerAvatarBubble extends StatelessWidget {
  final String name;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _OwnerAvatarBubble({
    required this.name,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorFromName(name);
    return Tooltip(
      message: '$name · $count action${count == 1 ? '' : 's'}',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isSelected ? 0.55 : 0.28),
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? KColors.amber : color.withValues(alpha: 0.6),
              width: isSelected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initialsFromName(name),
            style: const TextStyle(
              color: KColors.text,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _UnassignedBubble extends StatelessWidget {
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _UnassignedBubble({
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Unassigned · $count action${count == 1 ? '' : 's'}',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isSelected
                ? KColors.textMuted.withValues(alpha: 0.35)
                : KColors.surface2,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? KColors.amber : KColors.border2,
              width: isSelected ? 2 : 1,
              style: isSelected ? BorderStyle.solid : BorderStyle.solid,
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.person_off_outlined,
            size: 14,
            color: KColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ── List entry helper ─────────────────────────────────────────────────────────

class _ListEntry {
  final ProjectAction action;
  final bool isParent;
  final bool isChild;
  final GroupRollup? rollup;
  // 0 = top level, 1 = task under a parent, 2 = sub-task.
  final int depth;

  const _ListEntry({
    required this.action,
    required this.isParent,
    required this.isChild,
    this.rollup,
    this.depth = 0,
  });
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
  final String? planTag;
  final bool isParent;
  final bool isChild;
  final GroupRollup? rollup;
  final bool? isExpanded;
  final VoidCallback? onToggleExpand;

  const _ActionCard({
    required this.action,
    required this.db,
    required this.projectId,
    required this.category,
    this.planTag,
    this.isParent = false,
    this.isChild = false,
    this.rollup,
    this.isExpanded,
    this.onToggleExpand,
  });

  bool get _isOverdue {
    if (action.dueDate == null || action.status == 'closed') return false;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return action.dueDate!.compareTo(today) < 0;
  }

  @override
  Widget build(BuildContext context) {
    final barColor = _actionBarColor(action, category);

    final card = Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(
          color: isParent ? KColors.phosphor.withValues(alpha: 0.5) : KColors.border,
          width: isParent ? 1.3 : 1.0,
        ),
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
              if (isParent && onToggleExpand != null) ...[
                InkWell(
                  onTap: onToggleExpand,
                  borderRadius: BorderRadius.circular(2),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 2, vertical: 2),
                    child: Icon(
                      (isExpanded ?? true)
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 18,
                      color: KColors.phosphor,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
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
                        if (isParent) ...[
                          const Icon(Icons.account_tree_outlined,
                              size: 12, color: KColors.phosphor),
                          const SizedBox(width: 5),
                        ],
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
                        const SizedBox(width: 4),
                        InCanvasIndicator(
                          itemType: 'action',
                          itemId: action.id,
                        ),
                        if (planTag != null) ...[
                          const SizedBox(width: 4),
                          _PlanTag(label: planTag!),
                        ],
                        if (isParent && rollup != null) ...[
                          const SizedBox(width: 6),
                          _GroupRollupChip(rollup: rollup!),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (action.sourceProjectId != null)
                CascadedSourceBadge(sourceProjectId: action.sourceProjectId)
              else
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      size: 16, color: KColors.textMuted),
                  onSelected: (val) async {
                    if (val == 'edit') {
                      await showDialog(
                        context: context,
                        builder: (_) => ActionFormDialog(
                            projectId: projectId, db: db, action: action),
                      );
                      // Re-push after edit when escalated.
                      if (context.mounted && action.escalatedAt != null) {
                        final fresh =
                            await db.actionsDao.getActionById(action.id);
                        if (fresh != null && context.mounted) {
                          await _cascadeFor(context, db)
                              .pushAction(fresh);
                        }
                      }
                    } else if (val == 'close') {
                      await db.actionsDao.upsertAction(
                        ProjectActionsCompanion(
                          id: Value(action.id),
                          projectId: Value(action.projectId),
                          description: Value(action.description),
                          status: const Value('closed'),
                          updatedAt: Value(DateTime.now()),
                        ),
                      );
                      if (context.mounted &&
                          action.escalatedAt != null) {
                        final fresh =
                            await db.actionsDao.getActionById(action.id);
                        if (fresh != null && context.mounted) {
                          await _cascadeFor(context, db)
                              .pushAction(fresh);
                        }
                      }
                    } else if (val == 'escalate') {
                      await db.actionsDao
                          .setActionEscalated(action.id, true);
                      final fresh =
                          await db.actionsDao.getActionById(action.id);
                      if (fresh != null && context.mounted) {
                        await _cascadeFor(context, db).pushAction(fresh);
                      }
                    } else if (val == 'unescalate') {
                      if (context.mounted) {
                        await _cascadeFor(context, db).tombstoneRaidItem(
                          projectId: projectId,
                          itemKind: CascadeKinds.action,
                          itemId: action.id,
                        );
                      }
                      await db.actionsDao
                          .setActionEscalated(action.id, false);
                    } else if (val == 'delete') {
                      if (action.escalatedAt != null && context.mounted) {
                        await _cascadeFor(context, db).tombstoneRaidItem(
                          projectId: projectId,
                          itemKind: CascadeKinds.action,
                          itemId: action.id,
                        );
                      }
                      if (isParent) {
                        if (!context.mounted) return;
                        final ok = await _confirmDeleteParent(
                            context, action, rollup?.total ?? 0);
                        if (!ok) return;
                        await db.actionsDao
                            .deleteParentAndOrphanChildren(action.id);
                      } else {
                        await db.actionsDao.deleteAction(action.id);
                      }
                    } else if (val == 'delete_series') {
                      db.actionsDao
                          .deleteByRecurrenceGroup(
                              action.recurrenceGroupId!);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(
                        value: 'close', child: Text('Mark Closed')),
                    if (action.escalatedAt == null)
                      const PopupMenuItem(
                          value: 'escalate',
                          child: Text('Escalate to programme'))
                    else
                      const PopupMenuItem(
                          value: 'unescalate',
                          child: Text('Stop escalating')),
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

    if (!isChild) {
      return CanvasDragSource(
        itemType: 'action',
        itemId: action.id,
        title: action.description,
        body: action.outcome,
        child: card,
      );
    }

    // Children: subtle vertical guide-line on the left + indent.
    return Padding(
      padding: const EdgeInsets.only(left: 28),
      child: Stack(
        children: [
          Positioned(
            left: -16,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: KColors.border2),
          ),
          card,
        ],
      ),
    );
  }
}

// ── Group rollup chip ─────────────────────────────────────────────────────────

class _GroupRollupChip extends StatelessWidget {
  final GroupRollup rollup;
  const _GroupRollupChip({required this.rollup});

  @override
  Widget build(BuildContext context) {
    final parts = <(String, Color)>[
      if (rollup.todo > 0) ('${rollup.todo} open', KColors.textDim),
      if (rollup.inProgress > 0)
        ('${rollup.inProgress} in prog', KColors.amber),
      if (rollup.overdue > 0) ('${rollup.overdue} overdue', KColors.red),
      if (rollup.done > 0) ('${rollup.done} done', KColors.phosphor),
    ];
    if (parts.isEmpty) {
      return const Text('no children',
          style: TextStyle(color: KColors.textMuted, fontSize: 10));
    }
    return Tooltip(
      message: '${rollup.total} child action${rollup.total == 1 ? '' : 's'}'
          ' · ${rollup.done}/${rollup.total} done',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.border2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0)
                const Text(' · ',
                    style: TextStyle(color: KColors.textMuted, fontSize: 10)),
              Text(parts[i].$1,
                  style: TextStyle(
                      color: parts[i].$2,
                      fontSize: 10,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Resolves a CascadeService from the live providers. Shared between
/// the action row's escalate / unescalate / delete handlers so they
/// don't each duplicate the gateway resolution.
CascadeService _cascadeFor(BuildContext context, AppDatabase db) =>
    buildCascadeService(context);

Future<bool> _confirmDeleteParent(
    BuildContext context, ProjectAction parent, int childCount) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete group parent?'),
      content: Text(
        childCount == 0
            ? 'Delete "${parent.description}"? This cannot be undone.'
            : 'Delete "${parent.description}"? Its $childCount child '
                'action${childCount == 1 ? '' : 's'} will be kept and '
                'moved to top-level.',
        style: const TextStyle(color: KColors.textDim, fontSize: 12),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ── Plan tag pill ─────────────────────────────────────────────────────────────

class _PlanTag extends StatelessWidget {
  final String label;
  const _PlanTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: KColors.phosphor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: KColors.phosphor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 9, color: KColors.phosphor),
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: KColors.phosphor,
                    fontSize: 9,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
