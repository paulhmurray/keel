import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import 'journal_slash_menu.dart';
import 'journal_person_mention.dart';

// Left padding for the body TextField — also used by the block cursor painter.
const _kBodyLeftPad = 12.0;

// ---------------------------------------------------------------------------
// Vim mode support
// ---------------------------------------------------------------------------

enum _VimKind { normal, insert }

/// Blocks all text insertion while in Vim Normal mode.
class _VimNormalModeFormatter extends TextInputFormatter {
  _VimNormalModeFormatter(this._isNormal);
  final bool Function() _isNormal;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    return _isNormal() ? old : next;
  }
}

// ---------------------------------------------------------------------------
// JournalEditor
// ---------------------------------------------------------------------------

class JournalEditor extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final FocusNode bodyFocusNode;
  final String entryDate;
  final List<Person> persons;
  final VoidCallback onSave;
  final bool saving;
  final bool vimMode;
  final String vimEscapeSequence;
  final Future<Person?> Function(String name)? onCreatePerson;

  const JournalEditor({
    super.key,
    required this.titleController,
    required this.bodyController,
    required this.bodyFocusNode,
    required this.entryDate,
    required this.persons,
    required this.onSave,
    this.saving = false,
    this.vimMode = false,
    this.vimEscapeSequence = '',
    this.onCreatePerson,
  });

  @override
  State<JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends State<JournalEditor> {
  bool _showSlashMenu = false;
  bool _showMentionMenu = false;
  String _slashQuery = '';
  String _mentionQuery = '';
  int _slashSelectedIndex = 0;
  int _mentionSelectedIndex = 0;

  final LayerLink _layerLink = LayerLink();
  final ScrollController _scrollController = ScrollController();

  // Vim state
  _VimKind _vimKind = _VimKind.normal;
  String _vimPending = ''; // for two-key sequences: 'd', 'g'
  DateTime? _escFirstCharAt; // for escape sequence timing

  bool get _inNormal => widget.vimMode && _vimKind == _VimKind.normal;

  @override
  void initState() {
    super.initState();
    widget.bodyController.addListener(_onBodyChanged);
    // Start in Normal mode — user presses i/a/o to begin typing
  }

  @override
  void dispose() {
    widget.bodyController.removeListener(_onBodyChanged);
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Slash / mention detection
  // ---------------------------------------------------------------------------

  void _checkEscapeSequence() {
    final seq = widget.vimEscapeSequence;
    final ctrl = widget.bodyController;
    final text = ctrl.text;
    final cursor = ctrl.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return;

    final before = text.substring(0, cursor);

    // Full sequence just completed — check timing
    if (before.endsWith(seq)) {
      if (_escFirstCharAt != null &&
          DateTime.now().difference(_escFirstCharAt!) <=
              const Duration(milliseconds: 300)) {
        _escFirstCharAt = null;
        final newCursor = cursor - seq.length;
        final newText = text.substring(0, newCursor) + text.substring(cursor);
        // Schedule to avoid modifying controller inside its own listener callback
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ctrl.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newCursor),
            composing: TextRange.empty,
          );
          _enterNormal();
        });
      } else {
        _escFirstCharAt = null;
      }
      return;
    }

    // First char of sequence just typed — start timing window
    if (before.endsWith(seq[0])) {
      _escFirstCharAt = DateTime.now();
    } else {
      _escFirstCharAt = null;
    }
  }

  void _onBodyChanged() {
    if (_inNormal) return; // don't trigger menus in Normal mode

    // Escape sequence detection (Insert mode only)
    if (widget.vimMode &&
        _vimKind == _VimKind.insert &&
        widget.vimEscapeSequence.length >= 2) {
      _checkEscapeSequence();
    }

    final text = widget.bodyController.text;
    final cursor = widget.bodyController.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return;

    final textBeforeCursor = text.substring(0, cursor);

    final slashMatch =
        RegExp(r'(?:^|[\n ])(\/\w*)$').firstMatch(textBeforeCursor);
    if (slashMatch != null) {
      final query = slashMatch.group(1)!.substring(1);
      final wasShowing = _showSlashMenu && _slashQuery == query;
      setState(() {
        _showSlashMenu = true;
        _showMentionMenu = false;
        _slashQuery = query;
        if (!wasShowing) _slashSelectedIndex = 0;
      });
      return;
    }

    final mentionMatch = RegExp(r'@(\w*)$').firstMatch(textBeforeCursor);
    if (mentionMatch != null) {
      final query = mentionMatch.group(1)!;
      final wasShowing = _showMentionMenu && _mentionQuery == query;
      setState(() {
        _showMentionMenu = true;
        _showSlashMenu = false;
        _mentionQuery = query;
        if (!wasShowing) _mentionSelectedIndex = 0;
      });
      return;
    }

    if (_showSlashMenu || _showMentionMenu) {
      setState(() {
        _showSlashMenu = false;
        _showMentionMenu = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Slash / mention insertion
  // ---------------------------------------------------------------------------

  void _insertSlashTemplate(SlashCommand cmd) {
    final ctrl = widget.bodyController;
    final text = ctrl.text;
    final cursor = ctrl.selection.baseOffset;
    final textBefore = text.substring(0, cursor);
    final slashStart = textBefore.lastIndexOf('/');
    if (slashStart < 0) return;

    final now = DateTime.now();
    final dateStr =
        '${now.day} ${const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][now.month - 1]} ${now.year}';
    final resolved = cmd.template.replaceAll('{{today}}', dateStr);

    final newText =
        text.substring(0, slashStart) + resolved + text.substring(cursor);
    ctrl.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: slashStart + resolved.length),
    );
    setState(() {
      _showSlashMenu = false;
      _slashSelectedIndex = 0;
    });
  }

  void _insertMention(Person person) {
    final ctrl = widget.bodyController;
    final text = ctrl.text;
    final cursor = ctrl.selection.baseOffset;
    final atStart = text.lastIndexOf('@', cursor - 1);
    if (atStart < 0) return;

    final mention = '@${person.name} ';
    final newText =
        text.substring(0, atStart) + mention + text.substring(cursor);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atStart + mention.length),
    );
    setState(() {
      _showMentionMenu = false;
      _mentionSelectedIndex = 0;
    });
  }

  Future<void> _handleAddPerson() async {
    if (widget.onCreatePerson == null) return;
    final person = await widget.onCreatePerson!(_mentionQuery);
    if (person != null && mounted) {
      _insertMention(person);
    } else if (mounted) {
      setState(() => _showMentionMenu = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Vim: cursor helpers
  // ---------------------------------------------------------------------------

  TextEditingController get _ctrl => widget.bodyController;
  String get _text => _ctrl.text;
  int get _cursor => _ctrl.selection.baseOffset.clamp(0, _text.length);

  void _moveTo(int offset) {
    final clamped = offset.clamp(0, _text.length);
    _ctrl.selection = TextSelection.collapsed(offset: clamped);
  }

  // Move left (h)
  void _vimH() => _moveTo(_cursor - 1);

  // Move right (l)
  void _vimL() {
    final pos = _cursor;
    // Don't move past the end of the line
    if (pos < _text.length && _text[pos] != '\n') _moveTo(pos + 1);
  }

  // Move down (j)
  void _vimJ() {
    final pos = _cursor;
    final lineStart = _lineStart(pos);
    final col = pos - lineStart;
    final nextLineStart = _text.indexOf('\n', pos);
    if (nextLineStart < 0) return; // already on last line
    final nextLineEnd = _nextLineEnd(nextLineStart + 1);
    _moveTo((nextLineStart + 1 + col).clamp(nextLineStart + 1, nextLineEnd));
  }

  // Move up (k)
  void _vimK() {
    final pos = _cursor;
    final lineStart = _lineStart(pos);
    if (lineStart == 0) return; // already on first line
    final col = pos - lineStart;
    final prevLineEnd = lineStart - 1; // the '\n' char
    final prevLineStart = _lineStart(prevLineEnd);
    _moveTo((prevLineStart + col).clamp(prevLineStart, prevLineEnd));
  }

  // Start of line (0)
  void _vim0() => _moveTo(_lineStart(_cursor));

  // End of line ($)
  void _vimDollar() {
    final end = _nextLineEnd(_cursor);
    _moveTo(end);
  }

  // Forward word (w)
  void _vimW() {
    var i = _cursor;
    if (i >= _text.length) return;
    // Skip current word chars
    if (_isWordChar(_text[i])) {
      while (i < _text.length && _isWordChar(_text[i])) { i++; }
    } else {
      while (i < _text.length && !_isWordChar(_text[i]) && _text[i] != '\n') {
        i++;
      }
    }
    // Skip whitespace
    while (i < _text.length && (_text[i] == ' ' || _text[i] == '\t')) { i++; }
    _moveTo(i);
  }

  // Backward word (b)
  void _vimB() {
    var i = _cursor;
    if (i == 0) return;
    i--; // step back one
    // Skip whitespace
    while (i > 0 && (_text[i] == ' ' || _text[i] == '\t' || _text[i] == '\n')) {
      i--;
    }
    // Skip word
    if (_isWordChar(_text[i])) {
      while (i > 0 && _isWordChar(_text[i - 1])) { i--; }
    }
    _moveTo(i);
  }

  // Go to start (gg)
  void _vimGG() => _moveTo(0);

  // Go to end (G)
  void _vimG() => _moveTo(_text.length);

  // Delete char under cursor (x)
  void _vimX() {
    final pos = _cursor;
    if (pos >= _text.length) return;
    final newText = _text.substring(0, pos) + _text.substring(pos + 1);
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: pos.clamp(0, newText.length)),
    );
  }

  // Delete line (dd)
  void _vimDD() {
    final pos = _cursor;
    final start = _lineStart(pos);
    var end = _text.indexOf('\n', pos);
    if (end < 0) {
      // Last line — also remove the preceding newline if any
      final newText = start > 0
          ? _text.substring(0, start - 1)
          : '';
      _ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
            offset: (start - 1).clamp(0, newText.length)),
      );
    } else {
      // Remove line + newline
      final newText = _text.substring(0, start) + _text.substring(end + 1);
      _ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
            offset: start.clamp(0, newText.length)),
      );
    }
  }

  // Open line below (o) → insert mode
  void _vimO() {
    final pos = _cursor;
    var end = _text.indexOf('\n', pos);
    if (end < 0) end = _text.length;
    final newText = _text.substring(0, end) + '\n' + _text.substring(end);
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: end + 1),
    );
    _enterInsert();
  }

  // Open line above (O) → insert mode
  void _vimOUpper() {
    final pos = _cursor;
    final start = _lineStart(pos);
    final newText = _text.substring(0, start) + '\n' + _text.substring(start);
    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start),
    );
    _enterInsert();
  }

  void _enterInsert() => setState(() {
        _vimKind = _VimKind.insert;
        _vimPending = '';
      });

  void _enterNormal() => setState(() {
        _vimKind = _VimKind.normal;
        _vimPending = '';
        // Dismiss any menus
        _showSlashMenu = false;
        _showMentionMenu = false;
      });

  // Helpers
  int _lineStart(int pos) {
    if (pos <= 0) return 0;
    final idx = _text.lastIndexOf('\n', pos - 1);
    return idx < 0 ? 0 : idx + 1;
  }

  int _nextLineEnd(int fromPos) {
    final idx = _text.indexOf('\n', fromPos);
    return idx < 0 ? _text.length : idx;
  }

  bool _isWordChar(String c) => RegExp(r'\w').hasMatch(c);

  // ---------------------------------------------------------------------------
  // Key handler
  // ---------------------------------------------------------------------------

  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isMetaOrCtrl = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    // Ctrl+Enter → save (always)
    if (isMetaOrCtrl && event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onSave();
      return KeyEventResult.handled;
    }

    // ── Slash menu navigation ────────────────────────────────────────────────
    if (_showSlashMenu) {
      final items = filteredSlashCommands(_slashQuery);
      if (items.isNotEmpty) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.tab) {
          setState(() => _slashSelectedIndex =
              (_slashSelectedIndex + 1) % items.length);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() => _slashSelectedIndex =
              (_slashSelectedIndex - 1 + items.length) % items.length);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _insertSlashTemplate(
              items[_slashSelectedIndex.clamp(0, items.length - 1)]);
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _showSlashMenu = false);
        return KeyEventResult.handled;
      }
    }

    // ── Mention menu navigation ──────────────────────────────────────────────
    if (_showMentionMenu) {
      final items = filteredPersons(widget.persons, _mentionQuery);
      final showAdd =
          _mentionQuery.isNotEmpty && widget.onCreatePerson != null;
      final total = items.length + (showAdd ? 1 : 0);
      if (total > 0) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.tab) {
          setState(() =>
              _mentionSelectedIndex = (_mentionSelectedIndex + 1) % total);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() => _mentionSelectedIndex =
              (_mentionSelectedIndex - 1 + total) % total);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (showAdd && _mentionSelectedIndex == items.length) {
            _handleAddPerson();
          } else if (items.isNotEmpty) {
            _insertMention(
                items[_mentionSelectedIndex.clamp(0, items.length - 1)]);
          }
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _showMentionMenu = false);
        return KeyEventResult.handled;
      }
    }

    // ── Vim: Insert mode — only Esc is special ───────────────────────────────
    if (widget.vimMode && _vimKind == _VimKind.insert) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _enterNormal();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // let TextField handle everything else
    }

    // ── Vim: Normal mode — intercept all keys ────────────────────────────────
    if (widget.vimMode && _vimKind == _VimKind.normal) {
      // Esc in Normal mode passes through to the parent (overlay) to close it —
      // consistent with vim where Esc in normal mode has no further action.
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        return KeyEventResult.ignored;
      }
      return _handleNormalKey(event);
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleNormalKey(KeyEvent event) {
    // Allow Ctrl combos to pass through (copy/paste etc.)
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }

    final char = event.character; // actual typed char (shift-aware)
    final key = event.logicalKey;

    // ── Two-key sequences ────────────────────────────────────────────────────
    if (_vimPending == 'd') {
      setState(() => _vimPending = '');
      if (char == 'd') { _vimDD(); return KeyEventResult.handled; }
      return KeyEventResult.handled; // unknown — consume and reset
    }
    if (_vimPending == 'g') {
      setState(() => _vimPending = '');
      if (char == 'g') { _vimGG(); return KeyEventResult.handled; }
      return KeyEventResult.handled;
    }

    // ── Single-key commands ──────────────────────────────────────────────────
    switch (char) {
      // Enter insert mode
      case 'i': _enterInsert(); return KeyEventResult.handled;
      case 'I': _vim0(); _enterInsert(); return KeyEventResult.handled;
      case 'a':
        _moveTo(_cursor + 1);
        _enterInsert();
        return KeyEventResult.handled;
      case 'A': _vimDollar(); _enterInsert(); return KeyEventResult.handled;
      case 'o': _vimO(); return KeyEventResult.handled; // opens + enters insert
      case 'O': _vimOUpper(); return KeyEventResult.handled;

      // Motions
      case 'h': _vimH(); return KeyEventResult.handled;
      case 'l': _vimL(); return KeyEventResult.handled;
      case 'j': _vimJ(); return KeyEventResult.handled;
      case 'k': _vimK(); return KeyEventResult.handled;
      case 'w': _vimW(); return KeyEventResult.handled;
      case 'b': _vimB(); return KeyEventResult.handled;
      case '0': _vim0(); return KeyEventResult.handled;
      case r'$': _vimDollar(); return KeyEventResult.handled;
      case 'G': _vimG(); return KeyEventResult.handled;

      // Operations
      case 'x': _vimX(); return KeyEventResult.handled;

      // Start of two-key sequences
      case 'd':
        setState(() => _vimPending = 'd');
        return KeyEventResult.handled;
      case 'g':
        setState(() => _vimPending = 'g');
        return KeyEventResult.handled;
    }

    // Arrow keys work in normal mode for navigation
    if (key == LogicalKeyboardKey.arrowLeft) { _vimH(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowRight) { _vimL(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowDown) { _vimJ(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowUp) { _vimK(); return KeyEventResult.handled; }

    // Consume everything else in normal mode (don't let chars be typed)
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleEditorKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title field
          TextField(
            controller: widget.titleController,
            style: const TextStyle(
              color: KColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              hintText: 'Entry title (optional)',
              hintStyle: TextStyle(color: KColors.textMuted, fontSize: 18),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 4),
              prefixIcon: Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.edit_note_outlined,
                    color: KColors.amber, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.entryDate,
            style: const TextStyle(
              color: KColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: KColors.border, height: 1),
          const SizedBox(height: 16),

          // Body editor
          Expanded(
            child: Stack(
              children: [
                CompositedTransformTarget(
                  link: _layerLink,
                  child: TextField(
                    controller: widget.bodyController,
                    focusNode: widget.bodyFocusNode,
                    scrollController: _scrollController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    // Hide built-in cursor in Vim Normal mode — we draw our own block
                    showCursor: !_inNormal,
                    inputFormatters: [
                      if (widget.vimMode)
                        _VimNormalModeFormatter(() => _inNormal),
                    ],
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 13,
                      height: 1.7,
                    ),
                    decoration: const InputDecoration(
                      hintText:
                          'Write meeting notes, observations, decisions...\n\nType / for commands, @ to mention someone.',
                      hintStyle: TextStyle(
                        color: KColors.textMuted,
                        fontSize: 13,
                        height: 1.7,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.only(
                          left: _kBodyLeftPad, top: 8, bottom: 80),
                    ),
                  ),
                ),

                // Block cursor overlay for Vim Normal mode
                if (_inNormal)
                  IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, constraints) => ListenableBuilder(
                        listenable: Listenable.merge(
                            [widget.bodyController, _scrollController]),
                        builder: (context, _) => CustomPaint(
                          size: Size(
                              constraints.maxWidth, constraints.maxHeight),
                          painter: _BlockCursorPainter(
                            controller: widget.bodyController,
                            scrollOffset: _scrollController.hasClients
                                ? _scrollController.offset
                                : 0.0,
                            availableWidth: constraints.maxWidth - _kBodyLeftPad,
                          ),
                        ),
                      ),
                    ),
                  ),

                if (_showSlashMenu)
                  Positioned(
                    top: 40,
                    left: 0,
                    child: JournalSlashMenu(
                      query: _slashQuery,
                      selectedIndex: _slashSelectedIndex,
                      onSelect: _insertSlashTemplate,
                      onDismiss: () =>
                          setState(() => _showSlashMenu = false),
                    ),
                  ),

                if (_showMentionMenu)
                  Positioned(
                    top: 40,
                    left: 0,
                    child: JournalPersonMention(
                      persons: widget.persons,
                      query: _mentionQuery,
                      selectedIndex: _mentionSelectedIndex,
                      onSelect: _insertMention,
                      onAddNew: widget.onCreatePerson != null
                          ? _handleAddPerson
                          : null,
                    ),
                  ),
              ],
            ),
          ),

          // Footer
          const Divider(color: KColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                if (widget.vimMode) ...[
                  _VimModeBadge(kind: _vimKind),
                  const SizedBox(width: 12),
                ] else ...[
                  _buildHint('⌘↵', 'Save & parse'),
                  const SizedBox(width: 16),
                  _buildHint('/', 'Commands'),
                  const SizedBox(width: 16),
                  _buildHint('@', 'Mention'),
                  const SizedBox(width: 16),
                  _buildHint('↑↓', 'Navigate menu'),
                ],
                const Spacer(),
                ListenableBuilder(
                  listenable: widget.bodyController,
                  builder: (context, _) => Text(
                    '${widget.bodyController.text.length} chars',
                    style: const TextStyle(
                        color: KColors.textMuted, fontSize: 10),
                  ),
                ),
                if (widget.saving) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: KColors.amber,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint(String keyLabel, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: KColors.border2),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(keyLabel,
              style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 9,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Block cursor painter (Vim Normal mode)
// ---------------------------------------------------------------------------

class _BlockCursorPainter extends CustomPainter {
  static const _textStyle = TextStyle(
    color: KColors.text,
    fontSize: 13,
    height: 1.7,
  );
  static const _topPadding = 8.0;             // matches TextField contentPadding.top
  static const _leftPadding = _kBodyLeftPad;  // matches TextField contentPadding.left

  final TextEditingController controller;
  final double scrollOffset;
  final double availableWidth;

  _BlockCursorPainter({
    required this.controller,
    required this.scrollOffset,
    required this.availableWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final text = controller.text;
    final sel = controller.selection;
    if (!sel.isValid) return;
    final cursor = sel.baseOffset.clamp(0, text.length);

    // Lay out the full text so we can query cursor geometry
    final painter = TextPainter(
      text: TextSpan(text: text, style: _textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: availableWidth);

    final lineHeight = painter.preferredLineHeight;

    // Cursor top-left in the TextPainter coordinate space
    final caretOffset = painter.getOffsetForCaret(
      TextPosition(offset: cursor),
      Rect.fromLTWH(0, 0, 0, lineHeight),
    );

    // Character width: measure the box of the char under the cursor
    double charWidth = lineHeight * 0.55; // sensible fallback (~half line height)
    if (cursor < text.length && text[cursor] != '\n') {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: cursor, extentOffset: cursor + 1),
      );
      if (boxes.isNotEmpty) {
        charWidth = boxes.first.right - boxes.first.left;
      }
    }

    // Translate from TextPainter coords to widget coords
    final top = caretOffset.dy + _topPadding - scrollOffset;
    final left = caretOffset.dx + _leftPadding;

    // Clip to visible area
    if (top + lineHeight < 0 || top > size.height) return;

    // Semi-transparent phosphor fill
    canvas.drawRect(
      Rect.fromLTWH(left, top, charWidth.clamp(2.0, 24.0), lineHeight),
      Paint()
        ..color = KColors.phosphor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    // Solid left edge (classic block cursor look)
    canvas.drawRect(
      Rect.fromLTWH(left, top, 2, lineHeight),
      Paint()
        ..color = KColors.phosphor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_BlockCursorPainter old) =>
      old.controller != controller ||
      old.scrollOffset != scrollOffset ||
      old.availableWidth != availableWidth;
}

// ---------------------------------------------------------------------------
// Vim mode badge shown in footer
// ---------------------------------------------------------------------------

class _VimModeBadge extends StatelessWidget {
  final _VimKind kind;
  const _VimModeBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final isNormal = kind == _VimKind.normal;
    final label = isNormal ? 'NORMAL' : 'INSERT';
    final color = isNormal ? KColors.phosphor : KColors.amber;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (isNormal) ...[
          const SizedBox(width: 10),
          Text('i insert  a append  o new line  gg top  G end  dd delete line',
              style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
        ] else ...[
          const SizedBox(width: 10),
          Text('Esc  normal mode',
              style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
        ],
      ],
    );
  }
}
