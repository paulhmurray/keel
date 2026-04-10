import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import 'journal_slash_menu.dart';
import 'journal_person_mention.dart';

class JournalEditor extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final FocusNode bodyFocusNode;
  final String entryDate;
  final List<Person> persons;
  final VoidCallback onSave;
  final bool saving;

  const JournalEditor({
    super.key,
    required this.titleController,
    required this.bodyController,
    required this.bodyFocusNode,
    required this.entryDate,
    required this.persons,
    required this.onSave,
    this.saving = false,
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

  @override
  void initState() {
    super.initState();
    widget.bodyController.addListener(_onBodyChanged);
  }

  @override
  void dispose() {
    widget.bodyController.removeListener(_onBodyChanged);
    super.dispose();
  }

  void _onBodyChanged() {
    final text = widget.bodyController.text;
    final cursor = widget.bodyController.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return;

    final textBeforeCursor = text.substring(0, cursor);

    // Check for slash command
    final slashMatch = RegExp(r'(?:^|[\n ])(\/\w*)$').firstMatch(textBeforeCursor);
    if (slashMatch != null) {
      final query = slashMatch.group(1)!.substring(1); // remove /
      final wasShowing = _showSlashMenu && _slashQuery == query;
      setState(() {
        _showSlashMenu = true;
        _showMentionMenu = false;
        _slashQuery = query;
        if (!wasShowing) _slashSelectedIndex = 0;
      });
      return;
    }

    // Check for @ mention
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

  void _insertSlashTemplate(SlashCommand cmd) {
    final ctrl = widget.bodyController;
    final text = ctrl.text;
    final cursor = ctrl.selection.baseOffset;
    final textBefore = text.substring(0, cursor);
    final slashStart = textBefore.lastIndexOf('/');
    if (slashStart < 0) return;

    final newText = text.substring(0, slashStart) + cmd.template + text.substring(cursor);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: slashStart + cmd.template.length),
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
    final newText = text.substring(0, atStart) + mention + text.substring(cursor);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atStart + mention.length),
    );
    setState(() {
      _showMentionMenu = false;
      _mentionSelectedIndex = 0;
    });
  }

  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isMetaOrCtrl = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    if (isMetaOrCtrl && event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onSave();
      return KeyEventResult.handled;
    }

    // Slash command menu navigation
    if (_showSlashMenu) {
      final items = filteredSlashCommands(_slashQuery);
      if (items.isNotEmpty) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.tab) {
          setState(() =>
              _slashSelectedIndex = (_slashSelectedIndex + 1) % items.length);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() =>
              _slashSelectedIndex = (_slashSelectedIndex - 1 + items.length) % items.length);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _insertSlashTemplate(items[_slashSelectedIndex.clamp(0, items.length - 1)]);
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _showSlashMenu = false);
        return KeyEventResult.handled;
      }
    }

    // Person mention menu navigation
    if (_showMentionMenu) {
      final items = filteredPersons(widget.persons, _mentionQuery);
      if (items.isNotEmpty) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.tab) {
          setState(() =>
              _mentionSelectedIndex = (_mentionSelectedIndex + 1) % items.length);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() =>
              _mentionSelectedIndex = (_mentionSelectedIndex - 1 + items.length) % items.length);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _insertMention(items[_mentionSelectedIndex.clamp(0, items.length - 1)]);
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _showMentionMenu = false);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

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
                child: Icon(Icons.edit_note_outlined, color: KColors.amber, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Date indicator
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

          // Body editor with popup overlay
          Expanded(
            child: Stack(
              children: [
                CompositedTransformTarget(
                  link: _layerLink,
                  child: TextField(
                    controller: widget.bodyController,
                    focusNode: widget.bodyFocusNode,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    scrollPadding: const EdgeInsets.only(bottom: 120),
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 13,
                      height: 1.7,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Write meeting notes, observations, decisions...\n\nType / for commands, @ to mention someone.',
                      hintStyle: TextStyle(
                        color: KColors.textMuted,
                        fontSize: 13,
                        height: 1.7,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.only(top: 8, bottom: 80),
                    ),
                  ),
                ),

                // Slash command menu
                if (_showSlashMenu)
                  Positioned(
                    top: 40,
                    left: 0,
                    child: JournalSlashMenu(
                      query: _slashQuery,
                      selectedIndex: _slashSelectedIndex,
                      onSelect: _insertSlashTemplate,
                      onDismiss: () => setState(() => _showSlashMenu = false),
                    ),
                  ),

                // Person mention menu
                if (_showMentionMenu)
                  Positioned(
                    top: 40,
                    left: 0,
                    child: JournalPersonMention(
                      persons: widget.persons,
                      query: _mentionQuery,
                      selectedIndex: _mentionSelectedIndex,
                      onSelect: _insertMention,
                    ),
                  ),
              ],
            ),
          ),

          // Footer hints
          const Divider(color: KColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _buildHint('⌘↵', 'Save & parse'),
                const SizedBox(width: 16),
                _buildHint('/', 'Commands'),
                const SizedBox(width: 16),
                _buildHint('@', 'Mention'),
                const SizedBox(width: 16),
                _buildHint('↑↓', 'Navigate menu'),
                const Spacer(),
                ListenableBuilder(
                  listenable: widget.bodyController,
                  builder: (context, _) => Text(
                    '${widget.bodyController.text.length} chars',
                    style: const TextStyle(color: KColors.textMuted, fontSize: 10),
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
                  color: KColors.textDim, fontSize: 9, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
      ],
    );
  }
}
