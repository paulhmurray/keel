import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../features/journal/journal_glossary_mention.dart';
import '../../features/journal/journal_person_mention.dart';
import 'person_picker_field.dart';

/// A [TextField] that triggers @mention (people) and #mention (glossary)
/// overlays — matching the journal editor experience.
class MentionTextField extends StatefulWidget {
  final TextEditingController controller;
  final List<Person> persons;
  final List<GlossaryEntry> glossaryEntries;
  final AppDatabase db;
  final String projectId;
  /// Called after a new person is successfully created, so the parent can
  /// refresh its persons list.
  final VoidCallback? onPersonCreated;
  final InputDecoration decoration;
  final int? maxLines;
  final TextStyle style;
  final VoidCallback? onEditingComplete;

  const MentionTextField({
    super.key,
    required this.controller,
    required this.persons,
    required this.glossaryEntries,
    required this.db,
    required this.projectId,
    this.onPersonCreated,
    this.decoration = const InputDecoration(),
    this.maxLines,
    this.style = const TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
    this.onEditingComplete,
  });

  @override
  State<MentionTextField> createState() => _MentionTextFieldState();
}

class _MentionTextFieldState extends State<MentionTextField> {
  bool _showMentionMenu = false;
  bool _showGlossaryMenu = false;
  String _mentionQuery = '';
  String _glossaryQuery = '';
  int _mentionSelectedIndex = 0;
  int _glossarySelectedIndex = 0;

  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlayCtrl = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return;

    final before = text.substring(0, cursor);

    final mentionMatch = RegExp(r'@(\w*)$').firstMatch(before);
    if (mentionMatch != null) {
      final query = mentionMatch.group(1)!;
      if (!mounted) return;
      setState(() {
        _showMentionMenu = true;
        _showGlossaryMenu = false;
        _mentionQuery = query;
        _mentionSelectedIndex = 0;
      });
      if (!_overlayCtrl.isShowing) _overlayCtrl.show();
      return;
    }

    final glossaryMatch = RegExp(r'#(\w*)$').firstMatch(before);
    if (glossaryMatch != null) {
      final query = glossaryMatch.group(1)!;
      if (!mounted) return;
      setState(() {
        _showGlossaryMenu = true;
        _showMentionMenu = false;
        _glossaryQuery = query;
        _glossarySelectedIndex = 0;
      });
      if (!_overlayCtrl.isShowing) _overlayCtrl.show();
      return;
    }

    if (_showMentionMenu || _showGlossaryMenu) {
      if (!mounted) return;
      setState(() {
        _showMentionMenu = false;
        _showGlossaryMenu = false;
      });
      if (_overlayCtrl.isShowing) _overlayCtrl.hide();
    }
  }

  void _dismissOverlay() {
    setState(() {
      _showMentionMenu = false;
      _showGlossaryMenu = false;
    });
    if (_overlayCtrl.isShowing) _overlayCtrl.hide();
  }

  // ---------------------------------------------------------------------------
  // Insertion
  // ---------------------------------------------------------------------------

  void _insertMention(Person person) {
    final ctrl = widget.controller;
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
    _dismissOverlay();
  }

  void _insertGlossaryLink(GlossaryEntry entry) {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final cursor = ctrl.selection.baseOffset;
    final hashStart = text.lastIndexOf('#', cursor - 1);
    if (hashStart < 0) return;

    final link = '#${entry.name} ';
    final newText = text.substring(0, hashStart) + link + text.substring(cursor);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: hashStart + link.length),
    );
    _dismissOverlay();
  }

  Future<void> _handleAddPerson() async {
    final result = await showDialog<NewPersonResult>(
      context: context,
      builder: (_) => AddPersonDialog(
        name: _mentionQuery,
        db: widget.db,
        projectId: widget.projectId,
      ),
    );
    if (!mounted) return;
    if (result != null) {
      final now = DateTime.now();
      final id = const Uuid().v4();
      await widget.db.peopleDao.upsertPerson(PersonsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        name: Value(result.name),
        role: Value(result.role),
        organisation: Value(result.organisation),
        personType: Value(result.personType),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      widget.onPersonCreated?.call();
      if (mounted) {
        final created = Person(
          id: id,
          projectId: widget.projectId,
          name: result.name,
          role: result.role,
          organisation: result.organisation,
          personType: result.personType,
          createdAt: now,
          updatedAt: now,
        );
        _insertMention(created);
      }
    } else {
      _dismissOverlay();
    }
  }

  // ---------------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------------

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (_showMentionMenu) {
      final items = filteredPersons(widget.persons, _mentionQuery);
      final showAdd = _mentionQuery.isNotEmpty;
      final total = items.length + (showAdd ? 1 : 0);
      if (total > 0) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() => _mentionSelectedIndex = (_mentionSelectedIndex + 1) % total);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() =>
              _mentionSelectedIndex = (_mentionSelectedIndex - 1 + total) % total);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (showAdd && _mentionSelectedIndex == items.length) {
            _handleAddPerson();
          } else if (items.isNotEmpty) {
            _insertMention(items[_mentionSelectedIndex.clamp(0, items.length - 1)]);
          }
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _dismissOverlay();
        return KeyEventResult.handled;
      }
    }

    if (_showGlossaryMenu) {
      final items = filteredGlossaryEntries(widget.glossaryEntries, _glossaryQuery);
      final total = items.length; // no add-new for glossary in this context
      if (total > 0) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() =>
              _glossarySelectedIndex = (_glossarySelectedIndex + 1) % total);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(() =>
              _glossarySelectedIndex = (_glossarySelectedIndex - 1 + total) % total);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (items.isNotEmpty) {
            _insertGlossaryLink(
                items[_glossarySelectedIndex.clamp(0, items.length - 1)]);
          }
          return KeyEventResult.handled;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _dismissOverlay();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKey,
      child: OverlayPortal(
        controller: _overlayCtrl,
        overlayChildBuilder: (ctx) => CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          // Anchor the bottom-left of the menu to the top-left of the field,
          // so the menu appears above the text field.
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          child: Material(
            color: Colors.transparent,
            child: _showMentionMenu
                ? JournalPersonMention(
                    persons: widget.persons,
                    query: _mentionQuery,
                    selectedIndex: _mentionSelectedIndex,
                    onSelect: _insertMention,
                    onAddNew: _handleAddPerson,
                  )
                : _showGlossaryMenu
                    ? JournalGlossaryMention(
                        entries: widget.glossaryEntries,
                        query: _glossaryQuery,
                        selectedIndex: _glossarySelectedIndex,
                        onSelect: _insertGlossaryLink,
                      )
                    : const SizedBox.shrink(),
          ),
        ),
        child: CompositedTransformTarget(
          link: _layerLink,
          child: TextField(
            controller: widget.controller,
            maxLines: widget.maxLines,
            style: widget.style,
            decoration: widget.decoration,
            onEditingComplete: widget.onEditingComplete,
          ),
        ),
      ),
    );
  }
}
