import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/keybindings_table.dart';
import '../programme/programme_view.dart';
import '../timeline/timeline_view.dart';
import '../raid/raid_view.dart';
import '../decisions/decisions_view.dart';
import '../people/people_view.dart';
import '../actions/actions_view.dart';
import '../inbox/inbox_view.dart';
import '../context/context_view.dart';
import '../reports/reports_view.dart';
import '../settings/settings_view.dart';
import '../journal/journal_history_view.dart';
import '../journal/journal_overlay.dart';
import '../playbook/playbook_view.dart';
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

class _ShellLayoutState extends State<ShellLayout> {
  int _selectedIndex = 0;
  bool _leftPanelVisible = true;
  bool _rightPanelVisible = true;
  StreamSubscription<void>? _dbChangeSub;

  // Deep-navigation state (set by leader bindings, consumed by _buildView)
  int? _contextInitialTab;
  bool _contextTriggerNew = false;
  int? _raidInitialTab;
  bool _raidTriggerNew = false;
  bool _decisionsTriggerNew = false;

  // Leader key state — null = inactive, non-null = active at this menu node
  _MenuNode? _currentLeaderMenu;
  String _leaderPrefix = 'SPC';
  late final _MenuNode _rootMenu;

  static const double _leftPanelWidth = 220.0;
  static const double _rightPanelWidth = 280.0;

  @override
  void initState() {
    super.initState();
    _rootMenu = _buildRootMenu();
    if (!kIsWeb) {
      HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    }
    // Watch for any DB write and mark as pending sync
    final db = context.read<AppDatabase>();
    final syncProvider = context.read<SyncProvider>();
    _dbChangeSub = db.watchAnyChange().listen((_) {
      syncProvider.markLocalChange();
    });
  }

  _MenuNode _buildRootMenu() {
    return _MenuNode('Navigate to…', {
      ' ':  _ActionNode('Overview',   () { _selectedIndex = 0; }),
      't':  _ActionNode('Timeline',   () { _selectedIndex = 1; }),
      'R':  _ActionNode('Reports',     () { _selectedIndex = 8; }),
      'd':  _MenuNode('Decisions', {
        'n': _ActionNode('New decision', () {
          _selectedIndex = 3; _decisionsTriggerNew = true;
        }),
      }, onEnter: () {
        _selectedIndex = 3; _decisionsTriggerNew = false;
      }),
      'p':  _ActionNode('People',     () { _selectedIndex = 4; }),
      'a':  _ActionNode('Actions',    () { _selectedIndex = 5; }),
      'i':  _ActionNode('Inbox',      () { _selectedIndex = 6; }),
      'c':  _MenuNode('Context', {
        'e': _MenuNode('Entries', {
          'n': _ActionNode('New entry', () {
            _selectedIndex = 7; _contextInitialTab = 0; _contextTriggerNew = true;
          }),
        }, onEnter: () {
          _selectedIndex = 7; _contextInitialTab = 0; _contextTriggerNew = false;
        }),
        'd': _MenuNode('Documents', {
          'n': _ActionNode('Upload document', () {
            _selectedIndex = 7; _contextInitialTab = 1; _contextTriggerNew = true;
          }),
        }, onEnter: () {
          _selectedIndex = 7; _contextInitialTab = 1; _contextTriggerNew = false;
        }),
        'g': _MenuNode('Glossary', {
          'n': _ActionNode('New term', () {
            _selectedIndex = 7; _contextInitialTab = 2; _contextTriggerNew = true;
          }),
        }, onEnter: () {
          _selectedIndex = 7; _contextInitialTab = 2; _contextTriggerNew = false;
        }),
      }),
      'r':  _MenuNode('RAID', {
        'r': _MenuNode('Risks', {
          'n': _ActionNode('New risk', () {
            _selectedIndex = 2; _raidInitialTab = 0; _raidTriggerNew = true;
          }),
        }, onEnter: () {
          _selectedIndex = 2; _raidInitialTab = 0; _raidTriggerNew = false;
        }),
        'a': _MenuNode('Assumptions', {
          'n': _ActionNode('New assumption', () {
            _selectedIndex = 2; _raidInitialTab = 1; _raidTriggerNew = true;
          }),
        }, onEnter: () {
          _selectedIndex = 2; _raidInitialTab = 1; _raidTriggerNew = false;
        }),
        'i': _MenuNode('Issues', {
          'n': _ActionNode('New issue', () {
            _selectedIndex = 2; _raidInitialTab = 2; _raidTriggerNew = true;
          }),
        }, onEnter: () {
          _selectedIndex = 2; _raidInitialTab = 2; _raidTriggerNew = false;
        }),
        'd': _MenuNode('Dependencies', {
          'n': _ActionNode('New dependency', () {
            _selectedIndex = 2; _raidInitialTab = 3; _raidTriggerNew = true;
          }),
        }, onEnter: () {
          _selectedIndex = 2; _raidInitialTab = 3; _raidTriggerNew = false;
        }),
      }),
      'j':  _ActionNode('Journal',    () { _selectedIndex = 10; }),
      'P':  _ActionNode('Playbook',   () { _selectedIndex = 11; }),
    });
  }

  @override
  void dispose() {
    _dbChangeSub?.cancel();
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

    // ── Existing Ctrl / Meta shortcuts ────────────────────────────────────
    if (!isMetaOrCtrl) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyJ) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if (isShift) {
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

  void _goToSettings() => setState(() => _selectedIndex = 9);

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
          onNavigateToTimeline: () => setState(() => _selectedIndex = 1),
        );
      case 1:
        return const TimelineView();
      case 2:
        final tab = _raidInitialTab;
        final doNew = _raidTriggerNew;
        _raidInitialTab = null;
        _raidTriggerNew = false;
        return RaidView(initialTab: tab, triggerNew: doNew);
      case 3:
        final doNew = _decisionsTriggerNew;
        _decisionsTriggerNew = false;
        return DecisionsView(triggerNew: doNew);
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
        return ContextView(initialTab: tab, triggerNew: doNew);
      case 8:
        return const ReportsView();
      case 9:
        return const SettingsView();
      case 10:
        return const JournalHistoryView();
      case 11:
        return const PlaybookView();
      default:
        return ProgrammeView(
          onNavigateToTimeline: () => setState(() => _selectedIndex = 1),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;

    return Scaffold(
      body: Column(
        children: [
          const CriticalUpdateBanner(),
          _TopBar(onSyncTap: _goToSettings),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canShowLeft =
                    constraints.maxWidth >= _leftPanelWidth + 100 + 300;
                final canShowRight =
                    constraints.maxWidth >= _rightPanelWidth + 100;
                final showLeft = _leftPanelVisible && canShowLeft;
                final showRight = _rightPanelVisible && canShowRight;

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
                      onDestinationSelected: (i) =>
                          setState(() => _selectedIndex = i),
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

                    Container(width: 1, color: KColors.border),

                    // Right panel toggle
                    if (canShowRight)
                      _PanelToggle(
                        visible: _rightPanelVisible,
                        onToggle: () => setState(
                            () => _rightPanelVisible = !_rightPanelVisible),
                        isLeft: false,
                      ),

                    // Right panel — Claude
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      width: showRight ? _rightPanelWidth : 0,
                      child: showRight
                          ? const ClipRect(child: ClaudePanel())
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
              _HealthCompassIcon(projectId: projectId, db: db),
              const SizedBox(width: 10),
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
          if (syncProvider.hasPendingChanges) ...[
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
            content: const SizedBox(
              width: 420,
              child: KeybindingsTable(),
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
                  ...projects.map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.w600)),
                      )),
                  DropdownMenuItem(
                    value: '__new__',
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
                  if (val == '__new__') {
                    _showNewProjectDialog(context, projectProvider);
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
      BuildContext context, ProjectProvider projectProvider) {
    final nameCtrl = TextEditingController();
    String? startDate;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Project'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration:
                      const InputDecoration(labelText: 'Project name'),
                  onSubmitted: (_) =>
                      _create(ctx, nameCtrl, startDate, projectProvider),
                ),
                const SizedBox(height: 12),
                DatePickerField(
                  label: 'Start date (optional)',
                  isoValue: startDate,
                  onChanged: (v) => setDialogState(() => startDate = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  _create(ctx, nameCtrl, startDate, projectProvider),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _create(BuildContext ctx, TextEditingController controller,
      String? startDate, ProjectProvider projectProvider) {
    final name = controller.text.trim();
    if (name.isNotEmpty) {
      projectProvider.createProject(name, startDate: startDate);
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
      message: 'Local changes not yet synced — click to go to Settings',
      child: GestureDetector(
        onTap: onTap,
        child: _StatusPill(
          label: 'Sync needed',
          fg: KColors.blue,
          bg: KColors.blueDim,
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

// ---------------------------------------------------------------------------
// Health-reactive compass icon
// ---------------------------------------------------------------------------

/// Watches live project health and feeds a needle angle to [_AnimatedCompassIcon].
class _HealthCompassIcon extends StatelessWidget {
  final String? projectId;
  final AppDatabase db;

  const _HealthCompassIcon({required this.projectId, required this.db});

  static int _score(String v) =>
      v.toLowerCase() == 'high' ? 3 : v.toLowerCase() == 'medium' ? 2 : 1;

  @override
  Widget build(BuildContext context) {
    if (projectId == null) return const _AnimatedCompassIcon(targetAngle: 0);

    return StreamBuilder<List<ProjectAction>>(
      stream: db.actionsDao.watchOverdueActionsForProject(projectId!),
      builder: (context, overdueSnap) {
        final overdueCount = overdueSnap.data?.length ?? 0;
        return StreamBuilder<List<Risk>>(
          stream: db.raidDao.watchOpenRisksForProject(projectId!),
          builder: (context, riskSnap) {
            final risks = riskSnap.data ?? [];
            final hasRed = risks
                .any((r) => _score(r.likelihood) * _score(r.impact) >= 9);
            final hasAmber = risks
                .any((r) => _score(r.likelihood) * _score(r.impact) >= 4);

            // Needle drifts east as programme health worsens
            double angle = 0.0;
            if (hasRed || overdueCount >= 3) {
              angle = 0.55; // ~31°
            } else if (hasAmber || overdueCount >= 1) {
              angle = 0.28; // ~16°
            }
            return _AnimatedCompassIcon(targetAngle: angle);
          },
        );
      },
    );
  }
}

class _AnimatedCompassIcon extends StatefulWidget {
  final double targetAngle; // radians

  const _AnimatedCompassIcon({required this.targetAngle});

  @override
  State<_AnimatedCompassIcon> createState() => _AnimatedCompassIconState();
}

class _AnimatedCompassIconState extends State<_AnimatedCompassIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _angle = Tween<double>(begin: 0, end: widget.targetAngle).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AnimatedCompassIcon old) {
    super.didUpdateWidget(old);
    if (old.targetAngle != widget.targetAngle) {
      final from = _angle.value;
      _angle = Tween<double>(begin: from, end: widget.targetAngle).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
      );
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _angle,
      builder: (context, child) => CustomPaint(
        size: const Size(36, 36),
        painter: _CompassPainter(needleAngle: _angle.value),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double needleAngle;

  const _CompassPainter({required this.needleAngle});

  static const _bg = Color(0xFF0a0d0f);
  static const _ring1 = Color(0xFF253040);
  static const _ring2 = Color(0xFF1e2830);
  static const _amber = Color(0xFFe8a430);
  static const _phos = Color(0xFF2dd4a0);

  @override
  void paint(Canvas canvas, Size size) {
    // Scale from 128×128 SVG viewBox to actual size
    canvas.scale(size.width / 128, size.height / 128);

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 128, 128), const Radius.circular(24)),
      Paint()..color = _bg,
    );

    canvas.translate(64, 64);

    final thinStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Rings
    canvas.drawCircle(
        Offset.zero, 46, thinStroke..color = _ring1..strokeWidth = 0.8);
    canvas.drawCircle(
        Offset.zero, 30, thinStroke..color = _ring2..strokeWidth = 0.8);

    // Crosshairs
    final xhair = Paint()
      ..color = _ring2
      ..strokeWidth = 0.5;
    canvas.drawLine(const Offset(0, -50), const Offset(0, 50), xhair);
    canvas.drawLine(const Offset(-50, 0), const Offset(50, 0), xhair);

    // Ring tick dots
    final dot = Paint()..color = _ring2;
    for (final p in [
      const Offset(0, -30), const Offset(0, 30),
      const Offset(-30, 0), const Offset(30, 0),
    ]) {
      canvas.drawCircle(p, 2, dot);
    }

    // ── Needle (rotated) ──────────────────────────────────────
    canvas.save();
    canvas.rotate(needleAngle);

    // North needle (amber)
    canvas.drawPath(
      Path()
        ..moveTo(0, -26)
        ..lineTo(6, -4)
        ..lineTo(0, 0)
        ..lineTo(-6, -4)
        ..close(),
      Paint()..color = _amber,
    );

    // South needle (dark)
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(6, 4)
        ..lineTo(0, 26)
        ..lineTo(-6, 4)
        ..close(),
      Paint()..color = _ring1,
    );

    // Spine
    canvas.drawLine(
      const Offset(0, -26),
      const Offset(0, 26),
      Paint()
        ..color = _amber
        ..strokeWidth = 1.0,
    );

    // North cap chevron
    canvas.drawPath(
      Path()
        ..moveTo(-5, -43)
        ..lineTo(0, -50)
        ..lineTo(5, -43),
      Paint()
        ..color = _amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();
    // ── End needle ────────────────────────────────────────────

    // Pivot ring
    canvas.drawCircle(Offset.zero, 4,
        Paint()
          ..color = _bg
          ..style = PaintingStyle.fill);
    canvas.drawCircle(Offset.zero, 4,
        Paint()
          ..color = _amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    // Centre dot
    canvas.drawCircle(Offset.zero, 1.5, Paint()..color = _amber);

    // Phosphor bearing dot
    canvas.drawCircle(
      const Offset(26, -15),
      2.5,
      Paint()..color = _phos.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_CompassPainter old) => old.needleAngle != needleAngle;
}

