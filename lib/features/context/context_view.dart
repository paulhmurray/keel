import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../core/inbox/document_processor.dart';
import '../../core/llm/claude_client.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/source_badge.dart';

// ---------------------------------------------------------------------------
// Entry type colour mapping
// ---------------------------------------------------------------------------

Color _entryTypeColor(String type) {
  switch (type.toLowerCase()) {
    case 'observation':
      return KColors.phosphor;
    case 'note':
      return KColors.blue;
    case 'meeting-note':
      return KColors.textDim;
    case 'insight':
      return KColors.amber;
    case 'process':
      return KColors.phosphor;
    case 'rule':
      return KColors.red;
    case 'structure':
      return KColors.amber;
    case 'relationship':
      return KColors.amber;
    default:
      return KColors.textDim;
  }
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class ContextView extends StatefulWidget {
  const ContextView({super.key});

  @override
  State<ContextView> createState() => _ContextViewState();
}

class _ContextViewState extends State<ContextView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project.'));
    }
    final db = context.read<AppDatabase>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              const Icon(Icons.library_books,
                  color: KColors.amber, size: 22),
              const SizedBox(width: 10),
              Text('Context',
                  style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: KColors.border)),
          ),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Entries'),
              Tab(text: 'Documents'),
            ],
            indicatorColor: KColors.amber,
            labelColor: KColors.amber,
            unselectedLabelColor: KColors.textDim,
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _EntriesTab(projectId: projectId, db: db),
              _DocumentsTab(projectId: projectId, db: db),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Entries Tab
// ---------------------------------------------------------------------------

class _EntriesTab extends StatefulWidget {
  final String projectId;
  final AppDatabase db;

  const _EntriesTab({required this.projectId, required this.db});

  @override
  State<_EntriesTab> createState() => _EntriesTabState();
}

class _EntriesTabState extends State<_EntriesTab> {
  final _quickObsCtrl = TextEditingController();

  @override
  void dispose() {
    _quickObsCtrl.dispose();
    super.dispose();
  }

  Future<void> _captureObservation() async {
    final text = _quickObsCtrl.text.trim();
    if (text.isEmpty) return;
    await widget.db.contextDao.insertEntry(
      ContextEntriesCompanion(
        id: Value(const Uuid().v4()),
        projectId: Value(widget.projectId),
        title: Value(text.length > 80 ? '${text.substring(0, 80)}…' : text),
        content: Value(text),
        entryType: const Value('observation'),
        source: const Value('manual'),
      ),
    );
    _quickObsCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Quick observation bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickObsCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Capture observation…',
                    prefixIcon: Icon(Icons.visibility_outlined,
                        size: 18, color: KColors.phosphor),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (_) => _captureObservation(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _captureObservation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColors.phosphor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                child: const Text('Capture', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _EntryFormDialog(
                      projectId: widget.projectId, db: widget.db),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Entry'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<ContextEntry>>(
              stream:
                  widget.db.contextDao.watchEntriesForProject(widget.projectId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'No context entries yet.\nCapture an observation or add an entry.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: KColors.textDim),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final e = items[i];
                    return _EntryCard(
                      entry: e,
                      db: widget.db,
                      projectId: widget.projectId,
                    );
                  },
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
// Entry Card
// ---------------------------------------------------------------------------

class _EntryCard extends StatelessWidget {
  final ContextEntry entry;
  final AppDatabase db;
  final String projectId;

  const _EntryCard(
      {required this.entry, required this.db, required this.projectId});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final typeColor = _entryTypeColor(e.entryType);
    final tags = e.tags != null && e.tags!.isNotEmpty
        ? e.tags!.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _EntryFormDialog(
            projectId: projectId,
            db: db,
            entry: e,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      e.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Entry type badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: typeColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: typeColor.withAlpha(100)),
                    ),
                    child: Text(
                      e.entryType,
                      style: TextStyle(
                          color: typeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    ],
                    onSelected: (val) {
                      if (val == 'delete') {
                        db.contextDao.deleteEntry(e.id);
                      } else if (val == 'edit') {
                        showDialog(
                          context: context,
                          builder: (_) => _EntryFormDialog(
                            projectId: projectId,
                            db: db,
                            entry: e,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Body preview
              Text(
                e.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: KColors.textDim, fontSize: 12),
              ),
              const SizedBox(height: 8),
              // Footer row: source badge + tags + date
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SourceBadge(source: e.source),
                  ...tags.map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: KColors.surface2,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: KColors.border),
                      ),
                      child: Text(
                        '#$tag',
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 11),
                      ),
                    ),
                  ),
                  Text(
                    du.toDisplayDate(e.createdAt),
                    style: const TextStyle(
                        color: KColors.textDim, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry Form Dialog
// ---------------------------------------------------------------------------

class _EntryFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ContextEntry? entry; // null = new entry

  const _EntryFormDialog(
      {required this.projectId, required this.db, this.entry});

  @override
  State<_EntryFormDialog> createState() => _EntryFormDialogState();
}

class _EntryFormDialogState extends State<_EntryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _tagsCtrl;
  late String _type;
  late String _source;

  static const _types = [
    'observation',
    'note',
    'meeting-note',
    'insight',
    'process',
    'rule',
    'structure',
    'relationship',
  ];
  static const _sources = ['manual', 'meeting', 'email', 'document'];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _contentCtrl = TextEditingController(text: e?.content ?? '');
    _tagsCtrl = TextEditingController(text: e?.tags ?? '');
    _type = e?.entryType ?? 'observation';
    _source = e?.source ?? 'manual';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final tags = _tagsCtrl.text.trim().isEmpty ? null : _tagsCtrl.text.trim();

    if (widget.entry == null) {
      await widget.db.contextDao.insertEntry(
        ContextEntriesCompanion(
          id: Value(const Uuid().v4()),
          projectId: Value(widget.projectId),
          title: Value(_titleCtrl.text.trim()),
          content: Value(_contentCtrl.text.trim()),
          entryType: Value(_type),
          source: Value(_source),
          tags: Value(tags),
        ),
      );
    } else {
      await widget.db.contextDao.updateEntry(
        ContextEntriesCompanion(
          id: Value(widget.entry!.id),
          projectId: Value(widget.projectId),
          title: Value(_titleCtrl.text.trim()),
          content: Value(_contentCtrl.text.trim()),
          entryType: Value(_type),
          source: Value(_source),
          tags: Value(tags),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.entry == null ? 'New Context Entry' : 'Edit Context Entry'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contentCtrl,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Content *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tagsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'comma-separated, e.g. risk, milestone, vendor',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownField(
                        label: 'Type',
                        value: _type,
                        items: _types,
                        onChanged: (v) => setState(() => _type = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownField(
                        label: 'Source',
                        value: _source,
                        items: _sources,
                        onChanged: (v) => setState(() => _source = v!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(widget.entry == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Documents Tab
// ---------------------------------------------------------------------------

class _DocumentsTab extends StatelessWidget {
  final String projectId;
  final AppDatabase db;

  const _DocumentsTab({required this.projectId, required this.db});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) =>
                      _DocumentUploadDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Upload Document'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<Document>>(
              stream: db.contextDao.watchDocumentsForProject(projectId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'No documents yet.\nUpload a document to extract text and generate a summary.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: KColors.textDim),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final d = items[i];
                    return _DocumentCard(
                        document: d, db: db, projectId: projectId);
                  },
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
// Document Card
// ---------------------------------------------------------------------------

class _DocumentCard extends StatelessWidget {
  final Document document;
  final AppDatabase db;
  final String projectId;

  const _DocumentCard(
      {required this.document, required this.db, required this.projectId});

  String? get _summary {
    final tags = document.tags;
    if (tags == null || tags.isEmpty) return null;
    try {
      final decoded = jsonDecode(tags);
      if (decoded is Map<String, dynamic>) {
        return decoded['summary'] as String?;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = document;
    final summary = _summary;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog(
          context: context,
          builder: (_) =>
              _DocumentDetailDialog(document: d, db: db, projectId: projectId),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.description_outlined,
                  color: KColors.blue, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        if (d.documentType != null &&
                            d.documentType!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: KColors.surface2,
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: KColors.border),
                            ),
                            child: Text(
                              d.documentType!,
                              style: const TextStyle(
                                  color: KColors.textDim, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (summary != null && summary.isNotEmpty)
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 12),
                      )
                    else if (d.content != null && d.content!.isNotEmpty)
                      Text(
                        d.content!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 12),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Added ${du.toDisplayDate(d.createdAt)}',
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 11),
                        ),
                        const SizedBox(width: 8),
                        if (summary != null)
                          const _StatusChip(
                              label: 'Summarised', color: KColors.phosphor),
                        if (d.content != null &&
                            d.content!.isNotEmpty &&
                            summary == null)
                          const _StatusChip(
                              label: 'Text extracted',
                              color: KColors.blue),
                        if (d.content == null || d.content!.isEmpty)
                          const _StatusChip(
                              label: 'No content', color: KColors.textDim),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                onSelected: (val) {
                  if (val == 'delete') db.contextDao.deleteDocument(d.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Document Upload Dialog
// ---------------------------------------------------------------------------

class _DocumentUploadDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;

  const _DocumentUploadDialog(
      {required this.projectId, required this.db});

  @override
  State<_DocumentUploadDialog> createState() => _DocumentUploadDialogState();
}

class _DocumentUploadDialogState extends State<_DocumentUploadDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _pasteCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();

  bool _useFilePath = true;
  bool _extracting = false;
  String? _extractedText;
  String? _extractError;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _pathCtrl.dispose();
    _pasteCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    const typeGroup = XTypeGroup(
      label: 'Documents',
      extensions: ['txt', 'md', 'pdf', 'docx'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    _pathCtrl.text = file.path;
    await _extract();
  }

  Future<void> _extract() async {
    final path = _pathCtrl.text.trim();
    if (path.isEmpty) return;

    setState(() {
      _extracting = true;
      _extractedText = null;
      _extractError = null;
    });

    try {
      final ext = path.contains('.')
          ? path.split('.').last.toLowerCase()
          : 'txt';
      const processor = DocumentProcessor();
      final text = await processor.extractText(path, ext);
      setState(() {
        _extractedText = text;
        _extracting = false;
        // Auto-fill title from filename if blank
        if (_titleCtrl.text.trim().isEmpty) {
          final parts = path.replaceAll('\\', '/').split('/');
          final filename = parts.last;
          final nameWithoutExt = filename.contains('.')
              ? filename.substring(0, filename.lastIndexOf('.'))
              : filename;
          _titleCtrl.text = nameWithoutExt;
        }
        // Auto-fill document type from extension
        if (_typeCtrl.text.trim().isEmpty) {
          final ext2 = path.contains('.')
              ? path.split('.').last.toUpperCase()
              : '';
          _typeCtrl.text = ext2;
        }
      });
    } catch (e) {
      setState(() {
        _extractError = e.toString();
        _extracting = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final content = _useFilePath
        ? (_extractedText ?? '')
        : _pasteCtrl.text.trim();

    await widget.db.contextDao.insertDocument(
      DocumentsCompanion(
        id: Value(const Uuid().v4()),
        projectId: Value(widget.projectId),
        title: Value(_titleCtrl.text.trim()),
        documentType: Value(
            _typeCtrl.text.trim().isEmpty ? null : _typeCtrl.text.trim()),
        content: Value(content.isEmpty ? null : content),
        filePath: Value(
            _pathCtrl.text.trim().isEmpty ? null : _pathCtrl.text.trim()),
      ),
    );

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Document'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _typeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Document Type',
                    hintText: 'e.g. PID, RAID, Minutes, TXT, PDF',
                  ),
                ),
                const SizedBox(height: 16),
                // Toggle between file path and paste
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('File Path'),
                      selected: _useFilePath,
                      onSelected: (v) => setState(() => _useFilePath = true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Paste Text'),
                      selected: !_useFilePath,
                      onSelected: (v) => setState(() => _useFilePath = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_useFilePath) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _pathCtrl.text.isEmpty
                            ? const Text(
                                'No file selected',
                                style: TextStyle(
                                    color: KColors.textDim, fontSize: 13),
                              )
                            : Text(
                                _pathCtrl.text.replaceAll('\\', '/').split('/').last,
                                style: const TextStyle(
                                    color: KColors.text, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _extracting ? null : _pickFile,
                        icon: const Icon(Icons.folder_open_outlined, size: 16),
                        label: const Text('Browse…'),
                      ),
                      if (_pathCtrl.text.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _extracting ? null : _extract,
                          child: _extracting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Re-extract'),
                        ),
                      ],
                    ],
                  ),
                  if (_extractError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Error: $_extractError',
                      style: const TextStyle(
                          color: KColors.red, fontSize: 12),
                    ),
                  ],
                  if (_extractedText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: KColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: KColors.phosphor.withAlpha(80)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_outline,
                                  color: KColors.phosphor, size: 14),
                              const SizedBox(width: 6),
                              const Text(
                                'Text extracted',
                                style: TextStyle(
                                    color: KColors.phosphor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text(
                                '${_extractedText!.length} characters',
                                style: const TextStyle(
                                    color: KColors.textDim, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _extractedText!.length > 200
                                ? '${_extractedText!.substring(0, 200)}…'
                                : _extractedText!,
                            style: const TextStyle(
                                color: KColors.textDim, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  TextFormField(
                    controller: _pasteCtrl,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Paste document text here',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Document Detail Dialog
// ---------------------------------------------------------------------------

class _DocumentDetailDialog extends StatefulWidget {
  final Document document;
  final AppDatabase db;
  final String projectId;

  const _DocumentDetailDialog(
      {required this.document, required this.db, required this.projectId});

  @override
  State<_DocumentDetailDialog> createState() => _DocumentDetailDialogState();
}

class _DocumentDetailDialogState extends State<_DocumentDetailDialog> {
  bool _generatingSummary = false;
  bool _sendingToInbox = false;
  String? _summaryError;

  Future<void> _generateSummary(BuildContext ctx) async {
    final settings = ctx.read<SettingsProvider>();
    if (!settings.hasApiKey) {
      setState(() =>
          _summaryError = 'No API key configured. Go to Settings → LLM Settings.');
      return;
    }

    final content = widget.document.content;
    if (content == null || content.isEmpty) {
      setState(
          () => _summaryError = 'No extracted text available to summarise.');
      return;
    }

    setState(() {
      _generatingSummary = true;
      _summaryError = null;
    });

    try {
      final client = ClaudeClient(
        apiKey: settings.settings.claudeApiKey,
        model: settings.settings.claudeModel,
      );

      final prompt =
          'You are a TPM assistant. Summarise this document in 3-5 bullet points, '
          'focusing on decisions, risks, actions, and key information relevant to '
          'programme management.\n\nDocument content:\n$content';

      final summary = await client.complete(
        systemPrompt:
            'You are an expert TPM assistant. Be concise and action-oriented.',
        userMessage: prompt,
        maxTokens: 800,
      );

      // Store summary in tags as JSON
      final existingTags = widget.document.tags;
      Map<String, dynamic> tagsMap = {};
      if (existingTags != null && existingTags.isNotEmpty) {
        try {
          final decoded = jsonDecode(existingTags);
          if (decoded is Map<String, dynamic>) tagsMap = decoded;
        } catch (_) {}
      }
      tagsMap['summary'] = summary;

      await widget.db.contextDao.updateDocument(
        DocumentsCompanion(
          id: Value(widget.document.id),
          projectId: Value(widget.document.projectId),
          title: Value(widget.document.title),
          content: Value(widget.document.content),
          filePath: Value(widget.document.filePath),
          documentType: Value(widget.document.documentType),
          tags: Value(jsonEncode(tagsMap)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (mounted) setState(() => _generatingSummary = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _generatingSummary = false;
          _summaryError = e.toString();
        });
      }
    }
  }

  Future<void> _sendToInbox(BuildContext ctx) async {
    final content = widget.document.content;
    if (content == null || content.isEmpty) return;

    setState(() => _sendingToInbox = true);

    // Capture messenger before async gap
    final messenger = ScaffoldMessenger.of(ctx);

    try {
      await widget.db.inboxDao.insertInboxItem(
        InboxItemsCompanion(
          id: Value(const Uuid().v4()),
          projectId: Value(widget.projectId),
          content: Value(
              'Document: ${widget.document.title}\n\n${content.length > 1000 ? '${content.substring(0, 1000)}…' : content}'),
          source: const Value('document'),
          status: const Value('unprocessed'),
        ),
      );
      if (mounted) {
        setState(() => _sendingToInbox = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Sent to Inbox for processing.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _sendingToInbox = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the document for live updates (summary being added)
    return StreamBuilder<List<Document>>(
      stream: widget.db.contextDao.watchDocumentsForProject(widget.projectId),
      builder: (ctx, snap) {
        final doc = snap.hasData
            ? snap.data!.where((d) => d.id == widget.document.id).firstOrNull
            : widget.document;

        if (doc == null) {
          Navigator.of(context).pop();
          return const SizedBox.shrink();
        }

        String? liveSummary;
        final tags = doc.tags;
        if (tags != null && tags.isNotEmpty) {
          try {
            final decoded = jsonDecode(tags);
            if (decoded is Map<String, dynamic>) {
              liveSummary = decoded['summary'] as String?;
            }
          } catch (_) {}
        }

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.description_outlined,
                  color: KColors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(doc.title,
                      style: const TextStyle(fontSize: 16))),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Metadata
                  Row(
                    children: [
                      if (doc.documentType != null &&
                          doc.documentType!.isNotEmpty) ...[
                        _StatusChip(
                            label: doc.documentType!,
                            color: KColors.blue),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        'Added ${du.toDisplayDate(doc.createdAt)}',
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 12),
                      ),
                      if (doc.filePath != null &&
                          doc.filePath!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            doc.filePath!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: KColors.textDim, fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Summary section
                  Row(
                    children: [
                      const Text(
                        'Summary',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _generatingSummary
                            ? null
                            : () => _generateSummary(ctx),
                        icon: _generatingSummary
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.auto_awesome_outlined,
                                size: 14),
                        label: Text(
                          liveSummary != null
                              ? 'Regenerate Summary'
                              : 'Generate Summary',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (_summaryError != null) ...[
                    Text(
                      _summaryError!,
                      style: const TextStyle(
                          color: KColors.red, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (liveSummary != null && liveSummary.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: KColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: KColors.phosphor.withAlpha(80)),
                      ),
                      child: Text(
                        liveSummary,
                        style: const TextStyle(
                            fontSize: 13, color: KColors.text),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: KColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: KColors.border),
                      ),
                      child: const Text(
                        'No summary yet. Click "Generate Summary" to have Claude summarise this document.',
                        style: TextStyle(
                            color: KColors.textDim, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Extracted text section
                  const Text(
                    'Extracted Text',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (doc.content != null && doc.content!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 300),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: KColors.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: KColors.border),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          doc.content!,
                          style: const TextStyle(
                              color: KColors.textDim,
                              fontSize: 12,
                              fontFamily: 'monospace'),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: KColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: KColors.border),
                      ),
                      child: const Text(
                        'No extracted text available.',
                        style: TextStyle(
                            color: KColors.textDim, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              onPressed: (doc.content == null || doc.content!.isEmpty ||
                      _sendingToInbox)
                  ? null
                  : () => _sendToInbox(ctx),
              icon: _sendingToInbox
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.inbox_outlined, size: 14),
              label: const Text('Send to Inbox'),
            ),
          ],
        );
      },
    );
  }
}
