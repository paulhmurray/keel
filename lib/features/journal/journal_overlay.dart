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
  String? _savedEntryId;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existingEntry;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _bodyCtrl = TextEditingController(text: e?.body ?? '');
    _bodyFocus = FocusNode();
    _savedEntryId = e?.id;
    _bodyCtrl.addListener(() => _hasChanges = true);
    _loadPersons();
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
    final persons = await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = persons);
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

    // Save to DB
    final entryId = _savedEntryId ?? const Uuid().v4();
    _savedEntryId = entryId;
    final now = DateTime.now();
    final title = _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim();

    await widget.db.journalDao.upsertEntry(JournalEntriesCompanion(
      id: Value(entryId),
      projectId: Value(widget.projectId),
      title: Value(title),
      body: Value(body),
      entryDate: Value(_entryDate),
      parsed: const Value(false),
      createdAt: Value(now),
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

    if (mounted) {
      setState(() {
        _deltas = deltas;
        _phase = _OverlayPhase.reviewing;
      });
    }
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
          if (_phase == _OverlayPhase.editor)
            const Text(
              'Cmd+Enter to save · Esc to close',
              style: TextStyle(color: KColors.textMuted, fontSize: 10),
            ),
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
            onSave: _saveAndParse,
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
                        child: Text(
                          _bodyCtrl.text,
                          style: const TextStyle(
                            color: KColors.text,
                            fontSize: 12,
                            height: 1.7,
                          ),
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
