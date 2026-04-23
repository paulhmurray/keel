import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/inbox/inbox_item_draft.dart';
import '../../core/inbox/parsers/md_parser.dart';
import '../../core/inbox/parsers/org_parser.dart';
import '../../core/inbox/parsers/txt_parser.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/source_badge.dart';
import '../../shared/widgets/status_chip.dart';

// ---------------------------------------------------------------------------
// InboxView — top-level widget
// ---------------------------------------------------------------------------

class InboxView extends StatelessWidget {
  const InboxView({super.key});

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project to view inbox.'));
    }

    final db = context.read<AppDatabase>();

    return _InboxBody(projectId: projectId, db: db);
  }
}

// ---------------------------------------------------------------------------
// _InboxBody — stateful wrapper for the two-section layout
// ---------------------------------------------------------------------------

class _InboxBody extends StatefulWidget {
  final String projectId;
  final AppDatabase db;

  const _InboxBody({required this.projectId, required this.db});

  @override
  State<_InboxBody> createState() => _InboxBodyState();
}

class _InboxBodyState extends State<_InboxBody> {
  final _quickEntryCtrl = TextEditingController();
  final _filePathCtrl = TextEditingController();
  bool _parsing = false;
  String? _parseError;

  @override
  void dispose() {
    _quickEntryCtrl.dispose();
    _filePathCtrl.dispose();
    super.dispose();
  }

  // ---- Quick Entry --------------------------------------------------------

  Future<void> _parseAndAddQuickEntry() async {
    final text = _quickEntryCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _parsing = true;
      _parseError = null;
    });

    try {
      final drafts = TxtParser().parse(text, sourceLabel: 'manual_entry');
      await _saveDrafts(drafts, 'manual_entry');
      _quickEntryCtrl.clear();
    } catch (e) {
      setState(() => _parseError = 'Parse error: $e');
    } finally {
      setState(() => _parsing = false);
    }
  }

  // ---- File Loading -------------------------------------------------------

  Future<void> _loadFromFilePath() async {
    final path = _filePathCtrl.text.trim();
    if (path.isEmpty) return;

    setState(() {
      _parsing = true;
      _parseError = null;
    });

    try {
      final file = File(path);
      if (!file.existsSync()) {
        setState(() => _parseError = 'File not found: $path');
        return;
      }

      final content = await file.readAsString();
      final ext = path.toLowerCase();
      String sourceType;
      List<InboxItemDraft> drafts;

      if (ext.endsWith('.org')) {
        sourceType = 'org_file';
        drafts = OrgParser().parse(content, sourceLabel: path);
      } else if (ext.endsWith('.md')) {
        sourceType = 'md_file';
        drafts = MdParser().parse(content, sourceLabel: path);
      } else {
        sourceType = 'txt_file';
        drafts = TxtParser().parse(content, sourceLabel: path);
      }

      await _saveDrafts(drafts, sourceType);
      _filePathCtrl.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${drafts.length} items from file.')),
        );
      }
    } catch (e) {
      setState(() => _parseError = 'Error loading file: $e');
    } finally {
      setState(() => _parsing = false);
    }
  }

  Future<void> _saveDrafts(List<InboxItemDraft> drafts, String sourceType) async {
    for (final draft in drafts) {
      await widget.db.inboxDao.insertInboxItem(
        InboxItemsCompanion(
          id: Value(const Uuid().v4()),
          projectId: Value(widget.projectId),
          content: Value(draft.rawText),
          source: Value(sourceType),
          status: const Value('unprocessed'),
          tags: Value(draft.parsedType),
          linkedItemId: const Value(null),
          linkedItemType: Value(draft.parsedData.isNotEmpty ? draft.toJsonString() : null),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page header
          Row(
            children: [
              const Icon(Icons.inbox, color: KColors.amber, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text('Inbox',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quick entry card
          _QuickEntryCard(
            quickEntryCtrl: _quickEntryCtrl,
            filePathCtrl: _filePathCtrl,
            parsing: _parsing,
            parseError: _parseError,
            onParseAndAdd: _parseAndAddQuickEntry,
            onLoadFile: _loadFromFilePath,
          ),

          const SizedBox(height: 16),

          // Inbox queue
          Expanded(
            child: _InboxQueue(
              projectId: widget.projectId,
              db: widget.db,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _QuickEntryCard
// ---------------------------------------------------------------------------

class _QuickEntryCard extends StatelessWidget {
  final TextEditingController quickEntryCtrl;
  final TextEditingController filePathCtrl;
  final bool parsing;
  final String? parseError;
  final VoidCallback onParseAndAdd;
  final VoidCallback onLoadFile;

  const _QuickEntryCard({
    required this.quickEntryCtrl,
    required this.filePathCtrl,
    required this.parsing,
    required this.parseError,
    required this.onParseAndAdd,
    required this.onLoadFile,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Entry',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: KColors.amber),
            ),
            const SizedBox(height: 4),
            const Text(
              'Paste or type notes. Lines starting with TODO:, RISK:, DECISION:, ACTION: are auto-detected.',
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quickEntryCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText:
                    'TODO: Follow up with Alice\nRISK: Budget might be exceeded\nDecided to use microservices...',
                border: OutlineInputBorder(),
              ),
            ),
            if (parseError != null) ...[
              const SizedBox(height: 6),
              Text(parseError!,
                  style: const TextStyle(color: KColors.red, fontSize: 12)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: parsing ? null : onParseAndAdd,
                  icon: parsing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Parse & Add to Inbox'),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Load from file',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: KColors.textDim),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: filePathCtrl,
                    decoration: const InputDecoration(
                      hintText: '/path/to/notes.org  or  notes.md  or  tasks.txt',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: parsing ? null : onLoadFile,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('Load'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _InboxQueue
// ---------------------------------------------------------------------------

class _InboxQueue extends StatefulWidget {
  final String projectId;
  final AppDatabase db;

  const _InboxQueue({required this.projectId, required this.db});

  @override
  State<_InboxQueue> createState() => _InboxQueueState();
}

class _InboxQueueState extends State<_InboxQueue> {
  int _focusedIndex = 0;
  late FocusNode _focusNode;
  List<InboxItem> _items = [];

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_items.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _focusedIndex = min(_focusedIndex + 1, _items.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _focusedIndex = max(_focusedIndex - 1, 0));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyY) {
      final item = _items[_focusedIndex];
      if (item.status == 'unprocessed') {
        _openReviewForItem(item);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      final item = _items[_focusedIndex];
      if (item.status == 'unprocessed') {
        _rejectItem(item);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openReviewForItem(InboxItem item) {
    Map<String, dynamic> parsedData = {};
    try {
      if (item.linkedItemType != null && item.linkedItemType!.isNotEmpty) {
        final decoded = jsonDecode(item.linkedItemType!);
        if (decoded is Map<String, dynamic>) parsedData = decoded;
      }
    } catch (_) {}
    final parsedType = item.tags ?? 'note';
    showDialog(
      context: context,
      builder: (_) => _ReviewDialog(
        item: item,
        parsedType: parsedType,
        parsedData: parsedData,
        db: widget.db,
        projectId: widget.projectId,
        onAccepted: () => _markAccepted(item),
      ),
    );
  }

  Future<void> _rejectItem(InboxItem item) async {
    await widget.db.inboxDao.upsertInboxItem(
      InboxItemsCompanion(
        id: Value(item.id),
        projectId: Value(item.projectId),
        content: Value(item.content),
        source: Value(item.source),
        status: const Value('rejected'),
        tags: Value(item.tags),
        linkedItemId: Value(item.linkedItemId),
        linkedItemType: Value(item.linkedItemType),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _markAccepted(InboxItem item) async {
    await widget.db.inboxDao.upsertInboxItem(
      InboxItemsCompanion(
        id: Value(item.id),
        projectId: Value(item.projectId),
        content: Value(item.content),
        source: Value(item.source),
        status: const Value('accepted'),
        tags: Value(item.tags),
        linkedItemId: Value(item.linkedItemId),
        linkedItemType: Value(item.linkedItemType),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Inbox Queue',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 8),
            StreamBuilder<List<InboxItem>>(
              stream: widget.db.inboxDao.watchUnprocessedForProject(widget.projectId),
              builder: (_, snap) {
                final count = snap.data?.length ?? 0;
                if (count == 0) return const SizedBox.shrink();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: KColors.amber.withAlpha(40),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: KColors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Keyboard hints row
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _KeyHint('↑↓', 'navigate'),
              const SizedBox(width: 12),
              _KeyHint('Y', 'accept'),
              const SizedBox(width: 12),
              _KeyHint('N', 'reject'),
              const Spacer(),
              const Text('Click list to enable shortcuts', style: TextStyle(color: KColors.textMuted, fontSize: 10)),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              child: StreamBuilder<List<InboxItem>>(
                stream: widget.db.inboxDao.watchInboxForProject(widget.projectId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  _items = snap.data!;
                  if (_items.isEmpty) {
                    return const Center(
                      child: Text(
                        'Inbox is empty.',
                        style: TextStyle(color: KColors.textDim),
                      ),
                    );
                  }
                  if (_focusedIndex >= _items.length) {
                    _focusedIndex = _items.length - 1;
                  }
                  return ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) => _InboxItemCard(
                      item: _items[i],
                      db: widget.db,
                      projectId: widget.projectId,
                      isActive: i == _focusedIndex && _focusNode.hasFocus,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _InboxItemCard
// ---------------------------------------------------------------------------

class _InboxItemCard extends StatelessWidget {
  final InboxItem item;
  final AppDatabase db;
  final String projectId;
  final bool isActive;

  const _InboxItemCard({
    required this.item,
    required this.db,
    required this.projectId,
    this.isActive = false,
  });

  /// Decode the parsedData stored in linkedItemType column (we use it for JSON).
  Map<String, dynamic> get _parsedData {
    try {
      if (item.linkedItemType != null && item.linkedItemType!.isNotEmpty) {
        final decoded = jsonDecode(item.linkedItemType!);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return {};
  }

  String get _parsedType => item.tags ?? 'note';

  Future<void> _reject(BuildContext context) async {
    await db.inboxDao.upsertInboxItem(
      InboxItemsCompanion(
        id: Value(item.id),
        projectId: Value(item.projectId),
        content: Value(item.content),
        source: Value(item.source),
        status: const Value('rejected'),
        tags: Value(item.tags),
        linkedItemId: Value(item.linkedItemId),
        linkedItemType: Value(item.linkedItemType),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _markAccepted(BuildContext context) async {
    await db.inboxDao.upsertInboxItem(
      InboxItemsCompanion(
        id: Value(item.id),
        projectId: Value(item.projectId),
        content: Value(item.content),
        source: Value(item.source),
        status: const Value('accepted'),
        tags: Value(item.tags),
        linkedItemId: Value(item.linkedItemId),
        linkedItemType: Value(item.linkedItemType),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  void _openReviewDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _ReviewDialog(
        item: item,
        parsedType: _parsedType,
        parsedData: _parsedData,
        db: db,
        projectId: projectId,
        onAccepted: () => _markAccepted(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProcessed =
        item.status == 'accepted' || item.status == 'rejected';
    final typeColor = _typeColor(_parsedType);

    final card = Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: typeColor.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: typeColor.withAlpha(100)),
              ),
              child: Text(
                _parsedType.toUpperCase(),
                style: TextStyle(
                  color: typeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.content.length > 120
                        ? '${item.content.substring(0, 120)}...'
                        : item.content,
                    style: TextStyle(
                      fontSize: 13,
                      color: isProcessed
                          ? KColors.textDim
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SourceBadge(source: item.source),
                      const SizedBox(width: 8),
                      StatusChip(status: item.status),
                      const Spacer(),
                      Text(
                        item.createdAt.toLocal().toString().substring(0, 16),
                        style: const TextStyle(
                          color: KColors.textDim,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Action buttons — only for unprocessed
            if (!isProcessed) ...[
              _ActionButton(
                icon: Icons.check,
                color: KColors.phosphor,
                tooltip: 'Accept',
                onPressed: () => _openReviewDialog(context),
              ),
              const SizedBox(width: 4),
              _ActionButton(
                icon: Icons.close,
                color: KColors.red,
                tooltip: 'Reject',
                onPressed: () => _reject(context),
              ),
              const SizedBox(width: 4),
              _ActionButton(
                icon: Icons.edit_outlined,
                color: KColors.blue,
                tooltip: 'Edit / Modify',
                onPressed: () => _openReviewDialog(context),
              ),
            ] else
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (val) {
                  if (val == 'delete') {
                    db.inboxDao.deleteInboxItem(item.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
        ),
      ),
    );
    if (isActive) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: KColors.amber.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: card,
      );
    }
    return card;
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'risk':
        return KColors.red;
      case 'decision':
        return KColors.blue;
      case 'action':
      case 'todo':
        return KColors.blue;
      case 'context':
        return KColors.phosphor;
      case 'dependency':
        return KColors.amber;
      default:
        return KColors.textDim;
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ReviewDialog — accept / edit dialog
// ---------------------------------------------------------------------------

class _ReviewDialog extends StatefulWidget {
  final InboxItem item;
  final String parsedType;
  final Map<String, dynamic> parsedData;
  final AppDatabase db;
  final String projectId;
  final Future<void> Function() onAccepted;

  const _ReviewDialog({
    required this.item,
    required this.parsedType,
    required this.parsedData,
    required this.db,
    required this.projectId,
    required this.onAccepted,
  });

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final GlobalKey<FormState> _formKey;

  // Common fields
  late TextEditingController _descCtrl;

  // Risk fields
  late String _likelihood;
  late String _impact;
  late TextEditingController _mitigationCtrl;
  late String _riskStatus;

  // Action/todo fields
  late TextEditingController _ownerCtrl;
  String? _dueDate;
  late String _actionStatus;
  late String _priority;

  // Decision fields
  late TextEditingController _decisionMakerCtrl;
  String? _decisionDueDate;
  late String _decisionStatus;

  // Note/context fields
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;
  late String _entryType;

  // Dependency fields
  late String _dependencyType;
  late TextEditingController _depOwnerCtrl;
  String? _depDueDate;

  bool _saving = false;

  Map<String, dynamic> get d => widget.parsedData;

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<FormState>();

    _descCtrl = TextEditingController(text: d['description'] as String? ?? widget.item.content);

    // Risk
    _likelihood = d['likelihood'] as String? ?? 'medium';
    _impact = d['impact'] as String? ?? 'medium';
    _mitigationCtrl = TextEditingController(text: d['mitigation'] as String? ?? '');
    _riskStatus = d['status'] as String? ?? 'open';

    // Action
    _ownerCtrl = TextEditingController(text: d['owner'] as String? ?? '');
    _dueDate = d['due_date'] as String?;
    _actionStatus = d['status'] as String? ?? 'open';
    _priority = d['priority'] as String? ?? 'medium';

    // Decision
    _decisionMakerCtrl = TextEditingController(text: d['decision_maker'] as String? ?? '');
    _decisionDueDate = d['due_date'] as String?;
    _decisionStatus = d['status'] as String? ?? 'pending';

    // Note/context
    _titleCtrl = TextEditingController(text: d['title'] as String? ?? widget.item.content.split('\n').first);
    _bodyCtrl = TextEditingController(text: d['body'] as String? ?? widget.item.content);
    _entryType = d['entry_type'] as String? ?? 'observation';

    // Dependency
    _dependencyType = d['dependency_type'] as String? ?? 'inbound';
    _depOwnerCtrl = TextEditingController(text: d['owner'] as String? ?? '');
    _depDueDate = d['due_date'] as String?;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _mitigationCtrl.dispose();
    _ownerCtrl.dispose();
    _decisionMakerCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _depOwnerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _saving = true);

    try {
      await _acceptItem();
      await widget.onAccepted();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _acceptItem() async {
    final id = const Uuid().v4();
    final type = widget.parsedType;

    if (type == 'risk') {
      await widget.db.raidDao.insertRisk(RisksCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        description: Value(_descCtrl.text.trim()),
        likelihood: Value(_likelihood),
        impact: Value(_impact),
        mitigation: Value(_mitigationCtrl.text.trim().isEmpty
            ? null
            : _mitigationCtrl.text.trim()),
        status: Value(_riskStatus),
        source: const Value('inbox'),
        sourceNote: Value(widget.item.id),
      ));
    } else if (type == 'action' || type == 'todo') {
      await widget.db.actionsDao.insertAction(ProjectActionsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        description: Value(_descCtrl.text.trim()),
        owner: Value(_ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
        dueDate: Value(_dueDate),
        status: Value(_actionStatus),
        priority: Value(_priority),
        source: const Value('inbox'),
        sourceNote: Value(widget.item.id),
      ));
    } else if (type == 'decision') {
      await widget.db.decisionsDao.insertDecision(DecisionsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        description: Value(_descCtrl.text.trim()),
        status: Value(_decisionStatus),
        decisionMaker: Value(_decisionMakerCtrl.text.trim().isEmpty
            ? null
            : _decisionMakerCtrl.text.trim()),
        dueDate: Value(_decisionDueDate),
        source: const Value('inbox'),
        sourceNote: Value(widget.item.id),
      ));
    } else if (type == 'dependency') {
      await widget.db.raidDao.insertDependency(ProgramDependenciesCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        description: Value(_descCtrl.text.trim()),
        dependencyType: Value(_dependencyType),
        owner: Value(_depOwnerCtrl.text.trim().isEmpty ? null : _depOwnerCtrl.text.trim()),
        dueDate: Value(_depDueDate),
        status: const Value('open'),
        source: const Value('inbox'),
        sourceNote: Value(widget.item.id),
      ));
    } else {
      // note, context, or anything else → ContextEntry
      await widget.db.contextDao.insertEntry(ContextEntriesCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        title: Value(_titleCtrl.text.trim().isEmpty ? widget.item.content.split('\n').first : _titleCtrl.text.trim()),
        content: Value(_bodyCtrl.text.trim().isEmpty ? widget.item.content : _bodyCtrl.text.trim()),
        entryType: Value(_entryType),
        source: const Value('inbox'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.parsedType;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: KColors.phosphor, size: 20),
          const SizedBox(width: 8),
          Text('Review & Accept — ${_typeLabel(type)}'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source info
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: KColors.surface2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      SourceBadge(source: widget.item.source),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.item.content.length > 80
                              ? '${widget.item.content.substring(0, 80)}...'
                              : widget.item.content,
                          style: const TextStyle(
                              fontSize: 11, color: KColors.textDim),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Type-specific form
                if (type == 'risk') ..._buildRiskFields(),
                if (type == 'action' || type == 'todo') ..._buildActionFields(),
                if (type == 'decision') ..._buildDecisionFields(),
                if (type == 'dependency') ..._buildDependencyFields(),
                if (type == 'note' || type == 'context' || type == 'document') ..._buildNoteFields(),
                if (!const ['risk', 'action', 'todo', 'decision', 'dependency', 'note', 'context', 'document'].contains(type))
                  ..._buildNoteFields(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 16),
          label: const Text('Accept & Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: KColors.phosphor,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRiskFields() => [
        TextFormField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Description *'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        DropdownField(
          label: 'Likelihood',
          value: _likelihood,
          items: const ['low', 'medium', 'high'],
          onChanged: (v) => setState(() => _likelihood = v!),
        ),
        const SizedBox(height: 12),
        DropdownField(
          label: 'Impact',
          value: _impact,
          items: const ['low', 'medium', 'high'],
          onChanged: (v) => setState(() => _impact = v!),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _mitigationCtrl,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Mitigation'),
        ),
        const SizedBox(height: 12),
        DropdownField(
          label: 'Status',
          value: _riskStatus,
          items: const ['open', 'mitigated', 'closed'],
          onChanged: (v) => setState(() => _riskStatus = v!),
        ),
      ];

  List<Widget> _buildActionFields() => [
        TextFormField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Description *'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _ownerCtrl,
          decoration: const InputDecoration(labelText: 'Owner'),
        ),
        const SizedBox(height: 12),
        DatePickerField(
          label: 'Due Date',
          isoValue: _dueDate,
          onChanged: (v) => setState(() => _dueDate = v),
        ),
        const SizedBox(height: 12),
        DropdownField(
          label: 'Priority',
          value: _priority,
          items: const ['low', 'medium', 'high'],
          onChanged: (v) => setState(() => _priority = v!),
        ),
        const SizedBox(height: 12),
        DropdownField(
          label: 'Status',
          value: _actionStatus,
          items: const ['open', 'in_progress', 'done', 'cancelled'],
          onChanged: (v) => setState(() => _actionStatus = v!),
        ),
      ];

  List<Widget> _buildDecisionFields() => [
        TextFormField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Description *'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _decisionMakerCtrl,
          decoration: const InputDecoration(labelText: 'Decision Maker'),
        ),
        const SizedBox(height: 12),
        DatePickerField(
          label: 'Due Date',
          isoValue: _decisionDueDate,
          onChanged: (v) => setState(() => _decisionDueDate = v),
        ),
        const SizedBox(height: 12),
        DropdownField(
          label: 'Status',
          value: _decisionStatus,
          items: const ['pending', 'decided', 'deferred', 'cancelled'],
          onChanged: (v) => setState(() => _decisionStatus = v!),
        ),
      ];

  List<Widget> _buildNoteFields() => [
        TextFormField(
          controller: _titleCtrl,
          decoration: const InputDecoration(labelText: 'Title *'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _bodyCtrl,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Body'),
        ),
        const SizedBox(height: 12),
        DropdownField(
          label: 'Entry Type',
          value: _entryType,
          items: const [
            'observation',
            'meeting_note',
            'decision',
            'context',
            'background',
            'other',
          ],
          onChanged: (v) => setState(() => _entryType = v!),
        ),
      ];

  List<Widget> _buildDependencyFields() => [
        TextFormField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Description *'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        DropdownField(
          label: 'Dependency Type',
          value: _dependencyType,
          items: const ['inbound', 'outbound'],
          onChanged: (v) => setState(() => _dependencyType = v!),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _depOwnerCtrl,
          decoration: const InputDecoration(labelText: 'Owner'),
        ),
        const SizedBox(height: 12),
        DatePickerField(
          label: 'Due Date',
          isoValue: _depDueDate,
          onChanged: (v) => setState(() => _depDueDate = v),
        ),
      ];

  String _typeLabel(String type) {
    switch (type) {
      case 'risk':
        return 'Risk';
      case 'action':
        return 'Action';
      case 'todo':
        return 'Todo / Action';
      case 'decision':
        return 'Decision';
      case 'dependency':
        return 'Dependency';
      case 'context':
        return 'Context';
      default:
        return 'Note';
    }
  }
}

// ---------------------------------------------------------------------------
// _KeyHint
// ---------------------------------------------------------------------------

class _KeyHint extends StatelessWidget {
  final String keyLabel;
  final String hint;
  const _KeyHint(this.keyLabel, this.hint);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: KColors.border2),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(keyLabel, style: const TextStyle(color: KColors.textDim, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 4),
        Text(hint, style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
      ],
    );
  }
}
