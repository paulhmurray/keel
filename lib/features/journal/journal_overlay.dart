import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import '../../core/database/database.dart';
import '../../core/journal/journal_parser.dart';
import '../../core/journal/journal_linker.dart';
import '../../core/llm/llm_client.dart';
import '../../core/llm/llm_client_factory.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import 'journal_editor.dart';
import 'journal_delta_panel.dart';
import 'journal_link_renderer.dart';

enum _OverlayPhase { editor, parsing, reviewing }

class JournalOverlay extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final AppSettings settings;
  final JournalEntry? existingEntry;

  const JournalOverlay({
    super.key,
    required this.projectId,
    required this.db,
    required this.settings,
    this.existingEntry,
  });

  @override
  State<JournalOverlay> createState() => _JournalOverlayState();
}

class _JournalOverlayState extends State<JournalOverlay> {
  _OverlayPhase _phase = _OverlayPhase.editor;
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;
  late FocusNode _bodyFocus;
  List<DetectedDelta> _deltas = [];
  List<Person> _persons = [];
  List<GlossaryEntry> _glossaryEntries = [];
  String? _savedEntryId;
  // Track original content to detect real changes (not just focus/cursor moves)
  String _originalBody = '';
  String _originalTitle = '';
  bool _forceReparse = false;

  bool get _hasChanges =>
      _bodyCtrl.text.trim() != _originalBody.trim() ||
      _titleCtrl.text.trim() != _originalTitle.trim();

  bool get _alreadyParsed => widget.existingEntry?.parsed ?? false;

  @override
  void initState() {
    super.initState();
    final e = widget.existingEntry;
    _originalBody = e?.body ?? '';
    _originalTitle = e?.title ?? '';
    _titleCtrl = TextEditingController(text: _originalTitle);
    _bodyCtrl = TextEditingController(text: _originalBody);
    _bodyFocus = FocusNode();
    _savedEntryId = e?.id;
    _loadPersons();
    _loadGlossaryEntries();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bodyFocus.requestFocus());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPersons() async {
    final persons =
        await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = persons);
  }

  Future<void> _loadGlossaryEntries() async {
    final entries =
        await widget.db.glossaryDao.getForProject(widget.projectId);
    if (mounted) setState(() => _glossaryEntries = entries);
  }

  Future<GlossaryEntry?> _createGlossaryEntry(String name) async {
    if (!mounted) return null;
    final result = await showDialog<GlossaryEntry>(
      context: context,
      builder: (_) => _QuickGlossaryDialog(name: name),
    );
    if (result != null) {
      await widget.db.glossaryDao.upsert(GlossaryEntriesCompanion(
        id: Value(result.id),
        projectId: Value(widget.projectId),
        name: Value(result.name),
        acronym: Value(result.acronym),
        type: Value(result.type),
        description: Value(result.description),
        createdAt: Value(result.createdAt),
        updatedAt: Value(result.updatedAt),
      ));
      await _loadGlossaryEntries();
    }
    return result;
  }

  Future<Person?> _createPerson(String name) async {
    if (!mounted) return null;
    final result = await showDialog<Person>(
      context: context,
      builder: (_) => _QuickPersonDialog(name: name),
    );
    if (result != null) {
      await widget.db.peopleDao.upsertPerson(PersonsCompanion(
        id: Value(result.id),
        projectId: Value(widget.projectId),
        name: Value(result.name),
        role: Value(result.role),
        organisation: Value(result.organisation),
        createdAt: Value(result.createdAt),
        updatedAt: Value(result.updatedAt),
      ));
      await _loadPersons();
    }
    return result;
  }

  String get _entryDate {
    if (widget.existingEntry != null) return widget.existingEntry!.entryDate;
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _formatDisplayDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  Future<void> _saveAndParse() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) {
      _close();
      return;
    }

    final entryId = _savedEntryId ?? const Uuid().v4();
    _savedEntryId = entryId;
    final now = DateTime.now();
    final title = _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim();
    final contentChanged = body != _originalBody.trim();

    // If already parsed and nothing changed (and not a forced re-parse),
    // just save any title/metadata edits and close — no re-parse.
    if (_alreadyParsed && !contentChanged && !_forceReparse) {
      if (_hasChanges) {
        final existing = await widget.db.journalDao.getEntryById(entryId);
        await widget.db.journalDao.upsertEntry(JournalEntriesCompanion(
          id: Value(entryId),
          projectId: Value(widget.projectId),
          title: Value(title),
          body: Value(body),
          entryDate: Value(_entryDate),
          parsed: const Value(true),
          confirmedAt: Value(existing?.confirmedAt),
          createdAt: Value(existing?.createdAt ?? now),
          updatedAt: Value(now),
        ));
      }
      _close();
      return;
    }

    // Save to DB — mark as not-yet-parsed until review is confirmed
    await widget.db.journalDao.upsertEntry(JournalEntriesCompanion(
      id: Value(entryId),
      projectId: Value(widget.projectId),
      title: Value(title),
      body: Value(body),
      entryDate: Value(_entryDate),
      parsed: const Value(false),
      createdAt: Value(
          widget.existingEntry?.createdAt ?? now),
      updatedAt: Value(now),
    ));

    setState(() => _phase = _OverlayPhase.parsing);

    // Parse
    LLMClient? llmClient;
    if (widget.settings.hasApiKey) {
      try {
        llmClient = LLMClientFactory.fromSettings(widget.settings);
      } catch (_) {}
    }

    final parser = JournalParser(llmClient: llmClient);
    final deltas = await parser.parse(body);

    // Filter out items already extracted from this entry in a previous parse
    final filteredDeltas = await _filterAlreadyExtracted(entryId, deltas);

    if (mounted) {
      setState(() {
        _deltas = filteredDeltas;
        _forceReparse = false;
        _phase = _OverlayPhase.reviewing;
      });
    }
  }

  /// Loads existing journal_entry_links for this entry and marks any delta
  /// whose description matches an already-linked item as ignored, so the
  /// user is not asked to confirm duplicates.
  Future<List<DetectedDelta>> _filterAlreadyExtracted(
      String entryId, List<DetectedDelta> deltas) async {
    final links = await widget.db.journalDao.getLinksForEntry(entryId);
    if (links.isEmpty) return deltas;

    // Build a set of already-extracted descriptions (lowercased)
    final existingDescs = <String>{};
    for (final link in links) {
      String? desc;
      switch (link.itemType) {
        case 'action':
          desc = (await widget.db.actionsDao.getActionById(link.itemId))?.description;
        case 'decision':
          desc = (await widget.db.decisionsDao.getDecisionById(link.itemId))?.description;
        case 'risk':
          desc = (await widget.db.raidDao.getRiskById(link.itemId))?.description;
        case 'issue':
          final issue = await (widget.db.select(widget.db.issues)
                ..where((t) => t.id.equals(link.itemId)))
              .getSingleOrNull();
          desc = issue?.description;
        case 'dependency':
          final dep = await (widget.db.select(widget.db.programDependencies)
                ..where((t) => t.id.equals(link.itemId)))
              .getSingleOrNull();
          desc = dep?.description;
      }
      if (desc != null && desc.isNotEmpty) {
        existingDescs.add(desc.toLowerCase().trim());
      }
    }

    // Mark deltas that match existing extractions as ignored
    for (final delta in deltas) {
      final desc =
          (delta.editFields['description'] ?? delta.title).toLowerCase().trim();
      if (existingDescs.contains(desc)) {
        delta.ignored = true;
      }
    }
    return deltas;
  }

  Future<void> _confirmAll() async {
    for (final d in _deltas.where((d) => !d.ignored)) {
      d.confirmed = true;
    }
    await _commitAndClose();
  }

  Future<void> _commitAndClose() async {
    if (_savedEntryId == null) {
      _close();
      return;
    }
    final linker = JournalLinker(
      db: widget.db,
      projectId: widget.projectId,
      entryId: _savedEntryId!,
    );
    await linker.commitDeltas(_deltas);
    if (mounted) _close();
  }

  void _close() {
    Navigator.of(context).pop();
  }

  void _attemptClose() {
    if (_hasChanges && _bodyCtrl.text.trim().isNotEmpty && _phase == _OverlayPhase.editor) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsaved entry'),
          content: const Text('Save this entry before closing?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _close();
              },
              child: const Text('Discard'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _saveAndParse();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } else {
      _close();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _attemptClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKey,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: _phase == _OverlayPhase.reviewing
                ? MediaQuery.of(context).size.width * 0.85
                : 800,
            height: MediaQuery.of(context).size.height * 0.80,
            constraints: const BoxConstraints(maxWidth: 1200),
            decoration: BoxDecoration(
              color: KColors.bg,
              border: Border.all(color: KColors.border2),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Title bar
                _buildTitleBar(),
                // Content
                Expanded(
                  child: _buildContent(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.menu_book_outlined, size: 14, color: KColors.amber),
          const SizedBox(width: 8),
          Text(
            _phase == _OverlayPhase.reviewing
                ? 'REVIEW CHANGES — ${_formatDisplayDate(_entryDate)}'
                : 'JOURNAL — ${_formatDisplayDate(_entryDate)}',
            style: const TextStyle(
              color: KColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
            ),
          ),
          const Spacer(),
          if (_phase == _OverlayPhase.editor) ...[
            if (_alreadyParsed)
              InkWell(
                onTap: () {
                  setState(() => _forceReparse = true);
                  _saveAndParse();
                },
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: KColors.border2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'Re-parse',
                    style: TextStyle(color: KColors.textDim, fontSize: 10),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            const Text(
              'Cmd+Enter to save · Esc to close',
              style: TextStyle(color: KColors.textMuted, fontSize: 10),
            ),
          ],
          const SizedBox(width: 16),
          InkWell(
            onTap: _attemptClose,
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: KColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case _OverlayPhase.editor:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: JournalEditor(
            titleController: _titleCtrl,
            bodyController: _bodyCtrl,
            bodyFocusNode: _bodyFocus,
            entryDate: _formatDisplayDate(_entryDate),
            persons: _persons,
            glossaryEntries: _glossaryEntries,
            onSave: _saveAndParse,
            onCreatePerson: _createPerson,
            onCreateGlossaryEntry: _createGlossaryEntry,
          ),
        );

      case _OverlayPhase.parsing:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: KColors.amber, strokeWidth: 2),
              SizedBox(height: 16),
              Text(
                'Analysing entry...',
                style: TextStyle(color: KColors.textDim, fontSize: 12),
              ),
            ],
          ),
        );

      case _OverlayPhase.reviewing:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left: entry body (read-only)
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: KColors.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_titleCtrl.text.isNotEmpty) ...[
                      Text(
                        _titleCtrl.text,
                        style: const TextStyle(
                          color: KColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      _formatDisplayDate(_entryDate),
                      style: const TextStyle(
                          color: KColors.amber, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: KColors.border, height: 1),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: JournalLinkRenderer(
                          text: _bodyCtrl.text,
                          persons: _persons,
                          glossaryEntries: _glossaryEntries,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _phase = _OverlayPhase.editor),
                      icon: const Icon(Icons.edit_outlined, size: 12),
                      label: const Text('Edit entry', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(foregroundColor: KColors.textDim),
                    ),
                  ],
                ),
              ),
            ),
            // Right: delta panel
            SizedBox(
              width: 320,
              child: JournalDeltaPanel(
                deltas: _deltas,
                onConfirmAll: _confirmAll,
                onDismiss: _commitAndClose,
              ),
            ),
          ],
        );
    }
  }
}

class _QuickPersonDialog extends StatefulWidget {
  final String name;
  const _QuickPersonDialog({required this.name});

  @override
  State<_QuickPersonDialog> createState() => _QuickPersonDialogState();
}

class _QuickPersonDialogState extends State<_QuickPersonDialog> {
  late TextEditingController _nameCtrl;
  final _roleCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _orgCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    final person = Person(
      id: const Uuid().v4(),
      projectId: '',
      name: name,
      email: null,
      role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
      organisation:
          _orgCtrl.text.trim().isEmpty ? null : _orgCtrl.text.trim(),
      phone: null,
      teamsHandle: null,
      personType: 'stakeholder',
      createdAt: now,
      updatedAt: now,
    );
    Navigator.of(context).pop(person);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Add Person',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: KColors.textDim, fontSize: 12),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _roleCtrl,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Role (optional)',
                labelStyle: TextStyle(color: KColors.textDim, fontSize: 12),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _orgCtrl,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Organisation (optional)',
                labelStyle: TextStyle(color: KColors.textDim, fontSize: 12),
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
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _QuickGlossaryDialog extends StatefulWidget {
  final String name;
  const _QuickGlossaryDialog({required this.name});

  @override
  State<_QuickGlossaryDialog> createState() => _QuickGlossaryDialogState();
}

class _QuickGlossaryDialogState extends State<_QuickGlossaryDialog> {
  late TextEditingController _nameCtrl;
  final _acronymCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _type = 'term';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _acronymCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    final entry = GlossaryEntry(
      id: const Uuid().v4(),
      projectId: '',
      name: name,
      acronym: _acronymCtrl.text.trim().isEmpty ? null : _acronymCtrl.text.trim(),
      type: _type,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      owner: null,
      environment: null,
      status: null,
      createdAt: now,
      updatedAt: now,
    );
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Add Glossary Entry',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Type toggle
            Row(
              children: [
                const Text('Type:',
                    style: TextStyle(color: KColors.textDim, fontSize: 12)),
                const SizedBox(width: 12),
                _TypeToggle(
                  value: _type,
                  onChanged: (v) => setState(() => _type = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: KColors.textDim, fontSize: 12),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _acronymCtrl,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Acronym (optional)',
                labelStyle: TextStyle(color: KColors.textDim, fontSize: 12),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: KColors.textDim, fontSize: 12),
                alignLabelWithHint: true,
              ),
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
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _TypeToggle extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;
  const _TypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleBtn(
          label: 'Term',
          selected: value == 'term',
          onTap: () => onChanged('term'),
        ),
        const SizedBox(width: 6),
        _ToggleBtn(
          label: 'System',
          selected: value == 'system',
          onTap: () => onChanged('system'),
        ),
      ],
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? KColors.phosDim : Colors.transparent,
          border: Border.all(
            color: selected ? KColors.phosphor : KColors.border2,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? KColors.phosphor : KColors.textDim,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
