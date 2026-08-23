import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/analytics/keel_events.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/sync/links_gateway.dart';
import '../../core/sync/sync_client.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/keybindings_table.dart';
import '../../shared/widgets/sync_password_dialog.dart';
import '../programme/programme_view.dart';
import '../canvas/canvas_view.dart';
import '../timeline/gantt/programme_gantt_view.dart';
import '../raid/raid_view.dart';
import '../decisions/decisions_view.dart';
import '../people/people_view.dart';
import '../actions/actions_view.dart';
import '../inbox/inbox_view.dart';
import '../context/context_view.dart';
import '../reports/reports_view.dart';
import '../settings/settings_view.dart';
import '../actions/action_form.dart';
import '../decisions/decision_form.dart';
import '../journal/journal_history_view.dart';
import '../journal/journal_overlay.dart';
import '../playbook/playbook_view.dart';
import '../raid/risk_form.dart';
import '../raid/issue_form.dart';
import '../raid/assumption_form.dart';
import '../raid/dependency_form.dart';
import '../status/status_view.dart';
import '../charter/charter_view.dart';
import '../finance/finance_view.dart';
import '../helm/helm_view.dart';
import '../charter/charter_migration_notice.dart';
import '../../core/charter/charter_migration.dart';
import '../../shared/widgets/update_banner.dart';
import 'left_panel.dart';
import 'nav_rail.dart';
import 'claude_panel.dart';

class ShellLayout extends StatefulWidget {
  const ShellLayout({super.key});

  @override
  State<ShellLayout> createState() => _ShellLayoutState();
}

// ---------------------------------------------------------------------------
// Leader key binding tree
// ---------------------------------------------------------------------------

sealed class _KeyNode {
  String get description;
}

/// Branch node: shows a sub-menu. [onEnter] fires immediately when selected.
class _MenuNode extends _KeyNode {
  @override final String description;
  final Map<String, _KeyNode> children;
  final VoidCallback? onEnter;
  _MenuNode(this.description, this.children, {this.onEnter});
}

/// Leaf node: executes [action] and closes the leader HUD.
class _ActionNode extends _KeyNode {
  @override final String description;
  final VoidCallback action;
  _ActionNode(this.description, this.action);
}

// ---------------------------------------------------------------------------
// Shell layout state
// ---------------------------------------------------------------------------

enum _GanttLayoutMode { normal, expanded, presentation }

class _ShellLayoutState extends State<ShellLayout> {
  int _selectedIndex = 0;
  bool _leftPanelVisible = true;
  bool _rightPanelVisible = true;
  _GanttLayoutMode _ganttMode = _GanttLayoutMode.normal;
  StreamSubscription<void>? _dbChangeSub;

  // Deep-navigation state (set by leader bindings, consumed by _buildView)
  int? _contextInitialTab;
  bool _contextTriggerNew = false;
  int? _raidInitialTab;
  bool _raidTriggerNew = false;
  bool _decisionsTriggerNew = false;
  bool _financeTriggerNew = false;
  int _financeNavSeq = 0;

  // Sequence counters — increment on every navigation action so ValueKey
  // forces a widget remount even when _selectedIndex doesn't change.
  int _raidNavSeq = 0;
  int _contextNavSeq = 0;
  int _decisionsNavSeq = 0;

  // Playbook stage to expand on next PlaybookView build — set when the
  // user clicks a stage row in the sidebar. Consumed (cleared) by the
  // view dispatcher after one render.
  String? _playbookFocusStageId;

  // Canvas remount + initial-mode triggers. Bumped by the SPC t leader
  // chord so the view remounts (clean state) and, when SPC t n is used,
  // opens the quick-capture overlay on first build.
  int _canvasNavSeq = 0;
  bool _canvasInitialQuickCapture = false;

  // Leader key state — null = inactive, non-null = active at this menu node
  _MenuNode? _currentLeaderMenu;
  String _leaderPrefix = 'SPC';
  late final _MenuNode _rootMenu;

  // Three-view tour: track whether we've already triggered the dialog this
  // session so didChangeDependencies doesn't fire it twice.
  bool _tourTriggered = false;
  bool _charterMigrationTriggered = false;

  static const double _leftPanelWidth = 220.0;
  // Claude panel: user-resizable between min/max, with a one-click
  // normal ↔ wide toggle. Width persists across sessions.
  static const double _rightPanelDefaultWidth = 280.0;
  static const double _rightPanelWideWidth = 560.0;
  static const double _rightPanelMinWidth = 240.0;
  static const double _rightPanelMaxWidth = 720.0;
  static const String _rightPanelWidthPrefKey = 'keel_claude_panel_width';
  double _rightPanelWidth = _rightPanelDefaultWidth;
  bool _resizingRightPanel = false;

  // Docked journal pane (Ctrl+Alt+J) — take meeting notes while
  // navigating the app. The Ctrl+J modal overlay remains for quick capture.
  static const double _journalDockDefaultWidth = 420.0;
  static const double _journalDockMinWidth = 320.0;
  static const double _journalDockMaxWidth = 720.0;
  static const String _journalDockWidthPrefKey = 'keel_journal_dock_width';
  bool _journalDockVisible = false;
  double _journalDockWidth = _journalDockDefaultWidth;
  bool _resizingJournalDock = false;
  // Entry loaded in the dock (null = fresh note). The GlobalKey lets the
  // shell ask the pane about unsaved text before swapping its content.
  JournalEntry? _journalDockEntry;
  final _journalDockKey = GlobalKey<JournalOverlayState>();

  Future<void> _loadRightPanelWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_rightPanelWidthPrefKey);
    final savedDock = prefs.getDouble(_journalDockWidthPrefKey);
    if (!mounted) return;
    setState(() {
      if (saved != null) {
        _rightPanelWidth =
            saved.clamp(_rightPanelMinWidth, _rightPanelMaxWidth);
      }
      if (savedDock != null) {
        _journalDockWidth =
            savedDock.clamp(_journalDockMinWidth, _journalDockMaxWidth);
      }
    });
  }

  Future<void> _saveJournalDockWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_journalDockWidthPrefKey, _journalDockWidth);
  }

  /// Confirms discarding unsaved text in the docked note. True = proceed.
  Future<bool> _confirmDiscardDockNote() async {
    if (!(_journalDockKey.currentState?.hasUnsavedChanges ?? false)) {
      return true;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved note in split view'),
        content: const Text(
            'The docked journal has unsaved changes. Discard them?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep editing')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Discard')),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _toggleJournalDock() async {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) return;
    // Hiding unmounts the pane — don't silently eat unsaved text.
    if (_journalDockVisible && !await _confirmDiscardDockNote()) return;
    setState(() => _journalDockVisible = !_journalDockVisible);
  }

  /// Opens (or reveals) the docked journal. With [entry], loads that
  /// entry; with null, a fresh note.
  Future<void> _openJournalDock({JournalEntry? entry}) async {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) return;
    final changingContent =
        _journalDockVisible && _journalDockEntry?.id != entry?.id;
    if (changingContent && !await _confirmDiscardDockNote()) return;
    setState(() {
      _journalDockEntry = entry;
      _journalDockVisible = true;
    });
  }

  Future<void> _saveRightPanelWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_rightPanelWidthPrefKey, _rightPanelWidth);
  }

  void _toggleRightPanelWide() {
    setState(() {
      // From anywhere below wide → jump to wide; from wide-ish → default.
      _rightPanelWidth = _rightPanelWidth < _rightPanelWideWidth
          ? _rightPanelWideWidth
          : _rightPanelDefaultWidth;
    });
    _saveRightPanelWidth();
  }

  @override
  void initState() {
    super.initState();
    _rootMenu = _buildRootMenu();
    _loadRightPanelWidth();
    if (!kIsWeb) {
      HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    }
    // Watch for any DB write and mark the currently-viewed entity as
    // having pending changes (sync state is tracked per project/programme).
    final db = context.read<AppDatabase>();
    final syncProvider = context.read<SyncProvider>();
    _dbChangeSub = db.watchAnyChange().listen((_) {
      if (!mounted) return;
      syncProvider.markLocalChange(
          context.read<ProjectProvider>().currentProjectId);
    });

    // Best-effort: refresh programme links + cascade data on launch so a
    // PM who paired their project last night sees the connection (and any
    // cascaded data) without having to touch settings.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCascade());

    // Re-run the cascade refresh whenever the active project changes —
    // escalate a RAID item / edit a plan in a project, switch to the
    // linked programme, and it's there on first render.
    final projectProvider = context.read<ProjectProvider>();
    _projectProvider = projectProvider;
    _lastCascadeProjectId = projectProvider.currentProjectId;
    projectProvider.addListener(_onProjectChanged);
  }

  ProjectProvider? _projectProvider;
  String? _lastCascadeProjectId;
  // Bumped after a cascade refresh actually runs so views that load their
  // data once (the Gantt) remount and pick up freshly-cascaded rows.
  int _cascadeRefreshSeq = 0;

  void _onProjectChanged() {
    if (!mounted) return;
    final id = _projectProvider?.currentProjectId;
    if (id == _lastCascadeProjectId) return;
    _lastCascadeProjectId = id;
    _refreshCascade();
  }

  /// Brings cascade data up to date for the active entity, then forces a
  /// reload of one-shot views. Silent + best-effort.
  ///
  /// For a SAME-MACHINE link (the common single-install case) it replays
  /// both directions — the partner project re-pushes its catalogue
  /// (including derived fields like WP spans) and the programme pulls it
  /// in — so the programme is always fresh without depending on the PM
  /// re-saving items or a sync. For remote-only links it activates
  /// pending links and pulls on the programme side.
  Future<void> _refreshCascade() async {
    if (!mounted) return;
    final sync = context.read<SyncProvider>();
    final db = context.read<AppDatabase>();
    final token = sync.accessToken;
    try {
      final project = context.read<ProjectProvider>().currentProject;
      if (project == null) return;
      // Activate any pending_remote links the server now reports paired.
      if (token != null) {
        await db.programmeLinksDao.refreshPendingLinks(
          remoteUserId: sync.userId,
          remote: SyncLinksGateway(
              client: SyncClient(baseUrl: sync.serverUrl),
              accessToken: token),
        );
      }
      if (!mounted) return;
      final links = await db.programmeLinksDao.getLinksForEntity(project.id);
      final hasLocalLink = links
          .any((l) => l.status == 'active' && l.partnerLocalId != null);
      if (hasLocalLink) {
        // Same-machine: reconcile both sides (push partner project, pull
        // this entity) regardless of which side we're viewing.
        await sync.replayCascadeForActivation(project.id, db);
      } else if (project.kind == 'programme') {
        await buildCascadeServiceWith(db, sync).pullForProgramme(project.id);
      }
      if (mounted) setState(() => _cascadeRefreshSeq++);
    } catch (_) {
      // Quietly drop — manual refresh + next launch will retry.
    }
  }

  /// Fires [KeelEvents.sectionOpened] with a stable section tag — used
  /// to answer "which sections do users actually open?" without leaking
  /// per-user navigation patterns. Index → tag mapping lives here
  /// (rather than in the nav rail) so adding a new view requires just
  /// one new case.
  void _trackSectionOpened(int index) {
    final tag = _sectionTagFor(index);
    if (tag == null) return;
    context.analytics.track(
      KeelEvents.sectionOpened,
      props: {KeelEventProps.section: tag},
    );
  }

  String? _sectionTagFor(int index) {
    switch (index) {
      case 0:
        return null; // Programme overview — not a primary surface yet.
      case 1:
        return KeelSection.canvas;
      case 2:
        return KeelSection.raid;
      case 3:
        return KeelSection.decisions;
      case 4:
        return KeelSection.people;
      case 5:
        return KeelSection.actions;
      case 6:
        return KeelSection.inbox;
      case 7:
        return null; // Context — internal hosting page, not user-facing.
      case 8:
        return KeelSection.reports;
      case 9:
        return KeelSection.settings;
      case 10:
        return KeelSection.journal;
      case 11:
        return null; // Playbook — secondary surface.
      case 12:
        return KeelSection.plan;
      case 13:
        return KeelSection.status;
      case 14:
        return KeelSection.charter;
      case 15:
        return KeelSection.finance;
      case 16:
        return KeelSection.helm;
      default:
        return null;
    }
  }

  _MenuNode _buildRootMenu() {
    return _MenuNode('Navigate to…', {
      ' ':  _ActionNode('Overview',   () { _selectedIndex = 0; }),
      'h':  _ActionNode('Helm — my day', () { _selectedIndex = 16; }),
      't':  _MenuNode('Canvas', {
        'n': _ActionNode('Quick-capture', () {
          _selectedIndex = 1;
          _canvasInitialQuickCapture = true;
          _canvasNavSeq++;
        }),
      }, onEnter: () {
        _selectedIndex = 1;
        _canvasInitialQuickCapture = false;
        _canvasNavSeq++;
      }),
      'R':  _ActionNode('Reports',     () { _selectedIndex = 8; }),
      'd':  _MenuNode('Decisions', {
        'n': _ActionNode('New decision', () {
          _selectedIndex = 3; _decisionsTriggerNew = true; _decisionsNavSeq++;
        }),
      }, onEnter: () {
        _selectedIndex = 3; _decisionsTriggerNew = false; _decisionsNavSeq++;
      }),
      'p':  _ActionNode('People',     () { _selectedIndex = 4; }),
      'a':  _ActionNode('Actions',    () { _selectedIndex = 5; }),
      'i':  _ActionNode('Inbox',      () { _selectedIndex = 6; }),
      'c':  _MenuNode('Context', {
        'e': _MenuNode('Entries', {
          'n': _ActionNode('New entry', () {
            _selectedIndex = 7; _contextInitialTab = 0; _contextTriggerNew = true; _contextNavSeq++;
          }),
        }, onEnter: () {
          _selectedIndex = 7; _contextInitialTab = 0; _contextTriggerNew = false; _contextNavSeq++;
        }),
        'd': _MenuNode('Documents', {
          'n': _ActionNode('Upload document', () {
            _selectedIndex = 7; _contextInitialTab = 1; _contextTriggerNew = true; _contextNavSeq++;
          }),
        }, onEnter: () {
          _selectedIndex = 7; _contextInitialTab = 1; _contextTriggerNew = false; _contextNavSeq++;
        }),
        'g': _MenuNode('Glossary', {
          'n': _ActionNode('New term', () {
            _selectedIndex = 7; _contextInitialTab = 2; _contextTriggerNew = true; _contextNavSeq++;
          }),
        }, onEnter: () {
          _selectedIndex = 7; _contextInitialTab = 2; _contextTriggerNew = false; _contextNavSeq++;
        }),
      }),
      'r':  _MenuNode('RAID', {
        'r': _MenuNode('Risks', {
          'n': _ActionNode('New risk', () {
            _selectedIndex = 2; _raidInitialTab = 0; _raidTriggerNew = true; _raidNavSeq++;
          }),
        }, onEnter: () {
          _selectedIndex = 2; _raidInitialTab = 0; _raidTriggerNew = false; _raidNavSeq++;
        }),
        'a': _MenuNode('Assumptions', {
          'n': _ActionNode('New assumption', () {
            _selectedIndex = 2; _raidInitialTab = 1; _raidTriggerNew = true; _raidNavSeq++;
          }),
        }, onEnter: () {
          _selectedIndex = 2; _raidInitialTab = 1; _raidTriggerNew = false; _raidNavSeq++;
        }),
        'i': _MenuNode('Issues', {
          'n': _ActionNode('New issue', () {
            _selectedIndex = 2; _raidInitialTab = 2; _raidTriggerNew = true; _raidNavSeq++;
          }),
        }, onEnter: () {
          _selectedIndex = 2; _raidInitialTab = 2; _raidTriggerNew = false; _raidNavSeq++;
        }),
        'd': _MenuNode('Dependencies', {
          'n': _ActionNode('New dependency', () {
            _selectedIndex = 2; _raidInitialTab = 3; _raidTriggerNew = true; _raidNavSeq++;
          }),
        }, onEnter: () {
          _selectedIndex = 2; _raidInitialTab = 3; _raidTriggerNew = false; _raidNavSeq++;
        }),
      }),
      'j':  _MenuNode('Journal', {
        'n': _ActionNode('New entry (split view)', () {
          _openJournalDock();
        }),
        'q': _ActionNode('Quick capture', () { _openJournalOverlay(); }),
      }, onEnter: () { _selectedIndex = 10; }),
      'P':  _ActionNode('Playbook',   () { _selectedIndex = 11; }),
      'g':  _ActionNode('Plan',       () { _selectedIndex = 12; }),
      's':  _ActionNode('Status',     () { _selectedIndex = 13; }),
      'S':  _ActionNode('Settings',   () { _selectedIndex = 9; }),
      'C':  _ActionNode('Charter',    () { _selectedIndex = 14; }),
      'f':  _MenuNode('Finance', {
        'n': _ActionNode('New budget line', () {
          _selectedIndex = 15; _financeTriggerNew = true; _financeNavSeq++;
        }),
      }, onEnter: () {
        _selectedIndex = 15; _financeTriggerNew = false; _financeNavSeq++;
      }),
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tourTriggered) return;
    final projectId = context.read<ProjectProvider>().currentProjectId;
    final settings = context.read<SettingsProvider>();
    if (projectId != null && !settings.settings.hasSeenThreeViewTour) {
      _tourTriggered = true;
      final settingsProvider = settings;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (_) => const _ThreeViewTourDialog(),
        ).then((_) => settingsProvider.markThreeViewTourSeen());
      });
    }

    // Charter migration — always run on startup (idempotent: skips if charter
    // already exists). The UI notice is shown only once, but the data migration
    // must re-run after a sync pull in case the charter table was cleared.
    if (!_charterMigrationTriggered && projectId != null) {
      _charterMigrationTriggered = true;
      final settingsProvider = settings;
      final db = context.read<AppDatabase>();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final migrated = await CharterMigration(db).runIfNeeded();
        if (!mounted) return;
        if (!settingsProvider.settings.hasSeenCharterMigrationNotice) {
          if (migrated) {
            showDialog<void>(
              context: context,
              barrierDismissible: true,
              builder: (ctx) => CharterMigrationNotice(
                onOpenCharter: () => setState(() => _selectedIndex = 14),
                onDismiss: () {},
              ),
            ).then((_) => settingsProvider.markCharterMigrationNoticeSeen());
          } else {
            // No data to migrate — just mark as seen silently
            settingsProvider.markCharterMigrationNoticeSeen();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _dbChangeSub?.cancel();
    _projectProvider?.removeListener(_onProjectChanged);
    if (!kIsWeb) {
      HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    }
    super.dispose();
  }

  // Returns true if a text-editable widget currently has keyboard focus,
  // so we don't steal Space from text fields.
  bool _isTextInputFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final ctx = focus.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    // Walk up a few ancestors to catch TextField internals
    bool found = false;
    ctx.visitAncestorElements((el) {
      if (el.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  void _closeLeader() {
    _currentLeaderMenu = null;
    _leaderPrefix = 'SPC';
  }

  bool _handleLeaderChord(KeyEvent event) {
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      setState(_closeLeader);
      return true;
    }

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final char = key == LogicalKeyboardKey.space
        ? ' '
        : _logicalKeyChar(key, isShift);

    if (char == null) {
      setState(_closeLeader);
      return true;
    }

    final node = _currentLeaderMenu!.children[char];
    if (node == null) {
      // Unknown chord — cancel silently
      setState(_closeLeader);
      return true;
    }

    if (node is _ActionNode) {
      setState(() {
        node.action();
        _closeLeader();
      });
    } else if (node is _MenuNode) {
      setState(() {
        node.onEnter?.call();
        _currentLeaderMenu = node;
        _leaderPrefix = '$_leaderPrefix $char';
      });
    }

    return true;
  }

  static bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.capsLock;
  }

  /// Returns the printable character for a logical key, respecting shift.
  String? _logicalKeyChar(LogicalKeyboardKey key, bool shift) {
    final label = key.keyLabel;
    if (label.length == 1) {
      return shift ? label.toUpperCase() : label.toLowerCase();
    }
    return null;
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final isMetaOrCtrl =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    // ── Leader active: consume next keypress ─────────────────────────────
    if (_currentLeaderMenu != null) {
      // Ignore pure modifier keypresses — wait for the actual letter/symbol.
      if (_isModifierKey(event.logicalKey)) return false;
      return _handleLeaderChord(event);
    }

    // ── Space → activate leader (only when no text field focused) ─────────
    if (event.logicalKey == LogicalKeyboardKey.space &&
        !isMetaOrCtrl &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !_isTextInputFocused()) {
      setState(() {
        _currentLeaderMenu = _rootMenu;
        _leaderPrefix = 'SPC';
      });
      return true;
    }

    // ── Gantt layout mode shortcuts ───────────────────────────────────────
    if (_selectedIndex == 12) {
      if (event.logicalKey == LogicalKeyboardKey.f11) {
        _toggleGanttPresentation();
        return true;
      }
      if (isMetaOrCtrl && HardwareKeyboard.instance.isShiftPressed) {
        if (event.logicalKey == LogicalKeyboardKey.keyF) {
          _toggleGanttPresentation();
          return true;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyE) {
          _toggleGanttExpanded();
          return true;
        }
      }
    }

    // ── Existing Ctrl / Meta shortcuts ────────────────────────────────────
    if (!isMetaOrCtrl) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyJ) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      final isAlt = HardwareKeyboard.instance.isAltPressed;
      if (isAlt) {
        _toggleJournalDock();
      } else if (isShift) {
        setState(() => _selectedIndex = 10);
      } else {
        _openJournalOverlay();
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyI) {
      setState(() => _selectedIndex = 6);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isShiftPressed) {
      setState(() => _rightPanelVisible = !_rightPanelVisible);
      return true;
    }
    return false;
  }

  void _toggleGanttExpanded() {
    setState(() {
      _ganttMode = _ganttMode == _GanttLayoutMode.expanded
          ? _GanttLayoutMode.normal
          : _GanttLayoutMode.expanded;
    });
  }

  void _toggleGanttPresentation() {
    setState(() {
      _ganttMode = _ganttMode == _GanttLayoutMode.presentation
          ? _GanttLayoutMode.normal
          : _GanttLayoutMode.presentation;
    });
  }

  void _goToSettings() => setState(() => _selectedIndex = 9);

  /// Quick-sync straight from the header "Sync needed" pill: prompts for
  /// the encryption password and pushes the current entity. Saves a PM a
  /// trip to Settings. Falls back to Settings when sync isn't usable yet
  /// (no Solo plan), where the upgrade/sign-in UI lives.
  Future<void> _quickSync() async {
    final sync = context.read<SyncProvider>();
    final db = context.read<AppDatabase>();
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) return;
    if (sync.plan != 'solo') {
      _goToSettings();
      return;
    }
    final pwd = await showSyncPasswordDialog(context);
    if (pwd == null || pwd.isEmpty) return;
    await sync.syncProject(projectId, pwd, db);
    if (!mounted) return;
    if (sync.status == SyncStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sync failed: ${sync.lastError ?? 'unknown error'}'),
      ));
    }
  }

  void _openJournalOverlay() {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) return;
    final db = context.read<AppDatabase>();
    final settings = context.read<SettingsProvider>().settings;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      pageBuilder: (_, __, ___) => JournalOverlay(
        projectId: projectId,
        db: db,
        settings: settings,
      ),
    );
  }

  // ── Sidebar "open this item" actions ──────────────────────────────────
  // Each one navigates to the relevant section (so the user lands there
  // after dismissing the dialog) and then opens the form in view mode.

  void _openRiskFromSidebar(Risk r) {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) return;
    final db = context.read<AppDatabase>();
    setState(() {
      _selectedIndex = 2;
      _raidInitialTab = 0; // Risks tab
      _raidNavSeq++;
    });
    showDialog(
      context: context,
      builder: (_) => RiskFormDialog(
        projectId: projectId,
        db: db,
        risk: r,
        startInViewMode: true,
      ),
    );
  }

  void _openDecisionFromSidebar(Decision d) {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) return;
    final db = context.read<AppDatabase>();
    setState(() {
      _selectedIndex = 3;
      _decisionsNavSeq++;
    });
    showDialog(
      context: context,
      builder: (_) => DecisionFormDialog(
        projectId: projectId,
        db: db,
        decision: d,
        startInViewMode: true,
      ),
    );
  }

  void _openActionFromSidebar(ProjectAction a) {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) return;
    final db = context.read<AppDatabase>();
    setState(() => _selectedIndex = 5);
    showDialog(
      context: context,
      builder: (_) => ActionFormDialog(
        projectId: projectId,
        db: db,
        action: a,
        startInViewMode: true,
      ),
    );
  }

  void _openJournalFromSidebar(JournalEntry entry) {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    if (projectId == null) return;
    final db = context.read<AppDatabase>();
    final settings = context.read<SettingsProvider>().settings;
    setState(() => _selectedIndex = 10);
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      pageBuilder: (_, __, ___) => JournalOverlay(
        projectId: projectId,
        db: db,
        settings: settings,
        existingEntry: entry,
      ),
    );
  }

  /// Playbook stages aren't a dialog — instead, navigate to the playbook
  /// view and ask it to expand the named stage on its first render.
  void _openPlaybookStageFromSidebar(String stageId) {
    setState(() {
      _selectedIndex = 11;
      _playbookFocusStageId = stageId;
    });
  }

  // ── Helm rail "open this item" actions ─────────────────────────────
  // Rail items span EVERY project, so unlike the sidebar openers these
  // first switch the active project, then land on the item's section
  // with its form dialog open in view mode.

  void _switchProjectForHelmItem(String projectId) {
    final pp = context.read<ProjectProvider>();
    if (pp.currentProjectId != projectId) pp.selectProjectById(projectId);
  }

  void _openActionFromHelm(ProjectAction a) {
    _switchProjectForHelmItem(a.projectId);
    final db = context.read<AppDatabase>();
    setState(() => _selectedIndex = 5);
    showDialog(
      context: context,
      builder: (_) => ActionFormDialog(
        projectId: a.projectId,
        db: db,
        action: a,
        startInViewMode: true,
      ),
    );
  }

  void _openRiskFromHelm(Risk r) {
    _switchProjectForHelmItem(r.projectId);
    final db = context.read<AppDatabase>();
    setState(() {
      _selectedIndex = 2;
      _raidInitialTab = 0;
      _raidNavSeq++;
    });
    showDialog(
      context: context,
      builder: (_) => RiskFormDialog(
        projectId: r.projectId,
        db: db,
        risk: r,
        startInViewMode: true,
      ),
    );
  }

  void _openIssueFromHelm(Issue i) {
    _switchProjectForHelmItem(i.projectId);
    final db = context.read<AppDatabase>();
    setState(() {
      _selectedIndex = 2;
      _raidInitialTab = 2;
      _raidNavSeq++;
    });
    showDialog(
      context: context,
      builder: (_) => IssueFormDialog(
        projectId: i.projectId,
        db: db,
        issue: i,
        startInViewMode: true,
      ),
    );
  }

  void _openAssumptionFromHelm(Assumption a) {
    _switchProjectForHelmItem(a.projectId);
    final db = context.read<AppDatabase>();
    setState(() {
      _selectedIndex = 2;
      _raidInitialTab = 1;
      _raidNavSeq++;
    });
    showDialog(
      context: context,
      builder: (_) => AssumptionFormDialog(
        projectId: a.projectId,
        db: db,
        assumption: a,
        startInViewMode: true,
      ),
    );
  }

  void _openDependencyFromHelm(ProgramDependency d) {
    _switchProjectForHelmItem(d.projectId);
    final db = context.read<AppDatabase>();
    setState(() {
      _selectedIndex = 2;
      _raidInitialTab = 3;
      _raidNavSeq++;
    });
    showDialog(
      context: context,
      builder: (_) => DependencyFormDialog(
        projectId: d.projectId,
        db: db,
        dependency: d,
        startInViewMode: true,
      ),
    );
  }

  void _openDecisionFromHelm(Decision d) {
    _switchProjectForHelmItem(d.projectId);
    final db = context.read<AppDatabase>();
    setState(() {
      _selectedIndex = 3;
      _decisionsNavSeq++;
    });
    showDialog(
      context: context,
      builder: (_) => DecisionFormDialog(
        projectId: d.projectId,
        db: db,
        decision: d,
        startInViewMode: true,
      ),
    );
  }

  void _showNewProjectDialog(BuildContext context) {
    final projectProvider = context.read<ProjectProvider>();
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Project'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Project name'),
            onSubmitted: (_) {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                projectProvider.createProject(name);
                Navigator.of(ctx).pop();
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                projectProvider.createProject(name);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _loadDemo(BuildContext context) async {
    final projectProvider = context.read<ProjectProvider>();
    await projectProvider.loadDemoProject();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horizon Programme demo project loaded.')),
      );
    }
  }

  Widget _buildView() {
    switch (_selectedIndex) {
      case 0:
        return ProgrammeView(
          onNavigateToCanvas: () => setState(() => _selectedIndex = 1),
          onNavigateToCharter: () => setState(() => _selectedIndex = 14),
          onNavigateToActions: () => setState(() => _selectedIndex = 5),
          onNavigateToDecisions: () => setState(() => _selectedIndex = 3),
          onNavigateToRaid: () => setState(() => _selectedIndex = 2),
          onNavigateToPeople: () => setState(() => _selectedIndex = 4),
          onNavigateToPlaybook: () => setState(() => _selectedIndex = 11),
        );
      case 1:
        // Consume the one-shot quick-capture flag so re-renders don't
        // keep popping the overlay back open.
        final qc = _canvasInitialQuickCapture;
        _canvasInitialQuickCapture = false;
        return CanvasView(
          key: ValueKey(_canvasNavSeq),
          initialQuickCapture: qc,
        );
      case 2:
        final tab = _raidInitialTab;
        final doNew = _raidTriggerNew;
        _raidInitialTab = null;
        _raidTriggerNew = false;
        return RaidView(key: ValueKey(_raidNavSeq), initialTab: tab, triggerNew: doNew);
      case 3:
        final doNew = _decisionsTriggerNew;
        _decisionsTriggerNew = false;
        return DecisionsView(key: ValueKey(_decisionsNavSeq), triggerNew: doNew);
      case 4:
        return const PeopleView();
      case 5:
        return const ActionsView();
      case 6:
        return const InboxView();
      case 7:
        final tab = _contextInitialTab;
        final doNew = _contextTriggerNew;
        // Consume so re-renders don't retrigger
        _contextInitialTab = null;
        _contextTriggerNew = false;
        return ContextView(key: ValueKey(_contextNavSeq), initialTab: tab, triggerNew: doNew);
      case 8:
        return const ReportsView();
      case 9:
        return const SettingsView();
      case 10:
        return JournalHistoryView(
          onNewEntryDocked: () => _openJournalDock(),
          onOpenEntryDocked: (e) => _openJournalDock(entry: e),
        );
      case 11:
        final focus = _playbookFocusStageId;
        // Consume so re-renders don't keep re-expanding.
        _playbookFocusStageId = null;
        return PlaybookView(focusStageId: focus);
      case 12:
        return ProgrammeGanttView(
          cascadeRefreshSeq: _cascadeRefreshSeq,
          isExpanded: _ganttMode == _GanttLayoutMode.expanded,
          isPresentation: _ganttMode == _GanttLayoutMode.presentation,
          onToggleExpanded: _toggleGanttExpanded,
          onTogglePresentation: _toggleGanttPresentation,
        );
      case 13:
        return const StatusView();
      case 14:
        return const CharterView();
      case 15:
        final doNew = _financeTriggerNew;
        _financeTriggerNew = false;
        return FinanceView(key: ValueKey(_financeNavSeq), triggerNew: doNew);
      case 16:
        return HelmView(
          onOpenAction: _openActionFromHelm,
          onOpenRisk: _openRiskFromHelm,
          onOpenIssue: _openIssueFromHelm,
          onOpenAssumption: _openAssumptionFromHelm,
          onOpenDependency: _openDependencyFromHelm,
          onOpenDecision: _openDecisionFromHelm,
        );
      default:
        return ProgrammeView(
          onNavigateToCanvas: () => setState(() => _selectedIndex = 1),
          onNavigateToCharter: () => setState(() => _selectedIndex = 14),
          onNavigateToActions: () => setState(() => _selectedIndex = 5),
          onNavigateToDecisions: () => setState(() => _selectedIndex = 3),
          onNavigateToRaid: () => setState(() => _selectedIndex = 2),
          onNavigateToPeople: () => setState(() => _selectedIndex = 4),
          onNavigateToPlaybook: () => setState(() => _selectedIndex = 11),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;

    // Presentation mode: full-screen gantt, no chrome
    if (_selectedIndex == 12 &&
        _ganttMode == _GanttLayoutMode.presentation) {
      return Scaffold(
        backgroundColor: KColors.bg,
        body: ProgrammeGanttView(
          isExpanded: false,
          isPresentation: true,
          onToggleExpanded: _toggleGanttExpanded,
          onTogglePresentation: _toggleGanttPresentation,
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          const CriticalUpdateBanner(),
          _TopBar(onSyncTap: () => _quickSync()),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canShowLeft =
                    constraints.maxWidth >= _leftPanelWidth + 100 + 300;
                final canShowRight =
                    constraints.maxWidth >= _rightPanelWidth + 100;
                final isGanttExpanded =
                    _selectedIndex == 12 &&
                    _ganttMode == _GanttLayoutMode.expanded;
                final showLeft = _leftPanelVisible && canShowLeft;
                final showRight =
                    _rightPanelVisible && canShowRight && !isGanttExpanded;

                // Watermark opacity: higher on overview, high on onboarding
                final watermarkOpacity = projectId == null
                    ? 0.75
                    : _selectedIndex == 0
                        ? 0.55
                        : 0.40;

                return Row(
                  children: [
                    // Left panel — live pulse
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      width: showLeft ? _leftPanelWidth : 0,
                      child: showLeft
                          ? ClipRect(
                              child: LeftPanel(
                                onNavigateToRaid: () =>
                                    setState(() => _selectedIndex = 2),
                                onNavigateToDecisions: () =>
                                    setState(() => _selectedIndex = 3),
                                onNavigateToActions: () =>
                                    setState(() => _selectedIndex = 5),
                                onNavigateToJournal: () =>
                                    setState(() => _selectedIndex = 10),
                                onNavigateToPlaybook: () =>
                                    setState(() => _selectedIndex = 11),
                                onNavigateToProgramme: () =>
                                    setState(() => _selectedIndex = 0),
                                onNavigateToHelm: () =>
                                    setState(() => _selectedIndex = 16),
                                onOpenRisk: (r) =>
                                    _openRiskFromSidebar(r),
                                onOpenDecision: (d) =>
                                    _openDecisionFromSidebar(d),
                                onOpenAction: (a) =>
                                    _openActionFromSidebar(a),
                                onOpenJournal: (e) =>
                                    _openJournalFromSidebar(e),
                                onOpenPlaybookStage: (sid) =>
                                    _openPlaybookStageFromSidebar(sid),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // Left panel toggle
                    if (canShowLeft)
                      _PanelToggle(
                        visible: _leftPanelVisible,
                        onToggle: () => setState(
                            () => _leftPanelVisible = !_leftPanelVisible),
                        isLeft: true,
                      ),

                    Container(width: 1, color: KColors.border),

                    // Navigation rail
                    KeelNavRail(
                      selectedIndex: _selectedIndex,
                      isProgramme:
                          context.watch<ProjectProvider>().isProgramme,
                      onDestinationSelected: (i) {
                        setState(() {
                          _selectedIndex = i;
                          if (i != 12) _ganttMode = _GanttLayoutMode.normal;
                        });
                        _trackSectionOpened(i);
                      },
                    ),

                    Container(width: 1, color: KColors.border),

                    // Main content
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: KColors.bg),
                          Center(
                            child: AnimatedOpacity(
                              opacity: watermarkOpacity,
                              duration: const Duration(milliseconds: 500),
                              child: SvgPicture.asset(
                                'assets/keel-logo.svg',
                                width: 560,
                                height: 560,
                              ),
                            ),
                          ),
                          if (projectId == null && _selectedIndex != 9)
                            _OnboardingScreen(
                              onNewProject: () => _showNewProjectDialog(context),
                              onLoadDemo: () => _loadDemo(context),
                            )
                          else
                            _buildView(),
                          // Leader key HUD
                          if (_currentLeaderMenu != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _LeaderHud(
                                prefix: _leaderPrefix,
                                menu: _currentLeaderMenu!,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Docked journal — running meeting notes beside the app
                    if (_journalDockVisible && projectId != null) ...[
                      Container(width: 1, color: KColors.border),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (_) =>
                              setState(() => _resizingJournalDock = true),
                          onHorizontalDragUpdate: (d) => setState(() {
                            _journalDockWidth =
                                (_journalDockWidth - d.delta.dx).clamp(
                                    _journalDockMinWidth,
                                    _journalDockMaxWidth);
                          }),
                          onHorizontalDragEnd: (_) {
                            setState(() => _resizingJournalDock = false);
                            _saveJournalDockWidth();
                          },
                          child: Container(
                            width: 5,
                            color: _resizingJournalDock
                                ? KColors.amber.withValues(alpha: 0.4)
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _journalDockWidth,
                        child: JournalOverlay(
                          key: _journalDockKey,
                          projectId: projectId,
                          db: context.read<AppDatabase>(),
                          settings:
                              context.read<SettingsProvider>().settings,
                          // A stale entry from another project reverts
                          // the dock to a fresh note.
                          existingEntry:
                              _journalDockEntry?.projectId == projectId
                                  ? _journalDockEntry
                                  : null,
                          docked: true,
                          onCloseDock: () => setState(() {
                            _journalDockVisible = false;
                            _journalDockEntry = null;
                          }),
                        ),
                      ),
                    ],

                    Container(width: 1, color: KColors.border),

                    // Right panel toggle
                    if (canShowRight)
                      _PanelToggle(
                        visible: _rightPanelVisible,
                        onToggle: () => setState(
                            () => _rightPanelVisible = !_rightPanelVisible),
                        isLeft: false,
                      ),

                    // Drag handle — resize the Claude panel
                    if (showRight)
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (_) =>
                              setState(() => _resizingRightPanel = true),
                          onHorizontalDragUpdate: (d) => setState(() {
                            _rightPanelWidth =
                                (_rightPanelWidth - d.delta.dx).clamp(
                                    _rightPanelMinWidth,
                                    _rightPanelMaxWidth);
                          }),
                          onHorizontalDragEnd: (_) {
                            setState(() => _resizingRightPanel = false);
                            _saveRightPanelWidth();
                          },
                          child: Container(
                            width: 5,
                            color: _resizingRightPanel
                                ? KColors.amber.withValues(alpha: 0.4)
                                : Colors.transparent,
                          ),
                        ),
                      ),

                    // Right panel — Claude
                    AnimatedContainer(
                      duration: _resizingRightPanel
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      width: showRight ? _rightPanelWidth : 0,
                      child: showRight
                          ? ClipRect(
                              child: ClaudePanel(
                                isWide: _rightPanelWidth >=
                                    _rightPanelWideWidth,
                                onToggleWidth: _toggleRightPanelWide,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leader key HUD
// ---------------------------------------------------------------------------

class _LeaderHud extends StatelessWidget {
  final String prefix;
  final _MenuNode menu;

  const _LeaderHud({required this.prefix, required this.menu});

  @override
  Widget build(BuildContext context) {
    final entries = menu.children.entries.toList();

    return Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        border: const Border(top: BorderSide(color: KColors.border2)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Prefix breadcrumb — each part in its own chip
              ...prefix.split(' ').map((part) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: KColors.amber.withValues(alpha: 0.15),
                        border: Border.all(color: KColors.amber),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        part,
                        style: GoogleFonts.jetBrainsMono(
                          color: KColors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )),
              const SizedBox(width: 6),
              Text(
                menu.description,
                style: const TextStyle(
                    color: KColors.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              const Text(
                'ESC  cancel',
                style: TextStyle(
                    color: KColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Chord grid
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: entries.map((e) {
              final key = e.key == ' ' ? 'SPC' : e.key;
              final node = e.value;
              final hasChildren = node is _MenuNode;
              return _ChordChip(
                keyLabel: key,
                description: node.description,
                hasChildren: hasChildren,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ChordChip extends StatelessWidget {
  final String keyLabel;
  final String description;
  final bool hasChildren;

  const _ChordChip({
    required this.keyLabel,
    required this.description,
    this.hasChildren = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 28),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: KColors.surface2,
            border: Border.all(color: KColors.border2),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            keyLabel,
            style: GoogleFonts.jetBrainsMono(
              color: KColors.phosphor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          description,
          style: const TextStyle(color: KColors.textDim, fontSize: 12),
        ),
        if (hasChildren) ...[
          const SizedBox(width: 3),
          const Text('›',
              style: TextStyle(color: KColors.textMuted, fontSize: 12)),
        ],
        const SizedBox(width: 20),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Three-View Tour Dialog
// ---------------------------------------------------------------------------

class _ThreeViewTourDialog extends StatelessWidget {
  const _ThreeViewTourDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Three views. One programme.',
            style: GoogleFonts.syne(
              color: KColors.amber,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Each nav item gives you a different lens on your work.',
            style: TextStyle(color: KColors.textDim, fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            _TourItem(
              icon: Icons.bubble_chart_outlined,
              label: 'CANVAS — Strategic Thinking',
              description:
                  'Your strategic thinking surface. Sequence ideas, plan '
                  'moves before they need to happen, and pull formal items '
                  'in for active thought. Three bands: this week, next 30 '
                  'days, horizon.',
            ),
            const SizedBox(height: 12),
            _TourItem(
              icon: Icons.account_tree_outlined,
              label: 'PLAN — Programme Plan',
              description:
                  'The strategic Gantt. Workstreams, phases and long-horizon '
                  'planning laid out visually. Spot sequencing risks before '
                  'they become issues.',
            ),
            const SizedBox(height: 12),
            _TourItem(
              icon: Icons.monitor_heart_outlined,
              label: 'STATUS — Status Dashboard',
              description:
                  'Weekly health snapshot. RAG ratings, trends, top risks, '
                  'pending decisions and AI-drafted narrative — ready to '
                  'paste into your steering committee pack.',
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;

  const _TourItem({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: KColors.phosDim,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 18, color: KColors.phosphor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: KColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.05,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding Screen
// ---------------------------------------------------------------------------

class _OnboardingScreen extends StatelessWidget {
  final VoidCallback onNewProject;
  final VoidCallback onLoadDemo;

  const _OnboardingScreen({
    required this.onNewProject,
    required this.onLoadDemo,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 60.0),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'STAY THE COURSE',
            style: GoogleFonts.syne(
              color: KColors.amber,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'TPM COMMAND CENTRE',
            style: GoogleFonts.jetBrainsMono(
              color: KColors.textDim,
              fontSize: 11,
              letterSpacing: 0.25,
            ),
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: onNewProject,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Project'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onLoadDemo,
                icon: const Icon(Icons.science_outlined, size: 16, color: KColors.phosphor),
                label: const Text(
                  'Load Demo Data',
                  style: TextStyle(color: KColors.phosphor),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  side: const BorderSide(color: KColors.phosphor, width: 1),
                ),
              ),
            ],
          ),
        ],
      ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Top Bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final VoidCallback? onSyncTap;
  const _TopBar({this.onSyncTap});

  @override
  Widget build(BuildContext context) {
    final projectProvider = context.watch<ProjectProvider>();
    final db = context.read<AppDatabase>();
    final settings = context.watch<SettingsProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final hasKey = settings.hasApiKey;
    final projectId = projectProvider.currentProjectId;

    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: KColors.surface,
        border: Border(bottom: BorderSide(color: KColors.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              Text(
                'KEEL',
                style: GoogleFonts.syne(
                  color: KColors.amber,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),

          const SizedBox(width: 24),

          // Divider
          Container(width: 1, height: 28, color: KColors.border),

          const SizedBox(width: 24),

          // Project selector
          SizedBox(
            width: 300,
            child: _TopBarProjectSelector(
              projectProvider: projectProvider,
              db: db,
            ),
          ),

          const Spacer(),

          // Status pills
          if (projectId != null) ...[
            _OverdueActionsPill(projectId: projectId, db: db),
            const SizedBox(width: 10),
            _PendingDecisionsPill(projectId: projectId, db: db),
            const SizedBox(width: 10),
          ],
          if (syncProvider.hasPendingChangesFor(projectId)) ...[
            _SyncNeededPill(onTap: onSyncTap),
            const SizedBox(width: 10),
          ],
          _LlmStatusPill(hasKey: hasKey),
          const SizedBox(width: 10),
          _KeybindingsButton(),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Keybindings button
// ---------------------------------------------------------------------------

class _KeybindingsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Tooltip(
        message: 'Use toolbar buttons for actions',
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: KColors.surface2,
            border: Border.all(color: KColors.border2),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.keyboard_outlined,
              size: 14, color: KColors.textMuted),
        ),
      );
    }
    return Tooltip(
      message: 'Keyboard shortcuts',
      // ExcludeFocus prevents this InkWell from grabbing keyboard focus —
      // otherwise pressing SPC (the leader key) activates this button at
      // the same time as triggering the leader chord, opening the dialog
      // unintentionally. Mouse interaction still works.
      child: ExcludeFocus(
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.keyboard_outlined, size: 16, color: KColors.amber),
                  SizedBox(width: 8),
                  Text('Keyboard Shortcuts'),
                ],
              ),
              // Scrollable + height-constrained — the keybindings list is
              // ~38 rows; without scrolling it overflows the dialog on
              // anything smaller than a 24" monitor.
              content: const SizedBox(
                width: 420,
                height: 500,
                child: SingleChildScrollView(
                  child: KeybindingsTable(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: KColors.surface2,
              border: Border.all(color: KColors.border2),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.keyboard_outlined,
                size: 14, color: KColors.textDim),
          ),
        ),
      ),
    );
  }
}

class _TopBarProjectSelector extends StatelessWidget {
  final ProjectProvider projectProvider;
  final AppDatabase db;

  const _TopBarProjectSelector({
    required this.projectProvider,
    required this.db,
  });

  @override
  Widget build(BuildContext context) {
    final projects = projectProvider.projects;
    final current = projectProvider.currentProject;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: KColors.surface2,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: KColors.border2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            // ExcludeFocus prevents Material's DropdownButton from grabbing
            // keyboard focus and responding to SPC/Enter — that would steal
            // the SPC leader key. Mouse interaction still works.
            child: ExcludeFocus(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: current?.id,
                  isExpanded: true,
                  dropdownColor: KColors.surface2,
                  style: GoogleFonts.jetBrainsMono(
                    color: KColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  hint: Text(
                    'Select project…',
                    style: GoogleFonts.jetBrainsMono(
                        color: KColors.textDim, fontSize: 14),
                  ),
                  items: [
                    ...projects.map((p) {
                      final isProg = p.kind == 'programme';
                      return DropdownMenuItem(
                        value: p.id,
                        child: Row(
                          children: [
                            // Small PROG/PROJ tag so the user always
                            // knows which kind they're switching to.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: isProg
                                    ? KColors.amberDim.withValues(alpha: 0.7)
                                    : KColors.surface,
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(
                                  color: isProg
                                      ? KColors.amber
                                      : KColors.border2,
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                isProg ? 'PROG' : 'PROJ',
                                style: GoogleFonts.jetBrainsMono(
                                  color: isProg
                                      ? KColors.amber
                                      : KColors.textMuted,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(p.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      );
                    }),
                    DropdownMenuItem(
                      value: '__new_project__',
                      child: Row(
                        children: [
                          const Icon(Icons.add, size: 14, color: KColors.amber),
                          const SizedBox(width: 4),
                          Text('New Project',
                              style: GoogleFonts.jetBrainsMono(
                                  color: KColors.amber, fontSize: 12)),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: '__new_programme__',
                      child: Row(
                        children: [
                          const Icon(Icons.workspaces_outlined,
                              size: 14, color: KColors.amber),
                          const SizedBox(width: 4),
                          Text('New Programme',
                              style: GoogleFonts.jetBrainsMono(
                                  color: KColors.amber, fontSize: 12)),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: '__demo__',
                      child: Row(
                        children: [
                          const Icon(Icons.science_outlined,
                              size: 14, color: KColors.phosphor),
                          const SizedBox(width: 4),
                          Text('Load Demo Data',
                              style: GoogleFonts.jetBrainsMono(
                                  color: KColors.phosphor, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == '__new_project__') {
                      _showNewProjectDialog(context, projectProvider,
                          kind: 'project');
                    } else if (val == '__new_programme__') {
                      _showNewProjectDialog(context, projectProvider,
                          kind: 'programme');
                    } else if (val == '__demo__') {
                      _loadDemo(context, projectProvider);
                    } else if (val != null) {
                      projectProvider.selectProjectById(val);
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        if (current != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'Delete project',
            child: InkWell(
              borderRadius: BorderRadius.circular(3),
              onTap: () => _confirmDelete(context, current, projectProvider),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.delete_outline,
                    size: 14, color: KColors.textMuted),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _loadDemo(
      BuildContext context, ProjectProvider projectProvider) async {
    await projectProvider.loadDemoProject();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Horizon Programme demo project loaded.')),
      );
    }
  }

  void _showNewProjectDialog(
      BuildContext context, ProjectProvider projectProvider,
      {String kind = 'project'}) {
    final nameCtrl = TextEditingController();
    String? startDate;
    String? copyFromId;
    // Existing entries to source people from — both kinds are valid
    // donors, so a brand-new programme can inherit from a project the
    // PM has already built up, and vice versa.
    final existingProjects = projectProvider.projects;
    final isProgramme = kind == 'programme';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isProgramme ? 'New Programme' : 'New Project'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isProgramme) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Programmes are containers that receive cascaded '
                      'work packages, risks, and reports from linked '
                      'projects. You can link projects in Phase B.',
                      style: TextStyle(
                          color: KColors.textDim,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: isProgramme
                        ? 'Programme name'
                        : 'Project name',
                  ),
                  onSubmitted: (_) => _create(
                      ctx, nameCtrl, startDate, copyFromId,
                      projectProvider,
                      kind: kind),
                ),
                const SizedBox(height: 12),
                DatePickerField(
                  label: 'Start date (optional)',
                  isoValue: startDate,
                  onChanged: (v) => setDialogState(() => startDate = v),
                ),
                if (existingProjects.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: copyFromId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Copy people from (optional)',
                      helperText:
                          'Shares team, executives, vendors and stakeholders',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('— None (start blank) —'),
                      ),
                      ...existingProjects.map((p) {
                        final isProg = p.kind == 'programme';
                        return DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(
                            isProg ? '[PROG] ${p.name}' : p.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (v) => setDialogState(() => copyFromId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _create(
                  ctx, nameCtrl, startDate, copyFromId,
                  projectProvider,
                  kind: kind),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _create(
      BuildContext ctx,
      TextEditingController controller,
      String? startDate,
      String? copyFromId,
      ProjectProvider projectProvider,
      {String kind = 'project'}) {
    final name = controller.text.trim();
    if (name.isNotEmpty) {
      projectProvider.createProject(
        name,
        startDate: startDate,
        copyPeopleFromProjectId: copyFromId,
        kind: kind,
      );
      Navigator.of(ctx).pop();
    }
  }

  void _confirmDelete(BuildContext context, Project project,
      ProjectProvider projectProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          'This will permanently delete "${project.name}" and all its data '
          '(risks, decisions, actions, people, reports, etc.).\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await projectProvider.deleteProject(project.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status Pills
// ---------------------------------------------------------------------------

class _OverdueActionsPill extends StatelessWidget {
  final String projectId;
  final AppDatabase db;

  const _OverdueActionsPill({required this.projectId, required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProjectAction>>(
      stream: db.actionsDao.watchOverdueActionsForProject(projectId),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return _StatusPill(
          label: '$count overdue',
          fg: KColors.red,
          bg: KColors.redDim,
        );
      },
    );
  }
}

class _PendingDecisionsPill extends StatelessWidget {
  final String projectId;
  final AppDatabase db;

  const _PendingDecisionsPill({required this.projectId, required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Decision>>(
      stream: db.decisionsDao.watchPendingDecisionsForProject(projectId),
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return _StatusPill(
          label: '$count pending',
          fg: KColors.amber,
          bg: KColors.amberDim,
        );
      },
    );
  }
}

class _SyncNeededPill extends StatelessWidget {
  final VoidCallback? onTap;
  const _SyncNeededPill({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Local changes not yet synced — click to sync now',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: _StatusPill(
            label: 'Sync needed',
            fg: KColors.blue,
            bg: KColors.blueDim,
          ),
        ),
      ),
    );
  }
}

class _LlmStatusPill extends StatelessWidget {
  final bool hasKey;

  const _LlmStatusPill({required this.hasKey});

  @override
  Widget build(BuildContext context) {
    return _StatusPill(
      label: hasKey ? 'LLM ready' : 'No LLM',
      fg: hasKey ? KColors.phosphor : KColors.amber,
      bg: hasKey ? KColors.phosDim : KColors.amberDim,
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;

  const _StatusPill({required this.label, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: fg),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _anim = Tween(begin: 1.0, end: 0.25)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panel Toggle
// ---------------------------------------------------------------------------

class _PanelToggle extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggle;
  final bool isLeft;

  const _PanelToggle({
    required this.visible,
    required this.onToggle,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    if (isLeft) {
      icon = visible ? Icons.chevron_left : Icons.chevron_right;
    } else {
      icon = visible ? Icons.chevron_right : Icons.chevron_left;
    }

    return Container(
      width: 16,
      color: KColors.surface,
      child: InkWell(
        onTap: onToggle,
        child: Center(
          child: Icon(icon, size: 14, color: KColors.textMuted),
        ),
      ),
    );
  }
}


