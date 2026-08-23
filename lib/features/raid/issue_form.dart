import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/analytics/keel_events.dart';
import '../../core/database/database.dart';
import '../../core/raid/raid_conversion_service.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../../shared/widgets/person_picker_field.dart';
import 'raid_convert_button.dart';
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
  final _sources = ['manual', 'inbox', 'document', 'observation', 'meeting'];

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
    if (mounted) Navigator.of(context).pop();
  }

  Widget _readView() {
    final i = widget.issue!;
    return AlertDialog(
      title: Row(
        children: [
          if (i.ref != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KColors.amberDim,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(i.ref!,
                  style: const TextStyle(
                      color: KColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
          ],
          const Text('Issue'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (i.title != null && i.title!.isNotEmpty)
                _viewField('Title', i.title, large: true),
              _viewField('Description', i.description,
                  large: i.title == null || i.title!.isEmpty),
              if (i.impactStatement != null &&
                  i.impactStatement!.isNotEmpty)
                _viewField('Impact if unresolved', i.impactStatement),
              if (i.escalationRequired)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_upward,
                          size: 13, color: KColors.red),
                      const SizedBox(width: 6),
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
                ),
              Row(
                children: [
                  Expanded(child: _viewField('Priority', i.priority)),
                  Expanded(child: _viewField('Status', i.status)),
                ],
              ),
              Row(
                children: [
                  if (i.owner != null && i.owner!.isNotEmpty)
                    Expanded(child: _viewField('Owner', i.owner)),
                  if (i.dueDate != null)
                    Expanded(child: _viewField('Due Date', i.dueDate)),
                ],
              ),
              if (i.resolution != null && i.resolution!.isNotEmpty)
                _viewField('Resolution', i.resolution),
              Row(
                children: [
                  Expanded(child: _viewField('Source', i.source)),
                  if (i.sourceNote != null && i.sourceNote!.isNotEmpty)
                    Expanded(child: _viewField('Source Note', i.sourceNote)),
                ],
              ),
              _viewField('Last updated',
                  du.formatDate(i.updatedAt.toIso8601String())),
              RaidLinksSection(
                db: widget.db,
                projectId: widget.projectId,
                itemType: RaidKind.issue,
                itemId: i.id,
                readOnly: true,
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
          onPressed: () => setState(() => _isViewing = false),
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Edit'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isViewing) return _readView();

    final isEdit = widget.issue != null;

    return AlertDialog(
      title: Row(
        children: [
          Text(isEdit ? 'Edit Issue' : 'New Issue'),
          const Spacer(),
          if (isEdit)
            RaidConvertButton(
              db: widget.db,
              from: RaidKind.issue,
              itemId: widget.issue!.id,
              itemRef: widget.issue!.ref,
              sourceProjectId: widget.issue!.sourceProjectId,
            ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Short, scannable headline',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  hintText: 'What the issue is',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _impactCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Impact statement',
                  hintText:
                      'What happens to the project if this isn\'t resolved',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: _escalationRequired,
                      onChanged: (v) => setState(
                          () => _escalationRequired = v ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_upward,
                      size: 13, color: KColors.red),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _resolutionCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Resolution'),
              ),
              const SizedBox(height: 12),
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
                      decoration:
                          const InputDecoration(labelText: 'Source Note'),
                    ),
                  ),
                ],
              ),
              if (isEdit) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: RaidLinksSection(
                    db: widget.db,
                    projectId: widget.projectId,
                    itemType: RaidKind.issue,
                    itemId: widget.issue!.id,
                  ),
                ),
              ],
            ],
          ),
          ),
        ),
      ),
      actions: [
        if (widget.startInViewMode)
          TextButton(
            onPressed: () => setState(() => _isViewing = true),
            child: const Text('Cancel'),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

Widget _viewField(String label, String? value, {bool large = false}) {
  if (value == null || value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: KColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: KColors.text,
            fontSize: large ? 14 : 12,
            height: 1.55,
          ),
        ),
      ],
    ),
  );
}
