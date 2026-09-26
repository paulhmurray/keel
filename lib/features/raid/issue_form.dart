import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/analytics/keel_events.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/llm/context_builder.dart';
import '../../core/llm/raid_assist_prompts.dart';
import '../../core/raid/raid_conversion_service.dart';
import '../../core/raid/raid_lifecycle.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/ai_assist_button.dart';
import '../../shared/widgets/detail_dialog.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../../shared/widgets/person_picker_field.dart';
import 'raid_convert_button.dart';
import '../journal/journal_source_link.dart';
import 'raid_links_section.dart';

class IssueFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Issue? issue;
  final bool startInViewMode;

  const IssueFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.issue,
    this.startInViewMode = false,
  });

  @override
  State<IssueFormDialog> createState() => _IssueFormDialogState();
}

class _IssueFormDialogState extends State<IssueFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _impactCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _resolutionCtrl;
  late TextEditingController _sourceNoteCtrl;
  String? _dueDate;

  String _priority = 'medium';
  String _status = 'open';
  String _source = 'manual';
  bool _escalationRequired = false;
  List<Person> _persons = const [];

  late bool _isViewing;

  final _priorities = ['low', 'medium', 'high', 'critical'];
  final _statuses = ['open', 'in progress', 'resolved', 'closed'];
  final _sources = [
    'manual', 'inbox', 'document', 'observation', 'meeting', 'journal'
  ];

  bool get _isEdit => widget.issue != null;

  @override
  void initState() {
    super.initState();
    final issue = widget.issue;
    _titleCtrl = TextEditingController(text: issue?.title ?? '');
    _descCtrl = TextEditingController(text: issue?.description ?? '');
    _impactCtrl =
        TextEditingController(text: issue?.impactStatement ?? '');
    _ownerCtrl = TextEditingController(text: issue?.owner ?? '');
    _resolutionCtrl = TextEditingController(text: issue?.resolution ?? '');
    _sourceNoteCtrl = TextEditingController(text: issue?.sourceNote ?? '');
    _dueDate = issue?.dueDate;
    _priority = issue?.priority ?? 'medium';
    _status = issue?.status ?? 'open';
    _source = issue?.source ?? 'manual';
    _escalationRequired = issue?.escalationRequired ?? false;
    _isViewing = widget.startInViewMode && issue != null;
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final list = await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = list);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _impactCtrl.dispose();
    _ownerCtrl.dispose();
    _resolutionCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  String _nextRef(List<Issue> existing) {
    final nums = existing
        .where((i) => i.ref != null && i.ref!.startsWith('I'))
        .map((i) => int.tryParse(i.ref!.substring(1)) ?? 0)
        .toList()
      ..sort();
    return 'I${(nums.isEmpty ? 0 : nums.last) + 1}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final isNew = widget.issue == null;
    final existing = await widget.db.raidDao.getIssuesForProject(widget.projectId);
    final String ref = widget.issue?.ref ?? _nextRef(existing);

    final id = widget.issue?.id ?? const Uuid().v4();
    await widget.db.raidDao.upsertIssue(
      IssuesCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        title: Value(
            _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim()),
        description: Value(_descCtrl.text.trim()),
        impactStatement: Value(_impactCtrl.text.trim().isEmpty
            ? null
            : _impactCtrl.text.trim()),
        escalationRequired: Value(_escalationRequired),
        owner: Value(
            _ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
        dueDate: Value(_dueDate),
        priority: Value(_priority),
        status: Value(_status),
        closedAt: Value(nextClosedAt(
            kind: RaidKind.issue,
            newStatus: _status,
            existing: widget.issue?.closedAt)),
        resolution: Value(_resolutionCtrl.text.trim().isEmpty
            ? null
            : _resolutionCtrl.text.trim()),
        source: Value(_source),
        sourceNote: Value(_sourceNoteCtrl.text.trim().isEmpty
            ? null
            : _sourceNoteCtrl.text.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (isNew && mounted) {
      context.analytics.track(
        KeelEvents.issueCreated,
        props: {KeelEventProps.source: 'issue_form'},
      );
    }
    // Cascade to linked programmes; the service decides per link
    // (full detail vs escalated only) so no flag check here.
    if (mounted) {
      final fresh = await widget.db.raidDao.getIssueById(id);
      if (fresh != null && mounted) {
        await buildCascadeService(context).pushIssue(fresh);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ── AI assist ──────────────────────────────────────────────────────────────

  Future<RaidAssistPrompt> _prompt(IssueAssistField field) async {
    final ctx =
        await ContextBuilder(widget.db).buildSystemPrompt(widget.projectId);
    return issueAssistPrompt(
      field: field,
      title: _titleCtrl.text,
      description: _descCtrl.text,
      priority: _priority,
      status: _status,
      impactStatement: _impactCtrl.text,
      resolution: _resolutionCtrl.text,
      owner: _ownerCtrl.text,
      dueDate: _dueDate,
      projectContext: ctx,
    );
  }

  Color get _accent => switch (_priority) {
        'critical' => KColors.red,
        'high' => KColors.amber,
        _ => KColors.violet,
      };

  Widget _escalationBanner() => const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Icon(Icons.arrow_upward, size: 13, color: KColors.red),
            SizedBox(width: 6),
            Text(
              'ESCALATION REQUIRED',
              style: TextStyle(
                color: KColors.red,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08,
              ),
            ),
          ],
        ),
      );

  // ── Read view ──────────────────────────────────────────────────────────────

  Widget _readView() {
    final i = widget.issue!;
    final hasTitle = i.title != null && i.title!.isNotEmpty;
    return DetailDialog(
      accent: _accent,
      title: [
        if (i.ref != null) ...[DetailRefChip(i.ref!), const SizedBox(width: 10)],
        const Expanded(child: DetailTitle('Issue')),
        Text(i.priority.toUpperCase(),
            style: TextStyle(
                color: _accent, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
      left: [
        if (hasTitle) DetailField('Title', i.title, large: true),
        DetailField('Description', i.description, large: !hasTitle),
        DetailField('Impact if unresolved', i.impactStatement),
        if (i.escalationRequired) _escalationBanner(),
        Row(
          children: [
            Expanded(child: DetailField('Priority', i.priority)),
            Expanded(child: DetailField('Status', i.status)),
          ],
        ),
        Row(
          children: [
            if (i.owner != null && i.owner!.isNotEmpty)
              Expanded(child: DetailField('Owner', i.owner)),
            if (i.dueDate != null)
              Expanded(child: DetailField('Due Date', du.formatDate(i.dueDate))),
            if (isTerminalStatus(RaidKind.issue, i.status))
              Expanded(
                  child: DetailField(
                      'Closed on',
                      du.formatDate(i.closedAt ??
                          i.updatedAt.toIso8601String().substring(0, 10)))),
          ],
        ),
      ],
      right: [
        DetailField('Resolution', i.resolution),
        Row(
          children: [
            Expanded(child: DetailField('Source', i.source)),
            if (i.sourceNote != null && i.sourceNote!.isNotEmpty)
              Expanded(child: DetailField('Source Note', i.sourceNote)),
          ],
        ),
        JournalSourceLink(
          db: widget.db,
          projectId: widget.projectId,
          itemId: i.id,
          itemText: i.title ?? i.description,
        ),
        DetailField(
            'Last updated', du.formatDate(i.updatedAt.toIso8601String())),
        RaidLinksSection(
          db: widget.db,
          projectId: widget.projectId,
          itemType: RaidKind.issue,
          itemId: i.id,
          readOnly: true,
        ),
      ],
      footer: [
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => setState(() => _isViewing = false),
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Edit', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── Edit view ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isViewing) return _readView();

    final isEdit = _isEdit;

    return DetailDialog(
      accent: _accent,
      formKey: _formKey,
      title: [
        if (widget.issue?.ref != null) ...[
          DetailRefChip(widget.issue!.ref!),
          const SizedBox(width: 10),
        ],
        Expanded(child: DetailTitle(isEdit ? 'Edit Issue' : 'New Issue')),
        if (isEdit)
          RaidConvertButton(
            db: widget.db,
            from: RaidKind.issue,
            itemId: widget.issue!.id,
            itemRef: widget.issue!.ref,
            sourceProjectId: widget.issue!.sourceProjectId,
          ),
      ],
      left: [
        TextFormField(
          controller: _titleCtrl,
          autofocus: !isEdit,
          style: const TextStyle(color: KColors.text, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'Short, scannable headline',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descCtrl,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Description *',
            hintText: 'What the issue is',
            alignLabelWithHint: true,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        AiAssistedLabel(
          label: 'Impact statement',
          target: _impactCtrl,
          tooltip: 'Draft what happens to the project if this isn’t resolved',
          buildPrompt: () => _prompt(IssueAssistField.impactStatement),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _impactCtrl,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'What happens to the project if this isn\'t resolved',
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: _escalationRequired,
                onChanged: (v) =>
                    setState(() => _escalationRequired = v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_upward, size: 13, color: KColors.red),
            const SizedBox(width: 5),
            const Expanded(
              child: Text(
                'Escalation required — needs a decision or action '
                'from above this project',
                style: TextStyle(color: KColors.text, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownField(
                label: 'Priority',
                value: _priority,
                items: _priorities,
                onChanged: (v) => setState(() => _priority = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownField(
                label: 'Status',
                value: _status,
                items: _statuses,
                onChanged: (v) => setState(() => _status = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      right: [
        Row(
          children: [
            Expanded(
              child: PersonPickerField(
                controller: _ownerCtrl,
                label: 'Owner',
                persons: _persons,
                db: widget.db,
                projectId: widget.projectId,
                onPersonCreated: _loadPersons,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DatePickerField(
                label: 'Due Date',
                isoValue: _dueDate,
                onChanged: (v) => setState(() => _dueDate = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AiAssistedLabel(
          label: 'Resolution',
          target: _resolutionCtrl,
          tooltip: 'Draft the steps to close this issue',
          buildPrompt: () => _prompt(IssueAssistField.resolution),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _resolutionCtrl,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'How this gets closed, and who needs to be involved',
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownField(
                label: 'Source',
                value: _source,
                items: _sources,
                onChanged: (v) => setState(() => _source = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _sourceNoteCtrl,
                decoration: const InputDecoration(labelText: 'Source Note'),
              ),
            ),
          ],
        ),
        if (isEdit) ...[
          const SizedBox(height: 12),
          JournalSourceLink(
            db: widget.db,
            projectId: widget.projectId,
            itemId: widget.issue!.id,
            itemText: widget.issue!.title ?? widget.issue!.description,
          ),
          const DetailDivider(),
          RaidLinksSection(
            db: widget.db,
            projectId: widget.projectId,
            itemType: RaidKind.issue,
            itemId: widget.issue!.id,
          ),
        ],
        const SizedBox(height: 12),
      ],
      footer: [
        const Spacer(),
        if (widget.startInViewMode)
          TextButton(
            onPressed: () => setState(() => _isViewing = true),
            child: const Text('Cancel',
                style: TextStyle(color: KColors.textDim, fontSize: 12)),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: KColors.textDim, fontSize: 12)),
          ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create',
              style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
