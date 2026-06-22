import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/database/database.dart';
import '../../../../../shared/theme/keel_colors.dart';
import 'usm_model.dart';
import 'usm_story_panel.dart';

/// View for a single User Story Map template instance.
///
/// Layout (left → right, top → bottom):
///   Activity row  : [Discover] [Plan] [Book] …
///   Task row      :  Search · Compare    Pay    …  (each below its activity)
///   Release rows  : MVP, Release 2, … with stories in each (task × release) cell
///
/// Wide maps scroll horizontally; many-release maps scroll vertically.
/// Click a story to open a side panel for full editing.
class UsmView extends StatefulWidget {
  final CanvasTemplate template;

  const UsmView({super.key, required this.template});

  @override
  State<UsmView> createState() => _UsmViewState();
}

class _UsmViewState extends State<UsmView> {
  // Layout constants.
  static const double _taskColWidth = 200;
  static const double _activityHeaderHeight = 44;
  static const double _taskHeaderHeight = 36;
  static const double _releaseLabelWidth = 130;
  static const double _releaseRowMinHeight = 130;

  late UsmContent _content;
  String? _selectedStoryId;

  // Controllers for inline-edit name fields, keyed by entity id.
  final Map<String, TextEditingController> _activityCtrls = {};
  final Map<String, TextEditingController> _taskCtrls = {};
  final Map<String, TextEditingController> _releaseCtrls = {};

  // Single shared horizontal scroll controller — the header row and the
  // grid below share it so the columns stay aligned as the user scrolls.
  final ScrollController _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _content = UsmContent.decode(widget.template.content);
    _seedControllers();
  }

  @override
  void didUpdateWidget(covariant UsmView old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id) {
      _content = UsmContent.decode(widget.template.content);
      _disposeControllers();
      _seedControllers();
      _selectedStoryId = null;
    }
  }

  void _seedControllers() {
    for (final a in _content.activities) {
      _activityCtrls.putIfAbsent(
          a.id, () => TextEditingController(text: a.name));
      for (final t in a.tasks) {
        _taskCtrls.putIfAbsent(
            t.id, () => TextEditingController(text: t.name));
      }
    }
    for (final r in _content.releases) {
      _releaseCtrls.putIfAbsent(
          r.id, () => TextEditingController(text: r.name));
    }
  }

  void _disposeControllers() {
    for (final c in _activityCtrls.values) {
      c.dispose();
    }
    for (final c in _taskCtrls.values) {
      c.dispose();
    }
    for (final c in _releaseCtrls.values) {
      c.dispose();
    }
    _activityCtrls.clear();
    _taskCtrls.clear();
    _releaseCtrls.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    _hScroll.dispose();
    super.dispose();
  }

  // ---- Mutations ----------------------------------------------------------

  Future<void> _save(UsmContent next) async {
    setState(() => _content = next);
    final db = context.read<AppDatabase>();
    await db.canvasTemplatesDao.patchTemplate(
      widget.template.id,
      CanvasTemplatesCompanion(content: Value(next.encode())),
    );
  }

  void _addActivity() {
    final id = const Uuid().v4();
    _activityCtrls[id] = TextEditingController();
    final activities = [
      ..._content.activities,
      UsmActivity(id: id, sortOrder: _content.activities.length),
    ];
    _save(_content.copyWith(activities: activities));
  }

  void _renameActivity(String id, String name) {
    final updated = _content.activities
        .map((a) => a.id == id ? a.copyWith(name: name) : a)
        .toList();
    _save(_content.copyWith(activities: updated));
  }

  void _deleteActivity(String id) {
    final activity = _content.activities.firstWhere((a) => a.id == id);
    final taskIds = activity.tasks.map((t) => t.id).toSet();
    final filtered =
        _content.activities.where((a) => a.id != id).toList();
    final renumbered = [
      for (var i = 0; i < filtered.length; i++)
        filtered[i].copyWith(sortOrder: i),
    ];
    // Drop tasks and stories transitively.
    for (final t in activity.tasks) {
      _taskCtrls.remove(t.id)?.dispose();
    }
    _activityCtrls.remove(id)?.dispose();
    final stories =
        _content.stories.where((s) => !taskIds.contains(s.taskId)).toList();
    _save(_content.copyWith(activities: renumbered, stories: stories));
  }

  void _addTask(String activityId) {
    final id = const Uuid().v4();
    _taskCtrls[id] = TextEditingController();
    final updated = _content.activities.map((a) {
      if (a.id != activityId) return a;
      return a.copyWith(tasks: [
        ...a.tasks,
        UsmTask(id: id, sortOrder: a.tasks.length),
      ]);
    }).toList();
    _save(_content.copyWith(activities: updated));
  }

  void _renameTask(String activityId, String taskId, String name) {
    final updated = _content.activities.map((a) {
      if (a.id != activityId) return a;
      return a.copyWith(
        tasks: a.tasks
            .map((t) => t.id == taskId ? t.copyWith(name: name) : t)
            .toList(),
      );
    }).toList();
    _save(_content.copyWith(activities: updated));
  }

  void _deleteTask(String activityId, String taskId) {
    final updated = _content.activities.map((a) {
      if (a.id != activityId) return a;
      final filtered =
          a.tasks.where((t) => t.id != taskId).toList();
      final renumbered = [
        for (var i = 0; i < filtered.length; i++)
          filtered[i].copyWith(sortOrder: i),
      ];
      return a.copyWith(tasks: renumbered);
    }).toList();
    _taskCtrls.remove(taskId)?.dispose();
    // Drop stories under the removed task.
    final stories =
        _content.stories.where((s) => s.taskId != taskId).toList();
    _save(_content.copyWith(activities: updated, stories: stories));
  }

  void _addRelease() {
    final id = const Uuid().v4();
    _releaseCtrls[id] = TextEditingController(
        text: 'Release ${_content.releases.length + 1}');
    final next = [
      ..._content.releases,
      UsmRelease(
        id: id,
        name: 'Release ${_content.releases.length + 1}',
        sortOrder: _content.releases.length,
      ),
    ];
    _save(_content.copyWith(releases: next));
  }

  void _renameRelease(String id, String name) {
    final updated = _content.releases
        .map((r) => r.id == id ? r.copyWith(name: name) : r)
        .toList();
    _save(_content.copyWith(releases: updated));
  }

  void _deleteRelease(String id) {
    final filtered =
        _content.releases.where((r) => r.id != id).toList();
    final renumbered = [
      for (var i = 0; i < filtered.length; i++)
        filtered[i].copyWith(sortOrder: i),
    ];
    _releaseCtrls.remove(id)?.dispose();
    final stories =
        _content.stories.where((s) => s.releaseId != id).toList();
    _save(_content.copyWith(releases: renumbered, stories: stories));
  }

  void _addStory(String taskId, String releaseId) {
    final id = const Uuid().v4();
    final story = UsmStory(
      id: id,
      taskId: taskId,
      releaseId: releaseId,
    );
    _save(_content.copyWith(stories: [..._content.stories, story]));
    setState(() => _selectedStoryId = id);
  }

  void _updateStory(String id, UsmStory Function(UsmStory) edit) {
    final updated = _content.stories
        .map((s) => s.id == id ? edit(s) : s)
        .toList();
    _save(_content.copyWith(stories: updated));
  }

  void _deleteStory(String id) {
    final updated = _content.stories.where((s) => s.id != id).toList();
    if (_selectedStoryId == id) _selectedStoryId = null;
    _save(_content.copyWith(stories: updated));
  }

  void _moveStory(String id, String newTaskId, String newReleaseId) {
    _updateStory(
        id,
        (s) => s.copyWith(
              taskId: newTaskId,
              releaseId: newReleaseId,
            ));
  }

  void _selectStory(String id) {
    setState(() => _selectedStoryId = id);
  }

  void _closePanel() {
    setState(() => _selectedStoryId = null);
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selectedStory = _selectedStoryId == null
        ? null
        : _content.stories
            .where((s) => s.id == _selectedStoryId)
            .cast<UsmStory?>()
            .firstOrNull;
    return Row(
      children: [
        Expanded(child: _buildMap()),
        if (selectedStory != null)
          UsmStoryPanel(
            story: selectedStory,
            onTitleChanged: (v) =>
                _updateStory(selectedStory.id, (s) => s.copyWith(title: v)),
            onDescriptionChanged: (v) => _updateStory(
                selectedStory.id,
                (s) => s.copyWith(description: v.isEmpty ? null : v)),
            onEstimateChanged: (v) => _updateStory(
                selectedStory.id,
                (s) => s.copyWith(estimate: v.isEmpty ? null : v)),
            onTagsChanged: (tags) => _updateStory(
                selectedStory.id, (s) => s.copyWith(tags: tags)),
            onAcceptanceCriteriaChanged: (ac) => _updateStory(
                selectedStory.id,
                (s) => s.copyWith(acceptanceCriteria: ac)),
            onDelete: () => _deleteStory(selectedStory.id),
            onClose: _closePanel,
          ),
      ],
    );
  }

  Widget _buildMap() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          const SizedBox(height: 10),
          Expanded(
            child: _content.activities.isEmpty &&
                    _content.releases.isEmpty
                ? _EmptyState(
                    onAddActivity: _addActivity,
                    onAddRelease: _addRelease,
                  )
                : _scrollableMap(),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Row(
      children: [
        const Text(
          'USER STORY MAP',
          style: TextStyle(
            color: KColors.amber,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_content.activities.length} activities · '
          '${_content.allTasks.length} tasks · '
          '${_content.releases.length} releases · '
          '${_content.stories.length} stories',
          style: const TextStyle(
            color: KColors.textMuted,
            fontSize: 11,
          ),
        ),
        const Spacer(),
        _toolbarButton(
          label: 'Add activity',
          icon: Icons.add,
          onTap: _addActivity,
        ),
        const SizedBox(width: 8),
        _toolbarButton(
          label: 'Add release',
          icon: Icons.add,
          onTap: _addRelease,
        ),
      ],
    );
  }

  Widget _toolbarButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: KColors.amber,
        side: const BorderSide(color: KColors.amber),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: const TextStyle(fontSize: 12),
        minimumSize: const Size(0, 32),
      ),
    );
  }

  /// Visible column list — one entry per real task, OR one placeholder
  /// for any activity that doesn't have a task yet. Drives both the
  /// header rows and the per-release story cells so widths stay
  /// perfectly aligned.
  List<_UsmColumn> _visibleColumns() {
    final out = <_UsmColumn>[];
    for (final a in _content.activities) {
      if (a.tasks.isEmpty) {
        out.add(_UsmColumn(activity: a, task: null));
      } else {
        for (final t in a.tasks) {
          out.add(_UsmColumn(activity: a, task: t));
        }
      }
    }
    return out;
  }

  Widget _scrollableMap() {
    final columns = _visibleColumns();
    final gridWidth =
        (_releaseLabelWidth + columns.length * _taskColWidth)
            .clamp(_releaseLabelWidth.toDouble(), 99999.0);
    return Scrollbar(
      controller: _hScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _hScroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: gridWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerBands(),
              const SizedBox(height: 8),
              if (_content.releases.isEmpty)
                _noReleasesHint()
              else
                for (final r in _content.releases) _releaseRow(r),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noReleasesHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No releases yet.',
                style: TextStyle(
                  color: KColors.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Add a release band to start placing stories.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: KColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _addRelease,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add release'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KColors.amber,
                  side: const BorderSide(color: KColors.amber),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerBands() {
    final activities = _content.activities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Activities row — each activity spans 1 column (placeholder)
        // or one column per real task.
        Row(
          children: [
            SizedBox(width: _releaseLabelWidth, height: _activityHeaderHeight),
            for (final a in activities)
              _ActivityHeader(
                activity: a,
                width: (a.tasks.isEmpty ? 1 : a.tasks.length) *
                    _taskColWidth,
                height: _activityHeaderHeight,
                ctrl: _activityCtrls[a.id]!,
                onRename: (v) => _renameActivity(a.id, v),
                onAddTask: () => _addTask(a.id),
                onDelete: () => _deleteActivity(a.id),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Tasks row — one cell per visible column.
        Row(
          children: [
            SizedBox(width: _releaseLabelWidth, height: _taskHeaderHeight),
            for (final col in _visibleColumns())
              if (col.task == null)
                _PendingTaskCell(
                  width: _taskColWidth,
                  height: _taskHeaderHeight,
                  onAdd: () => _addTask(col.activity.id),
                )
              else
                _TaskHeader(
                  task: col.task!,
                  width: _taskColWidth,
                  height: _taskHeaderHeight,
                  ctrl: _taskCtrls[col.task!.id]!,
                  onRename: (v) =>
                      _renameTask(col.activity.id, col.task!.id, v),
                  onDelete: () =>
                      _deleteTask(col.activity.id, col.task!.id),
                ),
          ],
        ),
      ],
    );
  }

  Widget _releaseRow(UsmRelease release) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: KColors.border, width: 1),
        ),
      ),
      constraints:
          const BoxConstraints(minHeight: _releaseRowMinHeight),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          _ReleaseLabel(
            release: release,
            width: _releaseLabelWidth,
            ctrl: _releaseCtrls[release.id]!,
            onRename: (v) => _renameRelease(release.id, v),
            onDelete: () => _deleteRelease(release.id),
          ),
          // One cell per visible column — for activities without
          // tasks we render an inert placeholder so widths line up
          // with the header rows.
          for (final col in _visibleColumns())
            if (col.task == null)
              SizedBox(width: _taskColWidth)
            else
              _StoryCell(
                taskId: col.task!.id,
                releaseId: release.id,
                width: _taskColWidth,
                stories: _content.storiesAt(col.task!.id, release.id),
                selectedStoryId: _selectedStoryId,
                onAddStory: () =>
                    _addStory(col.task!.id, release.id),
                onSelectStory: _selectStory,
                onDropStory: (storyId) => _moveStory(
                    storyId, col.task!.id, release.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// Internal helper — represents one visible column in the grid. Either
/// a real (activity, task) pair or a placeholder for an activity that
/// has no tasks yet (so the activity header has somewhere to sit and
/// release rows can keep their widths aligned).
class _UsmColumn {
  final UsmActivity activity;
  final UsmTask? task;
  const _UsmColumn({required this.activity, required this.task});
}

// ---- Sub-widgets ----------------------------------------------------------

class _ActivityHeader extends StatelessWidget {
  final UsmActivity activity;
  final double width;
  final double height;
  final TextEditingController ctrl;
  final ValueChanged<String> onRename;
  final VoidCallback onAddTask;
  final VoidCallback onDelete;

  const _ActivityHeader({
    required this.activity,
    required this.width,
    required this.height,
    required this.ctrl,
    required this.onRename,
    required this.onAddTask,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: KColors.amberDim.withValues(alpha: 0.55),
        border: Border.all(color: KColors.amber.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(
                color: KColors.amber,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
              decoration: const InputDecoration(
                hintText: 'Activity',
                hintStyle:
                    TextStyle(color: KColors.textMuted, fontSize: 12),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onRename,
            ),
          ),
          IconButton(
            tooltip: 'Add task',
            visualDensity: VisualDensity.compact,
            onPressed: onAddTask,
            icon: const Icon(Icons.add, size: 14, color: KColors.amber),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 22, minHeight: 22),
          ),
          IconButton(
            tooltip: 'Delete activity',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(Icons.close,
                size: 13, color: KColors.amber),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 22, minHeight: 22),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown under an activity that has zero tasks yet — gives
/// the user an "Add first task" affordance without breaking the grid.
class _PendingTaskCell extends StatelessWidget {
  final double width;
  final double height;
  final VoidCallback onAdd;

  const _PendingTaskCell({
    required this.width,
    required this.height,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: KColors.surface2.withValues(alpha: 0.5),
        border: Border.all(
          color: KColors.border,
          width: 0.5,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add, size: 12),
        label: const Text('Add task'),
        style: TextButton.styleFrom(
          foregroundColor: KColors.textDim,
          textStyle: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}

class _TaskHeader extends StatelessWidget {
  final UsmTask task;
  final double width;
  final double height;
  final TextEditingController ctrl;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  const _TaskHeader({
    required this.task,
    required this.width,
    required this.height,
    required this.ctrl,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                hintText: 'Task',
                hintStyle: TextStyle(
                    color: KColors.textMuted, fontSize: 11.5),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onRename,
            ),
          ),
          IconButton(
            tooltip: 'Delete task',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(Icons.close,
                size: 12, color: KColors.textMuted),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 22, minHeight: 22),
          ),
        ],
      ),
    );
  }
}

class _ReleaseLabel extends StatelessWidget {
  final UsmRelease release;
  final double width;
  final TextEditingController ctrl;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  const _ReleaseLabel({
    required this.release,
    required this.width,
    required this.ctrl,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: KColors.border, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: null,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
              decoration: const InputDecoration(
                hintText: 'Release',
                hintStyle:
                    TextStyle(color: KColors.textMuted, fontSize: 12),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onRename,
            ),
          ),
          IconButton(
            tooltip: 'Delete release',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(Icons.close,
                size: 12, color: KColors.textMuted),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 22, minHeight: 22),
          ),
        ],
      ),
    );
  }
}

/// Drag payload for moving a story between cells.
class _StoryDragData {
  final String storyId;
  const _StoryDragData(this.storyId);
}

class _StoryCell extends StatelessWidget {
  final String taskId;
  final String releaseId;
  final double width;
  final List<UsmStory> stories;
  final String? selectedStoryId;
  final VoidCallback onAddStory;
  final ValueChanged<String> onSelectStory;
  final ValueChanged<String> onDropStory;

  const _StoryCell({
    required this.taskId,
    required this.releaseId,
    required this.width,
    required this.stories,
    required this.selectedStoryId,
    required this.onAddStory,
    required this.onSelectStory,
    required this.onDropStory,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_StoryDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => onDropStory(d.data.storyId),
      builder: (context, candidate, _) {
        final hover = candidate.isNotEmpty;
        return Container(
          width: width,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: KColors.surface,
            border: Border.all(
              color: hover
                  ? KColors.amber.withValues(alpha: 0.6)
                  : KColors.border,
              width: hover ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...stories.map((s) => _StoryCard(
                    key: ValueKey(s.id),
                    story: s,
                    isSelected: selectedStoryId == s.id,
                    onTap: () => onSelectStory(s.id),
                  )),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onAddStory,
                  icon: const Icon(Icons.add, size: 12),
                  label: const Text('Add story'),
                  style: TextButton.styleFrom(
                    foregroundColor: KColors.textDim,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StoryCard extends StatelessWidget {
  final UsmStory story;
  final bool isSelected;
  final VoidCallback onTap;

  const _StoryCard({
    super.key,
    required this.story,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: isSelected
            ? KColors.amberDim.withValues(alpha: 0.55)
            : KColors.surface2,
        border: Border.all(
          color: isSelected ? KColors.amber : KColors.border,
          width: isSelected ? 1.2 : 0.8,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            story.title.isEmpty ? '(untitled story)' : story.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          if (story.estimate != null && story.estimate!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: KColors.blue.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  story.estimate!,
                  style: const TextStyle(
                    color: KColors.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return LongPressDraggable<_StoryDragData>(
      data: _StoryDragData(story.id),
      delay: const Duration(milliseconds: 200),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: KColors.surface,
            border: Border.all(color: KColors.amber, width: 1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            story.title.isEmpty ? '(untitled)' : story.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KColors.amber,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: InkWell(
        onTap: onTap,
        child: card,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddActivity;
  final VoidCallback onAddRelease;

  const _EmptyState({
    required this.onAddActivity,
    required this.onAddRelease,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.view_week_outlined,
                  size: 28, color: KColors.amber),
              const SizedBox(height: 12),
              const Text(
                'Start mapping the user journey',
                style: TextStyle(
                  color: KColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'List the high-level user activities along the top, then '
                'break each one into tasks. Plot stories at each task '
                '× release intersection.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: KColors.textDim,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: onAddActivity,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add activity'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KColors.amberDim,
                      foregroundColor: KColors.amber,
                      elevation: 0,
                      side: const BorderSide(
                          color: KColors.amber, width: 0.5),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onAddRelease,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add release'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KColors.amber,
                      side: const BorderSide(color: KColors.amber),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
