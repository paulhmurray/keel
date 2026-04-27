import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../providers/project_provider.dart';
import '../../../shared/theme/keel_colors.dart';
import '../../../shared/widgets/date_picker_field.dart';
import '../../../shared/widgets/person_picker_field.dart';
import 'milestone_tracker_view.dart';

// ─── Layout constants ─────────────────────────────────────────────────────────
const _kNameW = 240.0;
const _kCellW = 56.0;
const _kHeaderH = 40.0;
const _kWpRowH = 32.0;
const _kRowH = 32.0;

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
  'mpower': 'Cyan (M-POWER)',
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

    final header  = await dao.getHeader(pid);
    final wps     = await dao.getWorkPackages(pid);
    final allActs = await dao.getActivitiesForProject(pid);
    final deps    = await dao.getDependencies(pid);

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
        _rows    = rows;
        _loading = false;
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
    setState(() { _draggingActId = null; _dragMonthDelta = 0; });
    if (delta == 0) return;
    await _db.programmeGanttDao.patchActivity(
      id,
      TimelineActivitiesCompanion(
        startMonth: Value(newStart),
        endMonth:   Value(newEnd),
        updatedAt:  Value(DateTime.now()),
      ),
    );
    _load();
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
      return GestureDetector(
        onTap: () => _openEditWp(row.wp),
        child: Container(
          height: _kWpRowH,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            border: Border(
              left: BorderSide(color: c, width: 3),
              bottom: const BorderSide(color: KColors.border),
            ),
          ),
          padding: const EdgeInsets.only(left: 8, right: 6),
          child: Row(children: [
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
            _RagDot(row.wp.ragStatus),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _openAddActivity(row.wp),
              child: Icon(Icons.add_circle_outline,
                  size: 14, color: c.withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 2),
          ]),
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

    return Container(
      height: _kRowH,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border(
          bottom: BorderSide(color: KColors.border.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(children: [
        // Indent + type indicator
        const SizedBox(width: 14),
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
                          Text(act.owner!,
                              style: const TextStyle(
                                  color: KColors.textDim, fontSize: 9),
                              overflow: TextOverflow.ellipsis),
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
      ]),
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
            cols.length, (ci) => _buildCell(row, cols[ci])),
      ),
    );
  }

  Widget _buildCell(_ActRow row,
      ({String label, int start, int end}) col) {
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
            child = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(act.cellLabel ?? act.name,
                  style: TextStyle(
                      color: c, fontSize: 8, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            );
          }

        case 'dependency_marker':
          bg = const Color(0xFF8B5CF6).withValues(alpha: 0.22);
          if (isFirst && act.cellLabel != null) {
            child = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(act.cellLabel!,
                  style: const TextStyle(
                      color: Color(0xFF8B5CF6), fontSize: 8),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            );
          }

        default: // 'activity'
          bg = c.withValues(alpha: 0.28);
          if (isFirst) {
            child = Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(act.cellLabel ?? act.name,
                  style: TextStyle(
                      color: c, fontSize: 8, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            );
          }
      }
    }

    final borderLeft = isFirst && (act.activityType == 'activity' ||
            act.activityType == 'dependency_marker' ||
            act.activityType == 'ongoing')
        ? BorderSide(color: c, width: 2)
        : const BorderSide(color: Colors.transparent);

    // Bar types support drag-to-move
    final isDraggable = isActive &&
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
      final fmt  = DateFormat('MMM yy');
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

    if (mounted) Navigator.of(context).pop();
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

    await widget.db.programmeGanttDao.deleteActivitiesForWP(widget.wp!.id);
    await widget.db.programmeGanttDao.deleteWorkPackage(widget.wp!.id);

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
    _ownerCtrl.addListener(_resolveOwnerId);
    _loadPersons();
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
        sortOrder:    Value(widget.sortOrder),
        updatedAt:    Value(now),
      ),
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
        Container(width: 3, height: 16, color: c,
            margin: const EdgeInsets.only(right: 8)),
        Expanded(
          child: Text(_isEdit ? 'Edit Activity' : 'Add Activity',
              style: const TextStyle(color: KColors.text, fontSize: 14)),
        ),
        Text(widget.wp.shortCode ?? widget.wp.name,
            style: TextStyle(color: c, fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]),
      content: SizedBox(
        width: 460,
        height: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: !_isEdit,
                  decoration:
                      const InputDecoration(labelText: 'Activity name *'),
                  style: const TextStyle(color: KColors.text, fontSize: 13),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                // Activity type
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration:
                      const InputDecoration(labelText: 'Activity type'),
                  dropdownColor: KColors.surface2,
                  items: _kActivityTypes.map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(_kActivityTypeLabels[t]!,
                            style: const TextStyle(fontSize: 13)),
                      )).toList(),
                  onChanged: (v) =>
                      setState(() => _type = v ?? 'activity'),
                ),
                const SizedBox(height: 10),
                // Month range
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _startMonth,
                      decoration: InputDecoration(
                          labelText: _isSinglePoint ? 'Month' : 'Start month'),
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _endMonth,
                        decoration: const InputDecoration(labelText: 'End month'),
                        dropdownColor: KColors.surface2,
                        items: _monthItems,
                        onChanged: (v) => setState(() => _endMonth = v),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 10),
                PersonPickerField(
                  controller: _ownerCtrl,
                  label: 'Owner',
                  persons: _persons,
                  db: widget.db,
                  projectId: widget.projectId,
                  onPersonCreated: _loadPersons,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(
                      labelText: 'Status', isDense: true),
                  dropdownColor: KColors.surface2,
                  items: milestoneTrackerStatuses.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(milestoneTrackerStatusLabels[s]!,
                        style: const TextStyle(fontSize: 13)),
                  )).toList(),
                  onChanged: (v) => setState(() => _status = v ?? 'not_started'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Cell label (optional)',
                      hintText: 'Text shown in Gantt cell',
                      isDense: true),
                  style: const TextStyle(color: KColors.text, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Notes (optional)', isDense: true),
                  style: const TextStyle(color: KColors.text, fontSize: 12),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: _isCritical,
                  onChanged: (v) => setState(() => _isCritical = v ?? false),
                  title: const Text('On critical path',
                      style: TextStyle(color: KColors.text, fontSize: 12)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
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

// ─── Dependency arrow painter ─────────────────────────────────────────────────
class _DependencyPainter extends CustomPainter {
  final List<_GRow>             rows;
  final List<TimelineDependency> deps;
  final Map<String, TimelineActivity> actMap;
  final double scrollX;
  final double scrollY;
  final double cellW;
  final bool   quarterMode;

  _DependencyPainter({
    required this.rows,
    required this.deps,
    required this.actMap,
    required this.scrollX,
    required this.scrollY,
    required this.cellW,
    required this.quarterMode,
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
    final linePaint = Paint()
      ..color = const Color(0x888B5CF6)   // muted purple
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = const Color(0x888B5CF6)
      ..style = PaintingStyle.fill;

    final ridx = _rowIdx;

    for (final dep in deps) {
      final fromAct = actMap[dep.fromActivityId];
      final toAct   = actMap[dep.toActivityId];
      if (fromAct == null || toAct == null) continue;

      final fromRow = ridx[fromAct.id];
      final toRow   = ridx[toAct.id];
      if (fromRow == null || toRow == null) continue;

      final fromEnd   = fromAct.endMonth ?? fromAct.startMonth;
      final toStart   = toAct.startMonth;
      if (fromEnd == null || toStart == null) continue;

      final fromX = _monthRight(fromEnd);
      final fromY = _rowMidY(fromRow);
      final toX   = _monthLeft(toStart);
      final toY   = _rowMidY(toRow);

      // Skip if entirely off-screen
      if (fromX < -cellW * 2 && toX < -cellW * 2) continue;
      if (fromX > size.width + cellW * 2 && toX > size.width + cellW * 2) continue;

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
      old.rows    != rows;
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
