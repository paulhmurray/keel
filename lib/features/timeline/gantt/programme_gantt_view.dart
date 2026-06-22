import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/cascade/cascade_service.dart';
import '../../../core/cascade/sync_cascade_gateway.dart';
import '../../../core/database/database.dart';
import '../../../core/sync/sync_client.dart';
import '../../../providers/sync_provider.dart';
import 'dependency_chains.dart';
import '../../../providers/project_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../shared/theme/keel_colors.dart';
import '../../../shared/widgets/date_picker_field.dart';
import '../../../shared/widgets/person_picker_field.dart';
import '../../actions/action_form.dart';
import 'milestone_tracker_view.dart';

// ─── Layout constants ─────────────────────────────────────────────────────────
const _kNameW = 350.0;
const _kCellW = 56.0;
const _kHeaderH = 40.0;
const _kWpRowH = 38.0;
const _kRowH = 38.0;

// ─── WP theme colours ─────────────────────────────────────────────────────────
Color _wpColor(String theme) => switch (theme) {
      'wp1'        => const Color(0xFF3B82F6), // blue
      'wp2'        => const Color(0xFF10B981), // emerald
      'wp3'        => const Color(0xFF8B5CF6), // purple
      'wp4'        => const Color(0xFFF59E0B), // amber
      'mpower'     => const Color(0xFF06B6D4), // cyan
      'governance' => const Color(0xFF6B7280), // grey
      _            => const Color(0xFF64748B), // slate default
    };

const _kThemes = ['wp1', 'wp2', 'wp3', 'wp4', 'mpower', 'governance', 'custom'];
const _kThemeLabels = {
  'wp1': 'Blue',
  'wp2': 'Emerald',
  'wp3': 'Purple',
  'wp4': 'Amber',
  'mpower': 'Cyan',
  'governance': 'Grey (Governance)',
  'custom': 'Custom',
};
const _kActivityTypes = [
  'activity', 'milestone', 'hard_deadline', 'dependency_marker', 'ongoing', 'gate',
];
const _kActivityTypeLabels = {
  'activity': 'Activity (bar)',
  'milestone': '◆ Milestone',
  'hard_deadline': '⚠ Hard Deadline',
  'dependency_marker': 'Dependency Marker',
  'ongoing': 'Ongoing / Recurring',
  'gate': '◈ Gate / Approval',
};
const _kRagStatuses = ['not_started', 'green', 'amber', 'red'];
const _kRagLabels = {
  'not_started': 'Not Started',
  'green': 'Green – On Track',
  'amber': 'Amber – At Risk',
  'red': 'Red – Off Track',
};

// ─── Keyboard intents ─────────────────────────────────────────────────────────
class _ZoomInIntent       extends Intent { const _ZoomInIntent(); }
class _ZoomOutIntent      extends Intent { const _ZoomOutIntent(); }
class _FitIntent          extends Intent { const _FitIntent(); }
class _ExpandIntent       extends Intent { const _ExpandIntent(); }
class _PresentationIntent extends Intent { const _PresentationIntent(); }

// ─── Row models ───────────────────────────────────────────────────────────────
sealed class _GRow {
  double get height;
}

class _WpRow extends _GRow {
  final TimelineWorkPackage wp;
  _WpRow(this.wp);
  @override double get height => _kWpRowH;
}

class _ActRow extends _GRow {
  final TimelineActivity act;
  final TimelineWorkPackage wp;
  _ActRow(this.act, this.wp);
  @override double get height => _kRowH;
}

/// Drag payload for reorder drags inside the name column. Two kinds:
/// `wp` carries the work package id; `activity` carries the activity id
/// plus its parent WP id so the drop logic can reject cross-WP drops
/// without an extra DB lookup.
class _ReorderPayload {
  final String kind; // 'wp' | 'activity'
  final String id;
  final String? parentWpId; // only set when kind == 'activity'
  const _ReorderPayload({
    required this.kind,
    required this.id,
    this.parentWpId,
  });
}

// ─── Outer wrapper (reads project ID) ────────────────────────────────────────
class ProgrammeGanttView extends StatelessWidget {
  final bool isExpanded;
  final bool isPresentation;
  final VoidCallback? onToggleExpanded;
  final VoidCallback? onTogglePresentation;

  const ProgrammeGanttView({
    super.key,
    this.isExpanded = false,
    this.isPresentation = false,
    this.onToggleExpanded,
    this.onTogglePresentation,
  });

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('No project selected',
          style: TextStyle(color: KColors.textMuted)));
    }
    return _ProgrammeGanttContent(
      key: ValueKey(projectId),
      projectId: projectId,
      isExpanded: isExpanded,
      isPresentation: isPresentation,
      onToggleExpanded: onToggleExpanded,
      onTogglePresentation: onTogglePresentation,
    );
  }
}

// ─── Main content widget ──────────────────────────────────────────────────────
class _ProgrammeGanttContent extends StatefulWidget {
  final String projectId;
  final bool isExpanded;
  final bool isPresentation;
  final VoidCallback? onToggleExpanded;
  final VoidCallback? onTogglePresentation;

  const _ProgrammeGanttContent({
    super.key,
    required this.projectId,
    this.isExpanded = false,
    this.isPresentation = false,
    this.onToggleExpanded,
    this.onTogglePresentation,
  });

  @override
  State<_ProgrammeGanttContent> createState() => _ProgrammeGanttContentState();
}

class _ProgrammeGanttContentState extends State<_ProgrammeGanttContent> {
  // ── Scroll controllers ───────────────────────────────────────────────────
  final _horizHeader = ScrollController();
  final _horizBody   = ScrollController();
  final _vertNames   = ScrollController();
  final _vertBody    = ScrollController();
  bool _hSync = false;
  bool _vSync = false;

  // ── View toggle ──────────────────────────────────────────────────────────
  bool _showMilestones = false;

  // ── Zoom & column mode ───────────────────────────────────────────────────
  double _cellW       = _kCellW;
  bool   _quarterMode = false;
  double _bodyWidth   = 800;

  // ── Inline name edit ─────────────────────────────────────────────────────
  String? _editingNameId;
  final _inlineNameCtrl  = TextEditingController();
  final _inlineNameFocus = FocusNode();

  // ── Drag to move ──────────────────────────────────────────────────────────
  String? _draggingActId;
  int    _dragOrigStart  = 0;
  int    _dragOrigEnd    = 0;
  double _dragAccumPx    = 0;
  int    _dragMonthDelta = 0;

  // ── Dependency arrows ────────────────────────────────────────────────────
  List<TimelineDependency> _deps = [];
  // When non-null, the painter spotlights the upstream + downstream
  // chains for this activity and dims everything else.
  String? _hoveredActivityId;
  Map<String, TimelineActivity> _actMap = {};
  bool _showDependencies = true;

  // ── Baseline ──────────────────────────────────────────────────────────────
  bool _showBaseline = true;
  bool _settingBaseline = false;

  // ── Data ─────────────────────────────────────────────────────────────────
  List<TimelineWorkPackage> _wps = [];
  Map<String, List<TimelineActivity>> _acts = {};
  ProgrammeHeader? _header;
  List<String> _months = [];
  List<_GRow> _rows = [];
  bool _loading = true;
  Map<String, ({int count, String urgency})> _actionSummary = {};

  AppDatabase get _db => context.read<AppDatabase>();

  @override
  void initState() {
    super.initState();
    _setupSync();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _setupSync() {
    _horizBody.addListener(() {
      if (_hSync) return;
      _hSync = true;
      if (_horizHeader.hasClients) _horizHeader.jumpTo(_horizBody.offset);
      _hSync = false;
    });
    _horizHeader.addListener(() {
      if (_hSync) return;
      _hSync = true;
      if (_horizBody.hasClients) _horizBody.jumpTo(_horizHeader.offset);
      _hSync = false;
    });
    _vertNames.addListener(() {
      if (_vSync) return;
      _vSync = true;
      if (_vertBody.hasClients) _vertBody.jumpTo(_vertNames.offset);
      _vSync = false;
    });
    _vertBody.addListener(() {
      if (_vSync) return;
      _vSync = true;
      if (_vertNames.hasClients) _vertNames.jumpTo(_vertBody.offset);
      _vSync = false;
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    final dao = _db.programmeGanttDao;
    final pid = widget.projectId;

    final header        = await dao.getHeader(pid);
    final wps           = await dao.getWorkPackages(pid);
    final allActs       = await dao.getActivitiesForProject(pid);
    final deps          = await dao.getDependencies(pid);
    final actionSummary = await _db.actionsDao.getLinkedActionSummary(pid);

    final actsByWp = <String, List<TimelineActivity>>{};
    for (final a in allActs) {
      actsByWp.putIfAbsent(a.workPackageId, () => []).add(a);
    }
    final actMap = {for (final a in allActs) a.id: a};

    List<String> months = [];
    if (header?.monthLabels != null) {
      try {
        months = (jsonDecode(header!.monthLabels!) as List).cast<String>();
      } catch (_) {}
    }
    if (months.isEmpty) months = List.generate(12, (i) => 'M$i');

    final rows = <_GRow>[];
    for (final wp in wps) {
      rows.add(_WpRow(wp));
      for (final act in actsByWp[wp.id] ?? []) {
        rows.add(_ActRow(act, wp));
      }
    }

    if (mounted) {
      setState(() {
        _header  = header;
        _wps     = wps;
        _acts    = actsByWp;
        _actMap  = actMap;
        _deps    = deps;
        _months  = months;
        _rows          = rows;
        _loading       = false;
        _actionSummary = actionSummary;
      });
    }
  }

  @override
  void dispose() {
    _horizHeader.dispose();
    _horizBody.dispose();
    _vertNames.dispose();
    _vertBody.dispose();
    _inlineNameCtrl.dispose();
    _inlineNameFocus.dispose();
    super.dispose();
  }

  // ── Zoom helpers ─────────────────────────────────────────────────────────

  /// Columns for the current mode: each entry has a label + inclusive month range.
  List<({String label, int start, int end})> get _ganttCols {
    if (!_quarterMode) {
      return List.generate(_months.length, (i) =>
          (label: _months[i], start: i, end: i));
    }
    final qs = <({String label, int start, int end})>[];
    for (int i = 0; i < _months.length; i += 3) {
      final last = min(i + 2, _months.length - 1);
      final label = last > i
          ? '${_months[i]}–${_months[last]}'
          : _months[i];
      qs.add((label: label, start: i, end: last));
    }
    return qs;
  }

  void _zoomIn()  => setState(() => _cellW = (_cellW * 1.3).clamp(24.0, 200.0));
  void _zoomOut() => setState(() => _cellW = (_cellW / 1.3).clamp(24.0, 200.0));
  void _fitToScreen() {
    final cols = _ganttCols.length;
    if (cols == 0) return;
    final w = (_bodyWidth / cols).clamp(24.0, 200.0);
    setState(() => _cellW = w);
  }

  // ── Inline name edit ──────────────────────────────────────────────────────

  void _startInlineEdit(TimelineActivity act) {
    setState(() {
      _editingNameId = act.id;
      _inlineNameCtrl.text = act.name;
    });
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _inlineNameFocus.requestFocus());
  }

  Future<void> _commitInlineName(TimelineActivity act) async {
    final name = _inlineNameCtrl.text.trim();
    setState(() => _editingNameId = null);
    if (name.isEmpty || name == act.name) return;
    await _db.programmeGanttDao.patchActivity(
      act.id,
      TimelineActivitiesCompanion(
        name: Value(name),
        updatedAt: Value(DateTime.now()),
      ),
    );
    _load();
  }

  void _cancelInlineEdit() => setState(() => _editingNameId = null);

  // ── Drag to move ──────────────────────────────────────────────────────────

  void _onDragStart(TimelineActivity act) {
    setState(() {
      _draggingActId = act.id;
      _dragOrigStart = act.startMonth ?? 0;
      _dragOrigEnd   = act.endMonth ?? (act.startMonth ?? 0);
      _dragAccumPx   = 0;
      _dragMonthDelta = 0;
    });
  }

  void _onDragUpdate(double dx) {
    if (_draggingActId == null) return;
    _dragAccumPx += dx;
    final newDelta = (_dragAccumPx / _cellW).round();
    if (newDelta != _dragMonthDelta) setState(() => _dragMonthDelta = newDelta);
  }

  Future<void> _onDragEnd() async {
    if (_draggingActId == null) return;
    final id    = _draggingActId!;
    final delta = _dragMonthDelta;
    final maxM  = _months.length - 1;
    final dur   = _dragOrigEnd - _dragOrigStart;
    final newStart = (_dragOrigStart + delta).clamp(0, maxM);
    final newEnd   = (newStart + dur).clamp(0, maxM);
    if (delta == 0) {
      setState(() { _draggingActId = null; _dragMonthDelta = 0; });
      return;
    }
    // Keep _draggingActId set until the reload completes so the bar continues
    // to render at the previewed position. Clearing it earlier would let the
    // bar briefly render from the still-stale _actMap before fresh data lands.
    await _db.programmeGanttDao.patchActivity(
      id,
      TimelineActivitiesCompanion(
        startMonth: Value(newStart),
        endMonth:   Value(newEnd),
        updatedAt:  Value(DateTime.now()),
      ),
    );
    await _load();
    if (!mounted) return;
    setState(() { _draggingActId = null; _dragMonthDelta = 0; });
  }

  /// Returns the effective start/end months for a cell render, accounting
  /// for any in-progress drag preview.
  (int?, int?) _effectiveMonths(TimelineActivity act) {
    if (_draggingActId == act.id) {
      final maxM  = _months.length - 1;
      final dur   = _dragOrigEnd - _dragOrigStart;
      final s = (_dragOrigStart + _dragMonthDelta).clamp(0, maxM);
      final e = (s + dur).clamp(0, maxM);
      return (s, e);
    }
    return (act.startMonth, act.endMonth);
  }

  // ── Baseline ──────────────────────────────────────────────────────────────

  bool get _hasBaseline => _actMap.values.any((a) => a.isBaseline);

  Future<void> _setBaseline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColors.surface,
        title: const Text('Set Baseline',
            style: TextStyle(color: KColors.text, fontSize: 14)),
        content: const Text(
            'Snapshot the current plan as the baseline.\n'
            'Any future changes will show as variance (ghost bars).',
            style: TextStyle(color: KColors.textDim, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Set Baseline')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _settingBaseline = true);
    await _db.programmeGanttDao.setBaseline(widget.projectId);
    await _load();
    if (mounted) setState(() => _settingBaseline = false);
  }

  Future<void> _clearBaseline() async {
    await _db.programmeGanttDao.clearBaseline(widget.projectId);
    _load();
  }

  // ── Dialog launchers ─────────────────────────────────────────────────────

  Future<void> _openHeaderSettings() async {
    await showDialog(
      context: context,
      builder: (_) => _HeaderSettingsDialog(
        db: _db, projectId: widget.projectId, header: _header,
      ),
    );
    _load();
  }

  Future<void> _openAddWp() async {
    await showDialog(
      context: context,
      builder: (_) => _WpFormDialog(
        db: _db, projectId: widget.projectId, sortOrder: _wps.length,
      ),
    );
    _load();
  }

  /// Reorders work packages so [srcId] lands immediately above [targetId]
  /// in the project's WP list. No-op if src == target. Persists via the
  /// DAO and reloads; the next stream tick repopulates [_wps] / [_rows].
  Future<void> _movePackageAbove(String srcId, String targetId) async {
    if (srcId == targetId) return;
    final ids = _wps.map((w) => w.id).toList();
    ids.remove(srcId);
    final at = ids.indexOf(targetId);
    if (at == -1) return;
    ids.insert(at, srcId);
    await _db.programmeGanttDao
        .reorderWorkPackages(widget.projectId, ids);
    await _load();
  }

  /// Reorders activities within [wpId] so [srcId] lands immediately above
  /// [targetId]. Both ids MUST belong to the same WP — callers gate this
  /// via the DragTarget's onWillAccept. No-op when src == target.
  Future<void> _moveActivityAbove(
      String wpId, String srcId, String targetId) async {
    if (srcId == targetId) return;
    final siblings = (_acts[wpId] ?? const <TimelineActivity>[])
        .map((a) => a.id)
        .toList();
    siblings.remove(srcId);
    final at = siblings.indexOf(targetId);
    if (at == -1) return;
    siblings.insert(at, srcId);
    await _db.programmeGanttDao
        .reorderActivitiesWithinWp(wpId, siblings);
    await _load();
  }

  Future<void> _openEditWp(TimelineWorkPackage wp) async {
    await showDialog(
      context: context,
      builder: (_) => _WpFormDialog(
        db: _db, projectId: widget.projectId, wp: wp, sortOrder: wp.sortOrder,
      ),
    );
    _load();
  }

  Future<void> _openAddActivity(TimelineWorkPackage wp, {int? startMonth}) async {
    await showDialog(
      context: context,
      builder: (_) => _ActivityFormDialog(
        db: _db,
        projectId: widget.projectId,
        wp: wp,
        months: _months,
        sortOrder: _acts[wp.id]?.length ?? 0,
        initialStartMonth: startMonth,
        initialEndMonth: startMonth,
      ),
    );
    _load();
  }

  Future<void> _openEditActivity(TimelineActivity act, TimelineWorkPackage wp) async {
    await showDialog(
      context: context,
      builder: (_) => _ActivityFormDialog(
        db: _db,
        projectId: widget.projectId,
        wp: wp,
        activity: act,
        months: _months,
        sortOrder: act.sortOrder,
      ),
    );
    _load();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.equal, meta: true):
            const _ZoomInIntent(),
        const SingleActivator(LogicalKeyboardKey.equal, control: true):
            const _ZoomInIntent(),
        const SingleActivator(LogicalKeyboardKey.minus, meta: true):
            const _ZoomOutIntent(),
        const SingleActivator(LogicalKeyboardKey.minus, control: true):
            const _ZoomOutIntent(),
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true):
            const _FitIntent(),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            const _FitIntent(),
        const SingleActivator(LogicalKeyboardKey.keyE,
            meta: true, shift: true):   const _ExpandIntent(),
        const SingleActivator(LogicalKeyboardKey.keyE,
            control: true, shift: true): const _ExpandIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF,
            meta: true, shift: true):   const _PresentationIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF,
            control: true, shift: true): const _PresentationIntent(),
        const SingleActivator(LogicalKeyboardKey.f11): const _PresentationIntent(),
      },
      child: Actions(
        actions: {
          _ZoomInIntent:  CallbackAction<_ZoomInIntent>(onInvoke: (_) => _zoomIn()),
          _ZoomOutIntent: CallbackAction<_ZoomOutIntent>(onInvoke: (_) => _zoomOut()),
          _FitIntent:     CallbackAction<_FitIntent>(onInvoke: (_) => _fitToScreen()),
          _ExpandIntent:  CallbackAction<_ExpandIntent>(
              onInvoke: (_) => widget.onToggleExpanded?.call()),
          _PresentationIntent: CallbackAction<_PresentationIntent>(
              onInvoke: (_) => widget.onTogglePresentation?.call()),
        },
        child: Focus(
          autofocus: true,
          child: Column(children: [
            _buildTopBar(),
            Expanded(child: _wps.isEmpty
                ? _buildEmptyState()
                : _showMilestones
                    ? MilestoneTrackerView(
                        wps: _wps,
                        actsByWp: _acts,
                        months: _months,
                        header: _header,
                        onTap: _openEditActivity,
                      )
                    : _buildGantt()),
          ]),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Row(children: [
        // Title — flexible so it shrinks rather than overflows
        Flexible(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('PROGRAMME PLAN',
                style: TextStyle(
                    color: KColors.textMuted, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.1)),
            if (_header?.title != null) ...[
              const SizedBox(width: 8),
              const Text('·', style: TextStyle(color: KColors.border2)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(_header!.title!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: KColors.text, fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 12),
        const Flexible(
          child: Text(
            'The delivery schedule. Work packages, activities, milestones over the programme lifetime.',
            style: TextStyle(color: KColors.textMuted, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        // View toggle
        _ViewToggle(
          showMilestones: _showMilestones,
          onChanged: (v) => setState(() => _showMilestones = v),
        ),
        const SizedBox(width: 12),
        if (!_showMilestones) ...[
          Tooltip(
            message: _showDependencies
                ? 'Hide dependency arrows'
                : 'Show dependency arrows',
            child: GestureDetector(
              onTap: () =>
                  setState(() => _showDependencies = !_showDependencies),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: _showDependencies
                      ? KColors.amber.withValues(alpha: 0.15)
                      : KColors.surface2,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: _showDependencies
                          ? KColors.amber
                          : KColors.border),
                ),
                child: Icon(Icons.share_outlined,
                    size: 13,
                    color: _showDependencies
                        ? KColors.amber
                        : KColors.textMuted),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Baseline controls
          if (_hasBaseline) ...[
            Tooltip(
              message: _showBaseline
                  ? 'Hide baseline ghost bars'
                  : 'Show baseline ghost bars',
              child: GestureDetector(
                onTap: () =>
                    setState(() => _showBaseline = !_showBaseline),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: _showBaseline
                        ? KColors.phosphor.withValues(alpha: 0.15)
                        : KColors.surface2,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: _showBaseline
                            ? KColors.phosphor
                            : KColors.border),
                  ),
                  child: Icon(Icons.compare_arrows_outlined,
                      size: 13,
                      color: _showBaseline
                          ? KColors.phosphor
                          : KColors.textMuted),
                ),
              ),
            ),
            Tooltip(
              message: 'Clear baseline',
              child: GestureDetector(
                onTap: _clearBaseline,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: KColors.surface2,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: KColors.border),
                  ),
                  child: const Icon(Icons.bookmark_remove_outlined,
                      size: 13, color: KColors.textMuted),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Tooltip(
            message: 'Set current plan as baseline',
            child: GestureDetector(
              onTap: _settingBaseline ? null : _setBaseline,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: KColors.surface2,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: KColors.border),
                ),
                alignment: Alignment.center,
                child: _settingBaseline
                    ? const SizedBox(
                        width: 10, height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5))
                    : const Text('Baseline',
                        style: TextStyle(
                            color: KColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _ZoomControls(
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onFit: _fitToScreen,
            quarterMode: _quarterMode,
            onToggleQuarter: (v) => setState(() {
              _quarterMode = v;
              _fitToScreen();
            }),
          ),
          const SizedBox(width: 12),
        ],
        TextButton.icon(
          onPressed: _openHeaderSettings,
          icon: const Icon(Icons.tune_outlined, size: 14),
          label: const Text('Configure', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _openAddWp,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Work Package', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        // Expand / presentation toggles
        _LayoutModeButtons(
          isExpanded: widget.isExpanded,
          isPresentation: widget.isPresentation,
          onToggleExpanded: widget.onToggleExpanded,
          onTogglePresentation: widget.onTogglePresentation,
        ),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.table_chart_outlined, size: 48, color: KColors.textMuted),
        const SizedBox(height: 16),
        const Text('No work packages yet',
            style: TextStyle(color: KColors.text, fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        const Text(
            'Add a work package to start building the programme Gantt.',
            style: TextStyle(color: KColors.textDim, fontSize: 12)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _openAddWp,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Add Work Package'),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _openHeaderSettings,
          icon: const Icon(Icons.tune_outlined, size: 14),
          label: const Text('Configure months / header',
              style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _buildGantt() {
    final cols      = _ganttCols;
    final totalCellW = cols.length * _cellW;

    return LayoutBuilder(builder: (ctx, constraints) {
      // Capture available width for fit-to-screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final w = constraints.maxWidth - _kNameW;
        if (w != _bodyWidth) _bodyWidth = w;
      });

      return Column(children: [
        // ── Sticky month/quarter header row ──────────────────────────────
        SizedBox(
          height: _kHeaderH,
          child: Row(children: [
            // Corner cell
            Container(
              width: _kNameW, height: _kHeaderH,
              decoration: const BoxDecoration(
                color: KColors.surface2,
                border: Border(
                  right: BorderSide(color: KColors.border),
                  bottom: BorderSide(color: KColors.border),
                ),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: const Text('WORK PACKAGE / ACTIVITY',
                  style: TextStyle(
                      color: KColors.textMuted, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 0.1)),
            ),
            // Column header cells
            Expanded(child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _horizHeader,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: List.generate(cols.length,
                    (i) => _buildColumnHeader(cols[i])),
              ),
            )),
          ]),
        ),

        // ── Body: frozen name column + scrollable cell grid ───────────────
        Expanded(child: Row(children: [
          // Frozen name column
          SizedBox(
            width: _kNameW,
            child: ListView.builder(
              controller: _vertNames,
              itemCount: _rows.length,
              itemBuilder: (ctx2, i) => _buildNameCell(_rows[i]),
            ),
          ),
          // Scrollable cell area + dependency overlay
          Expanded(
            child: Stack(children: [
              Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final dx = event.scrollDelta.dx;
                    if (dx.abs() > event.scrollDelta.dy.abs() &&
                        _horizBody.hasClients) {
                      try {
                        _horizBody.jumpTo(
                          (_horizBody.offset + dx)
                              .clamp(0.0, _horizBody.position.maxScrollExtent),
                        );
                      } catch (_) {}
                    }
                  }
                },
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _horizBody,
                  child: SizedBox(
                    width: totalCellW,
                    child: ListView.builder(
                      controller: _vertBody,
                      itemCount: _rows.length,
                      itemBuilder: (ctx2, i) => _buildCellRow(_rows[i], cols),
                    ),
                  ),
                ),
              ),
              // Dependency arrows overlay
              if (_showDependencies && _deps.isNotEmpty)
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_horizBody, _vertBody]),
                    builder: (_, __) => CustomPaint(
                      painter: _DependencyPainter(
                        rows:        _rows,
                        deps:        _deps,
                        actMap:      _actMap,
                        scrollX:     _horizBody.hasClients
                            ? _horizBody.offset : 0,
                        scrollY:     _vertBody.hasClients
                            ? _vertBody.offset : 0,
                        cellW:       _cellW,
                        quarterMode: _quarterMode,
                        hoveredActivityId: _hoveredActivityId,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
            ]),
          ),
        ])),
      ]);
    });
  }

  // ── Row: name column ──────────────────────────────────────────────────────

  Widget _buildNameCell(_GRow row) {
    if (row is _WpRow) {
      final c = _wpColor(row.wp.colourTheme);
      final isCascaded = row.wp.sourceProjectId != null;
      final payload = _ReorderPayload(kind: 'wp', id: row.wp.id);
      // Cascaded WPs are read-only on the programme side — the
      // canonical row lives on the source PM's machine. Disable edit
      // tap, the activity-add button, and reorder drops; show a
      // small PROJ tag instead so the user knows where it came from.
      return _ReorderDropTarget(
        accepts: (p) => !isCascaded && p.kind == 'wp' && p.id != row.wp.id,
        onAccept: (p) => _movePackageAbove(p.id, row.wp.id),
        child: GestureDetector(
          onTap: isCascaded ? null : () => _openEditWp(row.wp),
          child: Container(
            height: _kWpRowH,
            decoration: BoxDecoration(
              color: c.withValues(alpha: isCascaded ? 0.06 : 0.12),
              border: Border(
                left: BorderSide(color: c, width: 3),
                bottom: const BorderSide(color: KColors.border),
              ),
            ),
            padding: const EdgeInsets.only(left: 4, right: 6),
            child: Row(children: [
              if (isCascaded)
                // Reserve the same width as the drag handle would
                // occupy so cascaded + native rows stay aligned.
                const SizedBox(width: 16)
              else
                _DragHandle(
                  payload: payload,
                  feedbackLabel: row.wp.shortCode != null
                      ? '${row.wp.shortCode} — ${row.wp.name}'
                      : row.wp.name,
                  colour: c,
                ),
              Expanded(
                child: Text(
                  row.wp.shortCode != null
                      ? '${row.wp.shortCode} — ${row.wp.name}'
                      : row.wp.name,
                  style: TextStyle(
                      color: c, fontSize: 11, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCascaded) ...[
                _CascadedFromTag(sourceProjectId: row.wp.sourceProjectId!),
                const SizedBox(width: 4),
              ],
              _RagDot(row.wp.ragStatus),
              const SizedBox(width: 4),
              if (!isCascaded) ...[
                GestureDetector(
                  onTap: () => _openAddActivity(row.wp),
                  child: Icon(Icons.add_circle_outline,
                      size: 14, color: c.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: 2),
              ],
            ]),
          ),
        ),
      );
    }

    row as _ActRow;
    final act = row.act;
    final c = _wpColor(row.wp.colourTheme);
    final typeIcon = switch (act.activityType) {
      'milestone'          => '◆',
      'hard_deadline'      => '⚠',
      'gate'               => '◈',
      'ongoing'            => '↔',
      'dependency_marker'  => '→',
      _                    => null,
    };

    final isEditing = _editingNameId == act.id;
    final payload = _ReorderPayload(
      kind: 'activity',
      id: act.id,
      parentWpId: row.wp.id,
    );

    return _ReorderDropTarget(
      // Activities reorder only within their parent WP — cross-WP drops
      // would silently change the row's parent, which is not what the
      // user is asking for here.
      accepts: (p) =>
          p.kind == 'activity' &&
          p.parentWpId == row.wp.id &&
          p.id != act.id,
      onAccept: (p) =>
          _moveActivityAbove(row.wp.id, p.id, act.id),
      child: MouseRegion(
        onEnter: (_) {
          if (_hoveredActivityId != act.id) {
            setState(() => _hoveredActivityId = act.id);
          }
        },
        onExit: (_) {
          if (_hoveredActivityId == act.id) {
            setState(() => _hoveredActivityId = null);
          }
        },
        child: Container(
      height: _kRowH,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border(
          bottom: BorderSide(color: KColors.border.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(children: [
        // Drag handle in the indent gutter — keeps the visual indent
        // intact (handle replaces what was a SizedBox of similar width)
        // while making the row reorderable.
        _DragHandle(
          payload: payload,
          feedbackLabel: act.name,
          colour: c,
          // Activity rows are denser so a slightly smaller hit area is
          // fine; the gutter is only 14 px wide.
          width: 14,
        ),
        Container(width: 2, height: 14, color: c.withValues(alpha: 0.4)),
        const SizedBox(width: 6),
        if (typeIcon != null) ...[
          Text(typeIcon,
              style: TextStyle(color: c.withValues(alpha: 0.8), fontSize: 10)),
          const SizedBox(width: 4),
        ],
        // Name — inline edit or text
        Expanded(
          child: isEditing
              ? KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (e) {
                    if (e is KeyDownEvent &&
                        e.logicalKey == LogicalKeyboardKey.escape) {
                      _cancelInlineEdit();
                    }
                  },
                  child: TextField(
                    controller: _inlineNameCtrl,
                    focusNode: _inlineNameFocus,
                    style: const TextStyle(color: KColors.text, fontSize: 11),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _commitInlineName(act),
                    onEditingComplete: () => _commitInlineName(act),
                  ),
                )
              : GestureDetector(
                  onTap: () => _startInlineEdit(act),
                  onDoubleTap: () => _openEditActivity(act, row.wp),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.text,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(act.name,
                            style: const TextStyle(
                                color: KColors.text, fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                        if (act.owner != null && act.owner!.isNotEmpty)
                          Text(
                            act.contributors != null
                                ? '${act.owner!} +${(jsonDecode(act.contributors!) as List).length}'
                                : act.owner!,
                            style: const TextStyle(
                                color: KColors.textDim, fontSize: 9),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        // Edit icon (always visible for clarity)
        GestureDetector(
          onTap: () => _openEditActivity(act, row.wp),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.edit_outlined,
                size: 10, color: KColors.textMuted.withValues(alpha: 0.6)),
          ),
        ),
        if (act.isCritical)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.priority_high, size: 10, color: KColors.red),
          ),
        // Actions badge
        if (_actionSummary.containsKey(act.id))
          _ActionsBadge(
            summary: _actionSummary[act.id]!,
            onTap: () => _showActionsPopover(context, act),
          ),
      ]),
    ),
    ),
    );
  }

  void _showActionsPopover(BuildContext context, TimelineActivity act) {
    showDialog(
      context: context,
      builder: (_) => _ActionsPopoverDialog(
        activity: act,
        projectId: widget.projectId,
        db: _db,
        onActionSaved: _load,
      ),
    );
  }

  // ── Row: cell area ────────────────────────────────────────────────────────

  Widget _buildColumnHeader(({String label, int start, int end}) col) {
    return Container(
      width: _cellW, height: _kHeaderH,
      decoration: const BoxDecoration(
        color: KColors.surface2,
        border: Border(
          right: BorderSide(color: KColors.border),
          bottom: BorderSide(color: KColors.border),
        ),
      ),
      alignment: Alignment.center,
      child: Text(col.label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: KColors.textMuted, fontSize: 10,
              fontWeight: FontWeight.w600, letterSpacing: 0.1)),
    );
  }

  Widget _buildCellRow(_GRow row,
      List<({String label, int start, int end})> cols) {
    if (row is _WpRow) {
      final c = _wpColor(row.wp.colourTheme);
      return SizedBox(
        height: _kWpRowH,
        child: Row(
          children: List.generate(cols.length, (ci) {
            final col = cols[ci];
            return GestureDetector(
              onTap: () => _openAddActivity(row.wp, startMonth: col.start),
              child: Container(
                width: _cellW, height: _kWpRowH,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.05),
                  border: Border(
                    right: BorderSide(
                        color: KColors.border.withValues(alpha: 0.3)),
                    bottom: const BorderSide(color: KColors.border),
                  ),
                ),
              ),
            );
          }),
        ),
      );
    }

    row as _ActRow;
    return SizedBox(
      height: _kRowH,
      child: Row(
        children: List.generate(
            cols.length, (ci) => _buildCell(row, cols[ci], cols, ci)),
      ),
    );
  }

  Widget _buildCell(_ActRow row,
      ({String label, int start, int end}) col,
      [List<({String label, int start, int end})>? cols, int ci = 0]) {
    final act = row.act;
    final c   = _wpColor(row.wp.colourTheme);

    final (start, end) = _effectiveMonths(act);
    final isDragging = _draggingActId == act.id;

    // Single-point types only render at startMonth
    final isSingle = act.activityType == 'milestone' ||
        act.activityType == 'hard_deadline' ||
        act.activityType == 'gate';

    // Activity is "active" in this column if months overlap
    final isActive = isSingle
        ? (start != null && start >= col.start && start <= col.end)
        : (start != null && end != null &&
            start <= col.end && end >= col.start);

    final isFirst = isActive && start >= col.start;

    // Calculate how many cells the bar spans from this (first) cell onward,
    // so we can size the label to fill the full bar width.
    double barLabelWidth() {
      if (cols == null || end == null) return _cellW;
      int span = 0;
      for (int i = ci; i < cols.length; i++) {
        if (cols[i].start <= end && cols[i].end >= col.start) {
          span++;
        } else if (cols[i].start > end) {
          break;
        }
      }
      return (span.clamp(1, cols.length)) * _cellW;
    }

    Color? bg;
    Widget child = const SizedBox.shrink();

    if (isActive) {
      switch (act.activityType) {
        case 'milestone':
          child = Center(
            child: Text('◆',
                style: TextStyle(
                    color: c, fontSize: 15, fontWeight: FontWeight.w700)),
          );

        case 'hard_deadline':
          bg = const Color(0x33EF4444);
          child = Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('⚠',
                  style: TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
              if (act.cellLabel != null)
                Text(act.cellLabel!,
                    style: const TextStyle(
                        color: Color(0xFFEF4444), fontSize: 7),
                    overflow: TextOverflow.ellipsis),
            ]),
          );

        case 'gate':
          bg = KColors.amberDim.withValues(alpha: 0.8);
          child = Center(
            child: Text('◈',
                style: TextStyle(color: KColors.amber, fontSize: 13)),
          );

        case 'ongoing':
          bg = c.withValues(alpha: 0.14);
          if (isFirst) {
            child = OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: barLabelWidth(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(act.cellLabel ?? act.name,
                    style: TextStyle(
                        color: c, fontSize: 8, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
            );
          }

        case 'dependency_marker':
          bg = const Color(0xFF8B5CF6).withValues(alpha: 0.22);
          if (isFirst && act.cellLabel != null) {
            child = OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: barLabelWidth(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(act.cellLabel!,
                    style: const TextStyle(
                        color: Color(0xFF8B5CF6), fontSize: 8),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
            );
          }

        default: // 'activity'
          bg = c.withValues(alpha: 0.28);
          if (isFirst) {
            child = OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: barLabelWidth(),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(act.cellLabel ?? act.name,
                    style: TextStyle(
                        color: c, fontSize: 8, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ),
            );
          }
      }
    }

    final borderLeft = isFirst && (act.activityType == 'activity' ||
            act.activityType == 'dependency_marker' ||
            act.activityType == 'ongoing')
        ? BorderSide(color: c, width: 2)
        : const BorderSide(color: Colors.transparent);

    // Bar types support drag-to-move. Keep the cell draggable while a drag
    // on this activity is in progress so the gesture recogniser isn't
    // disposed when the preview shifts the bar off the originating cell.
    final isDraggable = (isActive || isDragging) &&
        (act.activityType == 'activity' ||
         act.activityType == 'ongoing' ||
         act.activityType == 'dependency_marker');

    // ── Ghost bar (baseline variance) ──────────────────────────────────────
    // Show when activity has moved from its baseline position.
    Widget? ghostBar;
    if (_showBaseline && act.isBaseline &&
        act.baselineStart != null && act.baselineEnd != null) {
      final bs = act.baselineStart!;
      final be = act.baselineEnd!;
      final movedFrom = bs != (act.startMonth ?? bs) ||
                        be != (act.endMonth ?? be);
      if (movedFrom) {
        final isBarType = act.activityType == 'activity' ||
            act.activityType == 'ongoing' ||
            act.activityType == 'dependency_marker';
        final ghostActive = isBarType
            ? (bs <= col.end && be >= col.start)
            : (bs >= col.start && bs <= col.end);
        if (ghostActive) {
          ghostBar = Positioned(
            bottom: 2,
            left: 0,
            right: 0,
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                    color: c.withValues(alpha: 0.5), width: 0.5),
              ),
            ),
          );
        }
      }
    }

    final cellContent = ghostBar != null
        ? Stack(children: [
            Positioned.fill(child: Container(
              decoration: BoxDecoration(color: bg),
              child: child,
            )),
            ghostBar,
          ])
        : child;

    final cell = Container(
      width: _cellW, height: _kRowH,
      decoration: BoxDecoration(
        color: ghostBar != null ? null :
            (isDragging && isActive
                ? (bg ?? KColors.surface).withValues(alpha: 0.5)
                : bg),
        border: Border(
          left: borderLeft,
          right: BorderSide(color: KColors.border.withValues(alpha: 0.3)),
          bottom: BorderSide(color: KColors.border.withValues(alpha: 0.3)),
        ),
      ),
      child: cellContent,
    );

    if (isDraggable) {
      return MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          onTap: () => _openEditActivity(act, row.wp),
          onHorizontalDragStart: (_) => _onDragStart(act),
          onHorizontalDragUpdate: (d) => _onDragUpdate(d.delta.dx),
          onHorizontalDragEnd: (_) => _onDragEnd(),
          child: cell,
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openEditActivity(act, row.wp),
      child: cell,
    );
  }
}

// ─── RAG dot ──────────────────────────────────────────────────────────────────
/// Small ≡ drag handle in the name-column gutter. Initiates a
/// [Draggable<_ReorderPayload>] which the matching [_ReorderDropTarget]s
/// pick up. Uses the regular [Draggable] (not LongPress) since this is
/// a desktop app — click-and-drag is the expected gesture.
class _DragHandle extends StatelessWidget {
  final _ReorderPayload payload;
  final String feedbackLabel;
  final Color colour;
  final double width;

  const _DragHandle({
    required this.payload,
    required this.feedbackLabel,
    required this.colour,
    this.width = 16,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<_ReorderPayload>(
        data: payload,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: KColors.surface,
              border: Border.all(color: colour.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              feedbackLabel,
              style: TextStyle(
                color: colour,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        child: SizedBox(
          width: width,
          height: _kRowH,
          child: Icon(Icons.drag_indicator,
              size: 12, color: KColors.textMuted.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}

/// Drop target for reorder drags. Wraps a row's name cell, highlighting
/// the row when a compatible payload hovers and invoking [onAccept] on
/// drop. Pure layout/no-data — the parent decides what "compatible"
/// means via [accepts].
class _ReorderDropTarget extends StatelessWidget {
  final bool Function(_ReorderPayload) accepts;
  final void Function(_ReorderPayload) onAccept;
  final Widget child;

  const _ReorderDropTarget({
    required this.accepts,
    required this.onAccept,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_ReorderPayload>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (ctx, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Stack(
          children: [
            child,
            if (hovering)
              // Thin amber bar at the top of the row showing exactly
              // where the dropped item will land (it inserts above).
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(height: 2, color: KColors.amber),
              ),
          ],
        );
      },
    );
  }
}

/// Tiny "PROJ · <name>" tag attached to cascaded WP rows on the
/// programme side. Looks up the source project's name via the live
/// project list so it stays accurate if the PM renames the project.
class _CascadedFromTag extends StatelessWidget {
  final String sourceProjectId;
  const _CascadedFromTag({required this.sourceProjectId});

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<ProjectProvider>().projects;
    final source = projects.cast<Project?>().firstWhere(
          (p) => p?.id == sourceProjectId,
          orElse: () => null,
        );
    final label = source?.name ?? 'project';
    return Tooltip(
      message: 'Cascaded from project: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.border2, width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text('PROJ',
            style: const TextStyle(
                color: KColors.textMuted,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      ),
    );
  }
}

class _RagDot extends StatelessWidget {
  final String status;
  const _RagDot(this.status);

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'green' => KColors.phosphor,
      'amber' => KColors.amber,
      'red'   => KColors.red,
      _       => KColors.textMuted,
    };
    return Container(
      width: 6, height: 6,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// "Depends on" editor used inside the activity dialog. Shows each
/// existing predecessor (internal activity or external label) as a row
/// and offers two add affordances: an internal-activity picker and a
/// free-text external dialog.
class _DependsOnEditor extends StatelessWidget {
  static const _typeOptions = [
    ('finish_to_start', 'FS'),
    ('start_to_start', 'SS'),
    ('finish_to_finish', 'FF'),
  ];

  final List<({TimelineActivity act, TimelineWorkPackage wp})>
      allActivities;
  final List<DependencySpec> predecessors;
  final ValueChanged<List<DependencySpec>> onChanged;

  const _DependsOnEditor({
    required this.allActivities,
    required this.predecessors,
    required this.onChanged,
  });

  void _addPredecessor(BuildContext ctx) async {
    final takenInternal = {
      for (final p in predecessors)
        if (!p.isExternal) p.fromActivityId!,
    };
    final available = allActivities
        .where((p) => !takenInternal.contains(p.act.id))
        .toList();
    if (available.isEmpty) return;
    final pickedId = await showDialog<String>(
      context: ctx,
      builder: (_) => _DependsOnPicker(available: available),
    );
    if (pickedId == null) return;
    onChanged([
      ...predecessors,
      DependencySpec.internal(
        fromActivityId: pickedId,
        dependencyType: 'finish_to_start',
      ),
    ]);
  }

  void _addExternal(BuildContext ctx) async {
    final takenLabels = {
      for (final p in predecessors)
        if (p.isExternal) p.externalLabel!.toLowerCase(),
    };
    final label = await showDialog<String>(
      context: ctx,
      builder: (_) => const _AddExternalDependencyDialog(),
    );
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (takenLabels.contains(trimmed.toLowerCase())) return;
    onChanged([
      ...predecessors,
      DependencySpec.external(trimmed),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final actById = {for (final p in allActivities) p.act.id: p};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('DEPENDS ON',
                style: TextStyle(
                  color: KColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                )),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addPredecessor(context),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add predecessor',
                  style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                foregroundColor: KColors.amber,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => _addExternal(context),
              icon: const Icon(Icons.language, size: 14),
              label: const Text('Add external',
                  style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                foregroundColor: KColors.amber,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        if (predecessors.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'No predecessors. Use "Add predecessor" for activities in '
              'this plan, or "Add external" for vendor deliveries, '
              'approvals, etc. that live outside the plan.',
              style: TextStyle(
                  color: KColors.textDim, fontSize: 11, height: 1.4),
            ),
          )
        else
          ...List.generate(predecessors.length, (i) {
            final p = predecessors[i];
            final removeBtn = IconButton(
              icon: const Icon(Icons.close,
                  size: 14, color: KColors.textMuted),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () {
                final next = [...predecessors]..removeAt(i);
                onChanged(next);
              },
            );

            if (p.isExternal) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.language,
                        size: 14, color: KColors.textDim),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('EXT · ${p.externalLabel}',
                          style: const TextStyle(
                              color: KColors.text, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                    removeBtn,
                  ],
                ),
              );
            }

            final pair = actById[p.fromActivityId];
            final label = pair == null
                ? '(missing activity)'
                : pair.wp.shortCode != null
                    ? '${pair.wp.shortCode} · ${pair.act.name}'
                    : '${pair.wp.name} · ${pair.act.name}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: KColors.text, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  // Type dropdown — FS / SS / FF. External isn't here:
                  // those go through the dedicated "Add external" flow.
                  SizedBox(
                    width: 64,
                    child: DropdownButton<String>(
                      value: p.dependencyType,
                      isDense: true,
                      isExpanded: true,
                      dropdownColor: KColors.surface2,
                      style: const TextStyle(
                          color: KColors.text, fontSize: 11),
                      items: _typeOptions
                          .map((t) => DropdownMenuItem(
                                value: t.$1,
                                child: Text(t.$2,
                                    style: const TextStyle(fontSize: 11)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final next = [...predecessors];
                        next[i] = DependencySpec.internal(
                          fromActivityId: p.fromActivityId!,
                          dependencyType: v,
                        );
                        onChanged(next);
                      },
                    ),
                  ),
                  removeBtn,
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// Tiny modal for entering an external dependency label. Returns the
/// trimmed text on submit, or null on cancel / empty.
class _AddExternalDependencyDialog extends StatefulWidget {
  const _AddExternalDependencyDialog();

  @override
  State<_AddExternalDependencyDialog> createState() =>
      _AddExternalDependencyDialogState();
}

class _AddExternalDependencyDialogState
    extends State<_AddExternalDependencyDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('External dependency',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Something this activity depends on that lives outside '
              'the plan — e.g. a vendor delivery, legal sign-off, or '
              'another team\'s milestone.',
              style: TextStyle(
                  color: KColors.textDim, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: KColors.text, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. Vendor API release, Legal sign-off',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Add', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

/// Simple picker dialog for choosing one predecessor activity from the
/// project. Grouped by Work Package. Returns the activity id, or null
/// on cancel.
class _DependsOnPicker extends StatelessWidget {
  final List<({TimelineActivity act, TimelineWorkPackage wp})> available;

  const _DependsOnPicker({required this.available});

  @override
  Widget build(BuildContext context) {
    // Group by WP id, preserving the input order.
    final groups =
        <String, List<({TimelineActivity act, TimelineWorkPackage wp})>>{};
    final wpOrder = <String>[];
    for (final p in available) {
      groups.putIfAbsent(p.wp.id, () {
        wpOrder.add(p.wp.id);
        return [];
      }).add(p);
    }
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Pick a predecessor',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 360,
        height: 360,
        child: ListView(
          children: [
            for (final wpId in wpOrder) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  groups[wpId]!.first.wp.shortCode != null
                      ? '${groups[wpId]!.first.wp.shortCode} · ${groups[wpId]!.first.wp.name}'
                      : groups[wpId]!.first.wp.name,
                  style: const TextStyle(
                    color: KColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              for (final pair in groups[wpId]!)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(pair.act.name,
                      style: const TextStyle(
                          color: KColors.text, fontSize: 12)),
                  onTap: () => Navigator.of(context).pop(pair.act.id),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: KColors.textDim)),
        ),
      ],
    );
  }
}

// ─── Header Settings Dialog ───────────────────────────────────────────────────
class _HeaderSettingsDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final ProgrammeHeader? header;

  const _HeaderSettingsDialog({
    required this.db,
    required this.projectId,
    this.header,
  });

  @override
  State<_HeaderSettingsDialog> createState() => _HeaderSettingsDialogState();
}

class _HeaderSettingsDialogState extends State<_HeaderSettingsDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _subtitleCtrl;
  late TextEditingController _deadlineCtrl;
  late TextEditingController _monthCountCtrl;
  String? _month0Date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final h = widget.header;
    _titleCtrl    = TextEditingController(text: h?.title ?? '');
    _subtitleCtrl = TextEditingController(text: h?.subtitle ?? '');
    _deadlineCtrl = TextEditingController(text: h?.hardDeadline ?? '');
    _month0Date   = h?.month0Date;

    // Derive month count from existing labels
    int monthCount = 12;
    if (h?.monthLabels != null) {
      try {
        final decoded = jsonDecode(h!.monthLabels!) as List;
        monthCount = decoded.length;
      } catch (_) {}
    }
    _monthCountCtrl = TextEditingController(text: monthCount.toString());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _deadlineCtrl.dispose();
    _monthCountCtrl.dispose();
    super.dispose();
  }

  List<String> _generateLabels() {
    final count = int.tryParse(_monthCountCtrl.text.trim()) ?? 12;
    if (_month0Date == null) {
      return List.generate(count, (i) => 'M$i');
    }
    try {
      final base = DateTime.parse(_month0Date!);
      final fmt  = intl.DateFormat('MMM yy');
      return List.generate(
          count, (i) => fmt.format(DateTime(base.year, base.month + i, 1)));
    } catch (_) {
      return List.generate(count, (i) => 'M$i');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final labels  = _generateLabels();
    final now     = DateTime.now();
    final id      = widget.header?.id ?? const Uuid().v4();

    await widget.db.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion(
      id:           Value(id),
      projectId:    Value(widget.projectId),
      title:        Value(_titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim()),
      subtitle:     Value(_subtitleCtrl.text.trim().isEmpty ? null : _subtitleCtrl.text.trim()),
      hardDeadline: Value(_deadlineCtrl.text.trim().isEmpty ? null : _deadlineCtrl.text.trim()),
      month0Date:   Value(_month0Date),
      monthLabels:  Value(jsonEncode(labels)),
      updatedAt:    Value(now),
    ));

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _generateLabels();
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Programme Header & Months',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Programme title',
                    hintText: 'e.g. TAC Digital Toolkit – Integration'),
                style: const TextStyle(color: KColors.text, fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _subtitleCtrl,
                decoration: const InputDecoration(labelText: 'Subtitle (optional)'),
                style: const TextStyle(color: KColors.text, fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _deadlineCtrl,
                decoration: const InputDecoration(
                    labelText: 'Hard deadline statement (optional)',
                    hintText: 'e.g. All environments live by end Sept 2025'),
                style: const TextStyle(color: KColors.text, fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text('MONTH COLUMNS',
                  style: TextStyle(
                      color: KColors.textMuted, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 0.1)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DatePickerField(
                    label: 'Month 0 start date',
                    isoValue: _month0Date,
                    onChanged: (v) =>
                        setState(() => _month0Date = v),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _monthCountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Count', isDense: true),
                    style: const TextStyle(
                        color: KColors.text, fontSize: 12),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Preview: ${preview.take(6).join(', ')}${preview.length > 6 ? ', ...' : ''}',
                  style: const TextStyle(
                      color: KColors.textDim, fontSize: 11)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: KColors.textDim)),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ─── Work Package Form Dialog ─────────────────────────────────────────────────
class _WpFormDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final TimelineWorkPackage? wp;
  final int sortOrder;

  const _WpFormDialog({
    required this.db,
    required this.projectId,
    this.wp,
    required this.sortOrder,
  });

  @override
  State<_WpFormDialog> createState() => _WpFormDialogState();
}

class _WpFormDialogState extends State<_WpFormDialog> {
  final _formKey    = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _codeCtrl;
  late TextEditingController _descCtrl;
  String _theme  = 'wp1';
  String _rag    = 'not_started';
  bool _saving   = false;
  bool _deleting = false;

  bool get _isEdit => widget.wp != null;

  @override
  void initState() {
    super.initState();
    final wp   = widget.wp;
    _nameCtrl  = TextEditingController(text: wp?.name ?? '');
    _codeCtrl  = TextEditingController(text: wp?.shortCode ?? '');
    _descCtrl  = TextEditingController(text: wp?.description ?? '');
    _theme     = wp?.colourTheme ?? 'wp1';
    _rag       = wp?.ragStatus ?? 'not_started';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final id  = widget.wp?.id ?? const Uuid().v4();

    await widget.db.programmeGanttDao.upsertWorkPackage(
      TimelineWorkPackagesCompanion(
        id:          Value(id),
        projectId:   Value(widget.projectId),
        name:        Value(_nameCtrl.text.trim()),
        shortCode:   Value(_codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim()),
        description: Value(_descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
        colourTheme: Value(_theme),
        ragStatus:   Value(_rag),
        sortOrder:   Value(widget.sortOrder),
        updatedAt:   Value(now),
      ),
    );

    // Best-effort cascade to any active programme links. Service
    // handles "no links / offline / cascaded row" cases internally.
    if (mounted) {
      final saved = await widget.db.programmeGanttDao
          .getWorkPackages(widget.projectId);
      final wp = saved.firstWhere((w) => w.id == id, orElse: () => saved.first);
      // ignore: use_build_context_synchronously
      await _cascadeFor(context).pushWorkPackage(wp);
    }

    if (mounted) Navigator.of(context).pop();
  }

  /// Builds a [CascadeService] from the live providers. Returns a
  /// service with a null gateway when the user isn't signed in — the
  /// service treats that as "no-op", so the UI doesn't need to branch.
  CascadeService _cascadeFor(BuildContext context) {
    final sync = context.read<SyncProvider>();
    final token = sync.accessToken;
    return CascadeService(
      widget.db,
      gateway: token == null
          ? null
          : SyncCascadeGateway(
              client: SyncClient(baseUrl: sync.serverUrl),
              accessToken: token,
            ),
    );
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColors.surface,
        title: const Text('Delete Work Package',
            style: TextStyle(color: KColors.text, fontSize: 14)),
        content: Text(
            'Delete "${widget.wp!.name}" and all its activities? This cannot be undone.',
            style: const TextStyle(color: KColors.textDim, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _deleting = true);

    final deletedId = widget.wp!.id;
    await widget.db.programmeGanttDao.deleteActivitiesForWP(deletedId);
    await widget.db.programmeGanttDao.deleteWorkPackage(deletedId);

    // Tombstone the cascade so programme-side rows disappear too.
    if (mounted) {
      // ignore: use_build_context_synchronously
      await _cascadeFor(context).deleteWorkPackage(
        projectId: widget.projectId,
        workPackageId: deletedId,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Text(_isEdit ? 'Edit Work Package' : 'New Work Package',
          style: const TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: !_isEdit,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  style: const TextStyle(color: KColors.text, fontSize: 13),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _codeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Short code (optional)',
                      hintText: 'e.g. WP1'),
                  style: const TextStyle(color: KColors.text, fontSize: 13),
                ),
                const SizedBox(height: 12),
                // Colour theme
                const Text('COLOUR THEME',
                    style: TextStyle(
                        color: KColors.textMuted, fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 0.1)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _kThemes.map((t) {
                    final selected = _theme == t;
                    final c       = _wpColor(t);
                    return GestureDetector(
                      onTap: () => setState(() => _theme = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? c.withValues(alpha: 0.2)
                              : Colors.transparent,
                          border: Border.all(
                              color: selected ? c : KColors.border2,
                              width: selected ? 1.5 : 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 8, height: 8,
                            decoration:
                                BoxDecoration(color: c, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(_kThemeLabels[t]!,
                              style: TextStyle(
                                  color: selected ? c : KColors.textDim,
                                  fontSize: 11)),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // RAG status
                DropdownButtonFormField<String>(
                  value: _rag,
                  decoration:
                      const InputDecoration(labelText: 'RAG status'),
                  dropdownColor: KColors.surface2,
                  items: _kRagStatuses
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(_kRagLabels[s]!,
                                style: const TextStyle(fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _rag = v ?? 'not_started'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Description (optional)', isDense: true),
                  style: const TextStyle(
                      color: KColors.text, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  if (_isEdit)
                    TextButton(
                      onPressed: _deleting ? null : _delete,
                      style: TextButton.styleFrom(
                          foregroundColor: KColors.red),
                      child: const Text('Delete',
                          style: TextStyle(fontSize: 12)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: KColors.textDim, fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_isEdit ? 'Save' : 'Create',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Activity Form Dialog ─────────────────────────────────────────────────────
class _ActivityFormDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final TimelineWorkPackage wp;
  final TimelineActivity? activity;
  final List<String> months;
  final int sortOrder;
  final int? initialStartMonth;
  final int? initialEndMonth;

  const _ActivityFormDialog({
    required this.db,
    required this.projectId,
    required this.wp,
    this.activity,
    required this.months,
    required this.sortOrder,
    this.initialStartMonth,
    this.initialEndMonth,
  });

  @override
  State<_ActivityFormDialog> createState() => _ActivityFormDialogState();
}

class _ActivityFormDialogState extends State<_ActivityFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _labelCtrl;
  late TextEditingController _notesCtrl;
  String   _type       = 'activity';
  String   _status     = 'not_started';
  int?     _startMonth;
  int?     _endMonth;
  bool     _isCritical = false;
  bool     _saving     = false;
  String?  _ownerId;
  List<Person> _persons = [];
  List<_Contributor> _contributors = [];

  // Inbound dependency state — list of predecessors of this activity.
  // Mix of internal predecessors (point at another activity) and
  // external ones (free-text label, no upstream activity row).
  List<DependencySpec> _predecessors = [];
  // All other activities in the project — populated once on form open
  // so the picker has something to enumerate.
  List<({TimelineActivity act, TimelineWorkPackage wp})> _allActivities =
      [];

  bool get _isEdit => widget.activity != null;
  bool get _isSinglePoint =>
      _type == 'milestone' || _type == 'hard_deadline' || _type == 'gate';

  @override
  void initState() {
    super.initState();
    final a    = widget.activity;
    _nameCtrl  = TextEditingController(text: a?.name ?? '');
    _ownerCtrl = TextEditingController(text: a?.owner ?? '');
    _labelCtrl = TextEditingController(text: a?.cellLabel ?? '');
    _notesCtrl = TextEditingController(text: a?.notes ?? '');
    _type       = a?.activityType ?? 'activity';
    _status     = a?.status ?? 'not_started';
    _startMonth = a?.startMonth ?? widget.initialStartMonth;
    _endMonth   = a?.endMonth ?? widget.initialEndMonth;
    _isCritical = a?.isCritical ?? false;
    _ownerId    = a?.ownerId;
    if (a?.contributors != null) {
      final names = jsonDecode(a!.contributors!) as List;
      final ids   = a.contributorIds != null
          ? jsonDecode(a.contributorIds!) as List
          : const [];
      _contributors = List.generate(
        names.length,
        (i) => (name: names[i] as String,
                 id: i < ids.length ? ids[i] as String? : null),
      );
    }
    _ownerCtrl.addListener(_resolveOwnerId);
    _loadPersons();
    _loadDependencies();
  }

  Future<void> _loadDependencies() async {
    // Load all activities + WPs in the project for the picker, and the
    // existing predecessors for this activity (if editing).
    final acts = await widget.db.programmeGanttDao
        .getActivitiesForProject(widget.projectId);
    final wps = await widget.db.programmeGanttDao
        .getWorkPackages(widget.projectId);
    final wpById = {for (final w in wps) w.id: w};
    final pairs = <({TimelineActivity act, TimelineWorkPackage wp})>[];
    for (final a in acts) {
      final wp = wpById[a.workPackageId];
      if (wp == null) continue;
      if (widget.activity != null && a.id == widget.activity!.id) continue;
      pairs.add((act: a, wp: wp));
    }

    final inbound = widget.activity == null
        ? const <TimelineDependency>[]
        : await widget.db.programmeGanttDao
            .getInboundDependenciesFor(widget.activity!.id);

    if (!mounted) return;
    setState(() {
      _allActivities = pairs;
      _predecessors = [
        for (final d in inbound)
          if (d.externalLabel != null)
            DependencySpec.external(d.externalLabel!)
          else
            DependencySpec.internal(
              fromActivityId: d.fromActivityId,
              dependencyType: d.dependencyType,
            ),
      ];
    });
  }

  void _resolveOwnerId() {
    final name = _ownerCtrl.text.trim().toLowerCase();
    final match = _persons.cast<Person?>().firstWhere(
      (p) => p!.name.toLowerCase() == name,
      orElse: () => null,
    );
    final newId = match?.id;
    if (newId != _ownerId) setState(() => _ownerId = newId);
  }

  Future<void> _loadPersons() async {
    final persons = await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) {
      setState(() => _persons = persons);
      _resolveOwnerId();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ownerCtrl.removeListener(_resolveOwnerId);
    _ownerCtrl.dispose();
    _labelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final id  = widget.activity?.id ?? const Uuid().v4();

    final endVal = _isSinglePoint ? _startMonth : _endMonth;

    await widget.db.programmeGanttDao.upsertActivity(
      TimelineActivitiesCompanion(
        id:           Value(id),
        workPackageId: Value(widget.wp.id),
        projectId:    Value(widget.projectId),
        name:         Value(_nameCtrl.text.trim()),
        owner:        Value(_ownerCtrl.text.trim().isEmpty
            ? null : _ownerCtrl.text.trim()),
        ownerId:      Value(_ownerId),
        activityType: Value(_type),
        status:       Value(_status),
        startMonth:   Value(_startMonth),
        endMonth:     Value(endVal),
        isCritical:   Value(_isCritical),
        cellLabel:    Value(_labelCtrl.text.trim().isEmpty
            ? null : _labelCtrl.text.trim()),
        notes:        Value(_notesCtrl.text.trim().isEmpty
            ? null : _notesCtrl.text.trim()),
        contributors: Value(_contributors.isEmpty ? null
            : jsonEncode(_contributors.map((c) => c.name).toList())),
        contributorIds: Value(_contributors.isEmpty ? null
            : jsonEncode(_contributors.map((c) => c.id).toList())),
        sortOrder:    Value(widget.sortOrder),
        updatedAt:    Value(now),
      ),
    );

    // Sync the inbound-dependency rows for this activity. Done after
    // the upsert so a newly-created activity has its row in place
    // before the FK-style links land.
    await widget.db.programmeGanttDao.replaceInboundDependencies(
      projectId: widget.projectId,
      activityId: id,
      desired: _predecessors,
    );

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColors.surface,
        title: const Text('Delete Activity',
            style: TextStyle(color: KColors.text, fontSize: 14)),
        content: Text('Delete "${widget.activity!.name}"?',
            style: const TextStyle(color: KColors.textDim, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await widget.db.programmeGanttDao.deleteActivity(widget.activity!.id);
    if (mounted) Navigator.of(context).pop();
  }

  List<DropdownMenuItem<int?>> get _monthItems {
    final items = <DropdownMenuItem<int?>>[
      const DropdownMenuItem(value: null, child: Text('— none —')),
    ];
    final labels = widget.months.isNotEmpty
        ? widget.months
        : List.generate(12, (i) => 'M$i');
    for (int i = 0; i < labels.length; i++) {
      items.add(DropdownMenuItem(
        value: i,
        child: Text('${labels[i]} (M$i)'),
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final c = _wpColor(widget.wp.colourTheme);

    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Row(children: [
        Container(width: 3, height: 20, color: c,
            margin: const EdgeInsets.only(right: 10)),
        Expanded(
          child: Text(_isEdit ? 'Edit Activity' : 'Add Activity',
              style: const TextStyle(color: KColors.text, fontSize: 16)),
        ),
        Text(widget.wp.shortCode ?? widget.wp.name,
            style: TextStyle(color: c, fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
      content: SizedBox(
        width: 640,
        height: 760,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: !_isEdit,
                  decoration: const InputDecoration(
                    labelText: 'Activity name *',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  style: const TextStyle(color: KColors.text, fontSize: 14),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                // Activity type
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Activity type',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(color: KColors.text, fontSize: 14),
                  dropdownColor: KColors.surface2,
                  items: _kActivityTypes.map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(_kActivityTypeLabels[t]!,
                            style: const TextStyle(fontSize: 14)),
                      )).toList(),
                  onChanged: (v) =>
                      setState(() => _type = v ?? 'activity'),
                ),
                const SizedBox(height: 12),
                // Month range
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _startMonth,
                      decoration: InputDecoration(
                        labelText:
                            _isSinglePoint ? 'Month' : 'Start month',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(
                          color: KColors.text, fontSize: 14),
                      dropdownColor: KColors.surface2,
                      items: _monthItems,
                      onChanged: (v) => setState(() {
                        _startMonth = v;
                        if (!_isSinglePoint &&
                            _endMonth != null &&
                            v != null &&
                            _endMonth! < v) {
                          _endMonth = v;
                        }
                      }),
                    ),
                  ),
                  if (!_isSinglePoint) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _endMonth,
                        decoration: const InputDecoration(
                          labelText: 'End month',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(
                            color: KColors.text, fontSize: 14),
                        dropdownColor: KColors.surface2,
                        items: _monthItems,
                        onChanged: (v) => setState(() => _endMonth = v),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 14),
                // Owner — roomier styling pass-through so the field
                // doesn't feel compressed at this larger dialog size.
                PersonPickerField(
                  controller: _ownerCtrl,
                  label: 'Owner',
                  persons: _persons,
                  db: widget.db,
                  projectId: widget.projectId,
                  onPersonCreated: _loadPersons,
                  textStyle: const TextStyle(
                      color: KColors.text, fontSize: 14),
                  labelStyle: const TextStyle(
                      color: KColors.textDim, fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                ),
                const SizedBox(height: 14),
                _MultiPersonPickerField(
                  selected: _contributors,
                  persons: _persons,
                  db: widget.db,
                  projectId: widget.projectId,
                  onPersonsReloaded: _loadPersons,
                  onChanged: (updated) =>
                      setState(() => _contributors = updated),
                  larger: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style:
                      const TextStyle(color: KColors.text, fontSize: 14),
                  dropdownColor: KColors.surface2,
                  items: milestoneTrackerStatuses.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(milestoneTrackerStatusLabels[s]!,
                        style: const TextStyle(fontSize: 14)),
                  )).toList(),
                  onChanged: (v) => setState(() => _status = v ?? 'not_started'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cell label (optional)',
                    hintText: 'Text shown in Gantt cell',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(color: KColors.text, fontSize: 14),
                ),
                const SizedBox(height: 14),
                // Notes — generous multi-line, larger font, label
                // anchored to the top so a long note doesn't push the
                // label out of view.
                TextFormField(
                  controller: _notesCtrl,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    alignLabelWithHint: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  style: const TextStyle(
                      color: KColors.text, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _isCritical,
                  onChanged: (v) => setState(() => _isCritical = v ?? false),
                  title: const Text('On critical path',
                      style: TextStyle(color: KColors.text, fontSize: 12)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 10),
                _DependsOnEditor(
                  allActivities: _allActivities,
                  predecessors: _predecessors,
                  onChanged: (next) =>
                      setState(() => _predecessors = next),
                ),
                const SizedBox(height: 16),
                // Action buttons inline — avoids OverflowBar issues
                Row(children: [
                  if (_isEdit)
                    TextButton(
                      onPressed: _delete,
                      style: TextButton.styleFrom(
                          foregroundColor: KColors.red),
                      child: const Text('Delete',
                          style: TextStyle(fontSize: 12)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: KColors.textDim, fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_isEdit ? 'Save' : 'Add',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Actions badge ────────────────────────────────────────────────────────────

class _ActionsBadge extends StatelessWidget {
  final ({int count, String urgency}) summary;
  final VoidCallback onTap;

  const _ActionsBadge({required this.summary, required this.onTap});

  Color get _color => switch (summary.urgency) {
    'overdue' => KColors.red,
    'soon'    => KColors.amber,
    _         => KColors.phosphor,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: '${summary.count} linked action${summary.count == 1 ? '' : 's'}',
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 9, color: _color),
              const SizedBox(width: 2),
              Text('${summary.count}',
                  style: TextStyle(
                      color: _color,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Actions popover dialog ───────────────────────────────────────────────────

class _ActionsPopoverDialog extends StatefulWidget {
  final TimelineActivity activity;
  final String projectId;
  final AppDatabase db;
  final VoidCallback onActionSaved;

  const _ActionsPopoverDialog({
    required this.activity,
    required this.projectId,
    required this.db,
    required this.onActionSaved,
  });

  @override
  State<_ActionsPopoverDialog> createState() => _ActionsPopoverDialogState();
}

class _ActionsPopoverDialogState extends State<_ActionsPopoverDialog> {
  List<ProjectAction> _actions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final actions = await widget.db.actionsDao.getActionsForActivity(widget.activity.id);
    if (mounted) setState(() { _actions = actions; _loading = false; });
  }

  Color _statusColor(ProjectAction a) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (a.status == 'closed') return KColors.textMuted;
    if (a.dueDate != null && a.dueDate!.compareTo(today) < 0) return KColors.red;
    return KColors.phosphor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Row(children: [
        const Icon(Icons.bolt, size: 14, color: KColors.amber),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Actions – ${widget.activity.name}',
            style: const TextStyle(color: KColors.text, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_actions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No actions linked to this activity yet.',
                          style: TextStyle(color: KColors.textDim, fontSize: 12)),
                    )
                  else
                    ..._actions.map((a) => _ActionRow(
                          action: a,
                          statusColor: _statusColor(a),
                          onTap: () async {
                            await showDialog(
                              context: context,
                              builder: (_) => ActionFormDialog(
                                projectId: widget.projectId,
                                db: widget.db,
                                action: a,
                                startInViewMode: true,
                              ),
                            );
                            await _load();
                            widget.onActionSaved();
                          },
                        )),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 13),
          label: const Text('Add Action', style: TextStyle(fontSize: 12)),
          onPressed: () async {
            await showDialog(
              context: context,
              builder: (_) => ActionFormDialog(
                projectId: widget.projectId,
                db: widget.db,
                preLinkedActivityId: widget.activity.id,
              ),
            );
            await _load();
            widget.onActionSaved();
          },
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final ProjectAction action;
  final Color statusColor;
  final VoidCallback onTap;

  const _ActionRow({
    required this.action,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(Icons.circle, size: 7, color: statusColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(action.description,
                  style: const TextStyle(color: KColors.text, fontSize: 12),
                  overflow: TextOverflow.ellipsis),
            ),
            if (action.owner != null) ...[
              const SizedBox(width: 6),
              Text(action.owner!,
                  style: const TextStyle(
                      color: KColors.textDim, fontSize: 10)),
            ],
            if (action.dueDate != null) ...[
              const SizedBox(width: 6),
              Text(action.dueDate!.substring(5), // MM-DD
                  style: TextStyle(color: statusColor, fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Multi-person contributor picker ─────────────────────────────────────────

typedef _Contributor = ({String name, String? id});

class _MultiPersonPickerField extends StatefulWidget {
  final List<_Contributor> selected;
  final List<Person> persons;
  final AppDatabase db;
  final String projectId;
  final VoidCallback onPersonsReloaded;
  final ValueChanged<List<_Contributor>> onChanged;
  /// When true, renders with the same roomier proportions as the host
  /// activity dialog (larger header, bigger chips + input). Default
  /// keeps the compact rendering used by every other caller.
  final bool larger;

  const _MultiPersonPickerField({
    required this.selected,
    required this.persons,
    required this.db,
    required this.projectId,
    required this.onPersonsReloaded,
    required this.onChanged,
    this.larger = false,
  });

  @override
  State<_MultiPersonPickerField> createState() =>
      _MultiPersonPickerFieldState();
}

class _MultiPersonPickerFieldState extends State<_MultiPersonPickerField> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _lastOptions = [];
  String _myName = '';

  static const _kAddSentinel = '\x00__add__';
  static const _kMeSentinel  = '\x00__me__';

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<String> _optionsFor(String query, String myName) {
    final q = query.toLowerCase().trim();
    final opts = <String>[];
    final selectedNames =
        widget.selected.map((c) => c.name.toLowerCase()).toSet();

    if (myName.isNotEmpty &&
        !selectedNames.contains(myName.toLowerCase()) &&
        (q.isEmpty ||
            myName.toLowerCase().contains(q) ||
            'me'.contains(q))) {
      opts.add(_kMeSentinel);
    }

    opts.addAll(widget.persons
        .where((p) =>
            !selectedNames.contains(p.name.toLowerCase()) &&
            p.name.toLowerCase().contains(q))
        .map((p) => p.name)
        .take(6));

    if (q.isNotEmpty) opts.add(_kAddSentinel);
    return opts;
  }

  void _add(String name, String? id) {
    if (name.isEmpty) return;
    final already = widget.selected.any(
        (c) => c.name.toLowerCase() == name.toLowerCase());
    if (!already) {
      widget.onChanged([...widget.selected, (name: name, id: id)]);
    }
    _ctrl.clear();
    _focusNode.unfocus();
  }

  void _remove(int index) {
    final updated = [...widget.selected]..removeAt(index);
    widget.onChanged(updated);
  }

  Future<void> _handleAddNew(String query) async {
    final result = await showDialog<NewPersonResult>(
      context: context,
      builder: (_) => AddPersonDialog(
        name: query,
        db: widget.db,
        projectId: widget.projectId,
      ),
    );
    if (result != null && mounted) {
      final id = const Uuid().v4();
      final now = DateTime.now();
      await widget.db.peopleDao.upsertPerson(PersonsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        name: Value(result.name),
        role: Value(result.role),
        organisation: Value(result.organisation),
        personType: Value(result.personType),
        isStakeholder: Value(result.isStakeholder),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      widget.onPersonsReloaded();
      _add(result.name, id);
    }
  }

  String? _idForName(String name) {
    final lower = name.toLowerCase();
    return widget.persons
        .cast<Person?>()
        .firstWhere((p) => p!.name.toLowerCase() == lower, orElse: () => null)
        ?.id;
  }

  @override
  Widget build(BuildContext context) {
    _myName = context.read<SettingsProvider>().settings.myName;
    // Pre-pick the size knobs so the build tree stays readable.
    final headerSize = widget.larger ? 11.0 : 9.0;
    final chipFont = widget.larger ? 13.0 : 11.0;
    final chipPadH = widget.larger ? 8.0 : 6.0;
    final inputFont = widget.larger ? 14.0 : 12.0;
    final hintFont = widget.larger ? 13.0 : 11.0;
    final outerPadV = widget.larger ? 10.0 : 4.0;
    final outerPadH = widget.larger ? 10.0 : 6.0;
    final chipDeleteSize = widget.larger ? 14.0 : 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONTRIBUTORS',
            style: TextStyle(
                color: KColors.textMuted,
                fontSize: headerSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: KColors.border2),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: EdgeInsets.symmetric(
              horizontal: outerPadH, vertical: outerPadV),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.selected.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.selected.asMap().entries.map((e) {
                    return Chip(
                      label: Text(e.value.name,
                          style: TextStyle(
                              color: KColors.text, fontSize: chipFont)),
                      backgroundColor: KColors.surface2,
                      side: const BorderSide(color: KColors.border2),
                      deleteIcon: Icon(Icons.close,
                          size: chipDeleteSize, color: KColors.textDim),
                      onDeleted: () => _remove(e.key),
                      padding: EdgeInsets.zero,
                      labelPadding:
                          EdgeInsets.symmetric(horizontal: chipPadH),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
              ],
              RawAutocomplete<String>(
                textEditingController: _ctrl,
                focusNode: _focusNode,
                optionsBuilder: (v) {
                  _lastOptions = _optionsFor(v.text, _myName);
                  return _lastOptions;
                },
                displayStringForOption: (opt) {
                  if (opt == _kMeSentinel) return _myName;
                  if (opt == _kAddSentinel) return _ctrl.text;
                  return opt;
                },
                fieldViewBuilder: (ctx, ctrl, fn, onSubmitted) =>
                    TextField(
                  controller: ctrl,
                  focusNode: fn,
                  style: TextStyle(
                      color: KColors.text, fontSize: inputFont),
                  decoration: InputDecoration(
                    hintText: 'Add contributor…',
                    hintStyle: TextStyle(
                        color: KColors.textMuted, fontSize: hintFont),
                    border: InputBorder.none,
                    isDense: !widget.larger,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: widget.larger ? 8 : 4),
                  ),
                  onSubmitted: (_) {
                    final first = _lastOptions.firstWhere(
                      (o) => o != _kAddSentinel,
                      orElse: () => '',
                    );
                    if (first == _kMeSentinel) {
                      _add(_myName, _idForName(_myName));
                    } else if (first.isNotEmpty) {
                      _add(first, _idForName(first));
                    } else {
                      final typed = _ctrl.text.trim();
                      if (typed.isNotEmpty) _add(typed, _idForName(typed));
                    }
                  },
                ),
                optionsViewBuilder: (ctx, onSelected, options) =>
                    Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: KColors.surface2,
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: const BorderSide(color: KColors.border2),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxHeight: 200, maxWidth: 260),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: options.map((opt) {
                          if (opt == _kMeSentinel) {
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: const Icon(
                                  Icons.person_pin_outlined,
                                  size: 14,
                                  color: KColors.phosphor),
                              title: Text('Me — $_myName',
                                  style: const TextStyle(
                                      color: KColors.phosphor,
                                      fontSize: 12)),
                              onTap: () {
                                onSelected(opt);
                                _add(_myName, _idForName(_myName));
                              },
                            );
                          }
                          if (opt == _kAddSentinel) {
                            final q = _ctrl.text.trim();
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: const Icon(
                                  Icons.person_add_outlined,
                                  size: 14,
                                  color: KColors.phosphor),
                              title: Text('Add "$q" as new person',
                                  style: const TextStyle(
                                      color: KColors.phosphor,
                                      fontSize: 12)),
                              onTap: () {
                                onSelected(opt);
                                _handleAddNew(q);
                              },
                            );
                          }
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(Icons.person_outline,
                                size: 14, color: KColors.textDim),
                            title: Text(opt,
                                style: const TextStyle(
                                    color: KColors.text,
                                    fontSize: 12)),
                            onTap: () {
                              onSelected(opt);
                              _add(opt, _idForName(opt));
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                onSelected: (opt) {
                  if (opt == _kMeSentinel) {
                    _add(_myName, _idForName(_myName));
                  } else if (opt != _kAddSentinel) {
                    _add(opt, _idForName(opt));
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Dependency arrow painter ─────────────────────────────────────────────────
class _DependencyPainter extends CustomPainter {
  final List<_GRow>             rows;
  final List<TimelineDependency> deps;
  final Map<String, TimelineActivity> actMap;
  final double scrollX;
  final double scrollY;
  final double cellW;
  final bool   quarterMode;
  /// When non-null, arrows on the upstream/downstream chains of this
  /// activity are spotlit; unrelated arrows fade. Computed inside the
  /// painter so the parent doesn't have to redo the BFS on every move.
  final String? hoveredActivityId;

  // Palette — kept as Paint sources rather than literals so each
  // colour's role in the legend is obvious from one place.
  static const _normalColor   = Color(0xCC8B5CF6); // muted purple
  static const _brokenColor   = Color(0xFFEF4444); // red
  static const _upstreamColor = Color(0xFF22D3EE); // cyan
  static const _downstreamColor = Color(0xFF34D399); // green
  static const _dimmedColor   = Color(0x33A0AEC0); // very faded grey

  _DependencyPainter({
    required this.rows,
    required this.deps,
    required this.actMap,
    required this.scrollX,
    required this.scrollY,
    required this.cellW,
    required this.quarterMode,
    this.hoveredActivityId,
  });

  // Build activity → row-index lookup once per paint.
  Map<String, int> get _rowIdx {
    final m = <String, int>{};
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r is _ActRow) m[r.act.id] = i;
    }
    return m;
  }

  double _rowTopY(int i) {
    double y = 0;
    for (int j = 0; j < i; j++) y += rows[j].height;
    return y;
  }

  double _rowMidY(int i) => _rowTopY(i) + rows[i].height / 2 - scrollY;

  // Pixel X of the left edge of the column that contains [month].
  double _monthLeft(int month) {
    final col = quarterMode ? month ~/ 3 : month;
    return col * cellW - scrollX;
  }

  // Pixel X of the right edge of the column that contains [month].
  double _monthRight(int month) => _monthLeft(month) + cellW;

  @override
  void paint(Canvas canvas, Size size) {
    // Pre-compute chain membership once per paint so each dep can be
    // classified in O(1). When nothing's hovered, both sets are empty.
    final upstream = hoveredActivityId == null
        ? const <String>{}
        : DependencyChains.upstreamOf(hoveredActivityId!, deps);
    final downstream = hoveredActivityId == null
        ? const <String>{}
        : DependencyChains.downstreamOf(hoveredActivityId!, deps);

    final ridx = _rowIdx;
    // Per-target counter so multiple externals on the same activity
    // stack horizontally to the left instead of stomping on each other.
    final externalSlot = <String, int>{};

    for (final dep in deps) {
      // External deps don't have a source row — render a small chip
      // anchored just left of the target activity's start cell. We
      // still want the spotlight/dim colouring to apply, so reuse
      // `_colourFor` with empty chain sets when not hovered.
      if (dep.externalLabel != null) {
        final toAct = actMap[dep.toActivityId];
        if (toAct == null) continue;
        final toRow = ridx[toAct.id];
        if (toRow == null) continue;
        final toMonth = toAct.startMonth;
        if (toMonth == null) continue;
        final slot = externalSlot[toAct.id] ?? 0;
        externalSlot[toAct.id] = slot + 1;
        final colour = _colourFor(dep, false, upstream, downstream);
        _paintExternalChip(
          canvas: canvas,
          size: size,
          label: dep.externalLabel!,
          toX: _monthLeft(toMonth),
          y: _rowMidY(toRow),
          slot: slot,
          colour: colour,
        );
        continue;
      }

      final fromAct = actMap[dep.fromActivityId];
      final toAct   = actMap[dep.toActivityId];
      if (fromAct == null || toAct == null) continue;

      final fromRow = ridx[fromAct.id];
      final toRow   = ridx[toAct.id];
      if (fromRow == null || toRow == null) continue;

      // For non-FS types the anchor point shifts (SS leaves from the
      // start of the predecessor, FF arrives at the end of the
      // successor). Kept simple: SS/FS anchor the from-side at the
      // appropriate edge, FF anchors the to-side at the end.
      final fromMonth = switch (dep.dependencyType) {
        'start_to_start' => fromAct.startMonth,
        _ => fromAct.endMonth ?? fromAct.startMonth,
      };
      final toMonth = switch (dep.dependencyType) {
        'finish_to_finish' => toAct.endMonth ?? toAct.startMonth,
        _ => toAct.startMonth,
      };
      if (fromMonth == null || toMonth == null) continue;

      final fromX = dep.dependencyType == 'start_to_start'
          ? _monthLeft(fromMonth)
          : _monthRight(fromMonth);
      final fromY = _rowMidY(fromRow);
      final toX = dep.dependencyType == 'finish_to_finish'
          ? _monthRight(toMonth)
          : _monthLeft(toMonth);
      final toY   = _rowMidY(toRow);

      // Skip if entirely off-screen
      if (fromX < -cellW * 2 && toX < -cellW * 2) continue;
      if (fromX > size.width + cellW * 2 && toX > size.width + cellW * 2) continue;

      final isBroken = DependencyChains.isBroken(dep, actMap);
      final colour = _colourFor(dep, isBroken, upstream, downstream);

      final linePaint = Paint()
        ..color = colour
        ..strokeWidth = isBroken ? 2.0 : 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final fillPaint = Paint()
        ..color = colour
        ..style = PaintingStyle.fill;

      // Bezier with horizontal tangents
      final dx     = (toX - fromX).abs().clamp(cellW * 0.5, cellW * 2.0);
      final path   = Path()
        ..moveTo(fromX, fromY)
        ..cubicTo(
          fromX + dx, fromY,
          toX - dx,   toY,
          toX,        toY,
        );
      canvas.drawPath(path, linePaint);

      // Arrowhead at toX, toY
      _arrow(canvas, fillPaint, Offset(toX, toY), Offset(toX - dx, toY));

      // Type label at the curve midpoint. Drawn only when the arrow
      // isn't dimmed — keeping non-hovered labels out keeps the canvas
      // readable when there are dozens of deps in view.
      if (colour != _dimmedColor) {
        _drawTypeLabel(
          canvas,
          colour,
          dep.dependencyType,
          (fromX + toX) / 2,
          (fromY + toY) / 2,
        );
      }
    }
  }

  /// Resolves the line colour for one dep given the current spotlight
  /// state. Order of precedence matters: broken-on-an-unrelated-arrow
  /// still gets dimmed because the user is focused on the hover chain.
  Color _colourFor(
    TimelineDependency dep,
    bool isBroken,
    Set<String> upstream,
    Set<String> downstream,
  ) {
    final hovered = hoveredActivityId;
    if (hovered == null) {
      return isBroken ? _brokenColor : _normalColor;
    }
    // Hovered chain: dep is "upstream" if its successor is the hovered
    // activity OR sits anywhere up the upstream chain of it.
    final inUpstream =
        dep.toActivityId == hovered || upstream.contains(dep.toActivityId);
    final inDownstream = dep.fromActivityId == hovered ||
        downstream.contains(dep.fromActivityId);
    if (inUpstream && isBroken) return _brokenColor;
    if (inDownstream && isBroken) return _brokenColor;
    if (inUpstream) return _upstreamColor;
    if (inDownstream) return _downstreamColor;
    return _dimmedColor;
  }

  void _drawTypeLabel(
    Canvas canvas,
    Color colour,
    String depType,
    double cx,
    double cy,
  ) {
    final text = DependencyChains.shortLabel(depType);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: colour,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Background chip so the label stays readable when it lands on
    // a busy bar.
    final pad = 2.0;
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: tp.width + pad * 2,
      height: tp.height + pad,
    );
    final bg = Paint()..color = const Color(0xE8141821); // surface-ish
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      bg,
    );
    tp.paint(
      canvas,
      Offset(cx - tp.width / 2, cy - tp.height / 2),
    );
  }

  /// Paints a small "EXT: label" chip just to the left of an
  /// activity's start cell, with an arrow pointing into the bar. The
  /// chip stays clipped to the visible cells area so it's never lost
  /// off the left edge even on a left-most activity.
  void _paintExternalChip({
    required Canvas canvas,
    required Size size,
    required String label,
    required double toX,
    required double y,
    required int slot,
    required Color colour,
  }) {
    final text = 'EXT: $label';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: colour,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);

    const padH = 6.0;
    const padV = 3.0;
    final chipW = tp.width + padH * 2;
    final chipH = tp.height + padV * 2;
    // Each external on the same activity sits one chip-width further
    // to the left, leaving an 8px gap between chip and target bar.
    final gap = 8.0;
    final stack = slot * (chipW + 4);
    var right = toX - gap - stack;
    var left = right - chipW;
    // Clamp left edge so we never paint behind the frozen name column.
    if (left < 0) {
      left = 0;
      right = left + chipW;
    }
    // Off-screen to the right — nothing to draw.
    if (left > size.width) return;

    final rect = Rect.fromLTWH(left, y - chipH / 2, chipW, chipH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = const Color(0xE8141821),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, Offset(left + padH, y - tp.height / 2));

    // Arrow from chip right edge into the activity bar — only render
    // when the gap is wide enough to be legible.
    if (toX - right > 4) {
      final linePaint = Paint()
        ..color = colour
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(right, y), Offset(toX, y), linePaint);
      _arrow(
        canvas,
        Paint()
          ..color = colour
          ..style = PaintingStyle.fill,
        Offset(toX, y),
        Offset(right, y),
      );
    }
  }

  void _arrow(Canvas canvas, Paint paint, Offset tip, Offset from) {
    final len = (tip - from).distance;
    if (len < 1) return;
    final nx = (tip.dx - from.dx) / len;
    final ny = (tip.dy - from.dy) / len;
    const al = 7.0, aw = 3.5;
    final p1 = Offset(tip.dx - al * nx + aw * ny, tip.dy - al * ny - aw * nx);
    final p2 = Offset(tip.dx - al * nx - aw * ny, tip.dy - al * ny + aw * nx);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DependencyPainter old) =>
      old.scrollX != scrollX ||
      old.scrollY != scrollY ||
      old.cellW   != cellW   ||
      old.deps    != deps    ||
      old.rows    != rows    ||
      old.hoveredActivityId != hoveredActivityId;
}

// ─── Layout mode buttons (expand / presentation) ─────────────────────────────
class _LayoutModeButtons extends StatelessWidget {
  final bool isExpanded;
  final bool isPresentation;
  final VoidCallback? onToggleExpanded;
  final VoidCallback? onTogglePresentation;

  const _LayoutModeButtons({
    required this.isExpanded,
    required this.isPresentation,
    this.onToggleExpanded,
    this.onTogglePresentation,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(
        message: isExpanded
            ? 'Restore normal layout (⌘⇧E)'
            : 'Expand — hide Claude panel (⌘⇧E)',
        child: GestureDetector(
          onTap: onToggleExpanded,
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: isExpanded
                  ? KColors.amber.withValues(alpha: 0.15)
                  : KColors.surface2,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: isExpanded ? KColors.amber : KColors.border),
            ),
            child: Icon(
              isExpanded
                  ? Icons.close_fullscreen_outlined
                  : Icons.open_in_full_outlined,
              size: 13,
              color: isExpanded ? KColors.amber : KColors.textMuted,
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Tooltip(
        message: isPresentation
            ? 'Exit presentation mode (F11)'
            : 'Presentation mode — full screen (F11)',
        child: GestureDetector(
          onTap: onTogglePresentation,
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: isPresentation
                  ? KColors.amber.withValues(alpha: 0.15)
                  : KColors.surface2,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: isPresentation ? KColors.amber : KColors.border),
            ),
            child: Icon(
              isPresentation
                  ? Icons.fullscreen_exit_outlined
                  : Icons.fullscreen_outlined,
              size: 14,
              color: isPresentation ? KColors.amber : KColors.textMuted,
            ),
          ),
        ),
      ),
    ]);
  }
}

// ─── Zoom controls widget ─────────────────────────────────────────────────────
class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final bool quarterMode;
  final ValueChanged<bool> onToggleQuarter;

  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.quarterMode,
    required this.onToggleQuarter,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Month / Quarter toggle
      Container(
        height: 28,
        decoration: BoxDecoration(
          color: KColors.surface2,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: KColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _modeTab('M', !quarterMode, () => onToggleQuarter(false)),
          Container(width: 1, height: 16, color: KColors.border),
          _modeTab('Q', quarterMode, () => onToggleQuarter(true)),
        ]),
      ),
      const SizedBox(width: 6),
      // Zoom buttons
      Container(
        height: 28,
        decoration: BoxDecoration(
          color: KColors.surface2,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: KColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _iconBtn(Icons.remove, onZoomOut, tooltip: 'Zoom out (⌘-)'),
          Container(width: 1, height: 16, color: KColors.border),
          _iconBtn(Icons.add, onZoomIn, tooltip: 'Zoom in (⌘+)'),
          Container(width: 1, height: 16, color: KColors.border),
          _iconBtn(Icons.fit_screen_outlined, onFit, tooltip: 'Fit to screen (⌘0)'),
        ]),
      ),
    ]);
  }

  Widget _modeTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: 28,
        decoration: BoxDecoration(
          color: active ? KColors.amber.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: active ? KColors.amber : KColors.textMuted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          color: Colors.transparent,
          child: Icon(icon, size: 14, color: KColors.textMuted),
        ),
      ),
    );
  }
}

// ─── View toggle widget ───────────────────────────────────────────────────────
class _ViewToggle extends StatelessWidget {
  final bool showMilestones;
  final ValueChanged<bool> onChanged;

  const _ViewToggle({required this.showMilestones, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: KColors.surface2,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: KColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _tab(Icons.table_chart_outlined, 'Plan', !showMilestones, () => onChanged(false)),
        Container(width: 1, height: 16, color: KColors.border),
        _tab(Icons.flag_outlined, 'Milestones', showMilestones, () => onChanged(true)),
      ]),
    );
  }

  Widget _tab(IconData icon, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? KColors.amber.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(children: [
          Icon(icon, size: 12,
              color: active ? KColors.amber : KColors.textMuted),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: active ? KColors.amber : KColors.textMuted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}
