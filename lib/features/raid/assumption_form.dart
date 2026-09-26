import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/analytics/keel_events.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/raid/raid_conversion_service.dart';
import '../../core/raid/raid_lifecycle.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/detail_dialog.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/person_picker_field.dart';
import '../../shared/utils/date_utils.dart' as du;
import 'raid_convert_button.dart';
import '../journal/journal_source_link.dart';
import 'raid_links_section.dart';

class AssumptionFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Assumption? assumption;
  final bool startInViewMode;

  const AssumptionFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.assumption,
    this.startInViewMode = false,
  });

  @override
  State<AssumptionFormDialog> createState() => _AssumptionFormDialogState();
}

class _AssumptionFormDialogState extends State<AssumptionFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _descCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _sourceNoteCtrl;

  String _status = 'open';
  String _source = 'manual';
  List<Person> _persons = const [];

  late bool _isViewing;

  final _statuses = ['open', 'validated', 'invalidated', 'closed'];
  final _sources = [
    'manual', 'inbox', 'document', 'observation', 'meeting', 'journal'
  ];

  bool get _isEdit => widget.assumption != null;

  @override
  void initState() {
    super.initState();
    final a = widget.assumption;
    _descCtrl = TextEditingController(text: a?.description ?? '');
    _ownerCtrl = TextEditingController(text: a?.owner ?? '');
    _sourceNoteCtrl = TextEditingController(text: a?.sourceNote ?? '');
    _status = a?.status ?? 'open';
    _source = a?.source ?? 'manual';
    _isViewing = widget.startInViewMode && a != null;
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final list = await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = list);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _ownerCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final isNew = widget.assumption == null;
    String ref = widget.assumption?.ref ??
        _nextRef(await widget.db.raidDao.getAssumptionsForProject(widget.projectId));

    final id = widget.assumption?.id ?? const Uuid().v4();
    await widget.db.raidDao.upsertAssumption(
      AssumptionsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(_descCtrl.text.trim()),
        owner: Value(
            _ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
        status: Value(_status),
        closedAt: Value(nextClosedAt(
            kind: RaidKind.assumption,
            newStatus: _status,
            existing: widget.assumption?.closedAt)),
        source: Value(_source),
        sourceNote: Value(_sourceNoteCtrl.text.trim().isEmpty
            ? null
            : _sourceNoteCtrl.text.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (isNew && mounted) {
      context.analytics.track(
        KeelEvents.assumptionCreated,
        props: {KeelEventProps.source: 'assumption_form'},
      );
    }
    // Cascade to linked programmes; the service decides per link
    // (full detail vs escalated only) so no flag check here.
    if (mounted) {
      final fresh = await widget.db.raidDao.getAssumptionById(id);
      if (fresh != null && mounted) {
        await buildCascadeService(context).pushAssumption(fresh);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  String _nextRef(List<Assumption> existing) {
    final nums = existing
        .where((a) => a.ref != null && a.ref!.startsWith('A'))
        .map((a) => int.tryParse(a.ref!.substring(1)) ?? 0)
        .toList()
      ..sort();
    return 'A${(nums.isEmpty ? 0 : nums.last) + 1}';
  }

  static const _accent = KColors.violet;

  Widget _readView() {
    final a = widget.assumption!;
    return DetailDialog(
      accent: _accent,
      title: [
        if (a.ref != null) ...[DetailRefChip(a.ref!), const SizedBox(width: 10)],
        const Expanded(child: DetailTitle('Assumption')),
        Text(a.status.toUpperCase(),
            style: const TextStyle(
                color: _accent, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
      left: [
        DetailField('Description', a.description, large: true),
        Row(
          children: [
            Expanded(child: DetailField('Status', a.status)),
            if (a.owner != null && a.owner!.isNotEmpty)
              Expanded(child: DetailField('Owner', a.owner)),
          ],
        ),
        if (isTerminalStatus(RaidKind.assumption, a.status))
          DetailField(
              'Closed on',
              du.formatDate(a.closedAt ??
                  a.updatedAt.toIso8601String().substring(0, 10))),
        if (a.validatedBy != null && a.validatedBy!.isNotEmpty)
          DetailField(
              'Validated by',
              a.validatedAt != null
                  ? '${a.validatedBy} · ${du.formatDate(a.validatedAt!.toIso8601String())}'
                  : a.validatedBy),
      ],
      right: [
        Row(
          children: [
            Expanded(child: DetailField('Source', a.source)),
            if (a.sourceNote != null && a.sourceNote!.isNotEmpty)
              Expanded(child: DetailField('Source Note', a.sourceNote)),
          ],
        ),
        JournalSourceLink(
          db: widget.db,
          projectId: widget.projectId,
          itemId: a.id,
          itemText: a.description,
        ),
        DetailField(
            'Last updated', du.formatDate(a.updatedAt.toIso8601String())),
        RaidLinksSection(
          db: widget.db,
          projectId: widget.projectId,
          itemType: RaidKind.assumption,
          itemId: a.id,
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

  @override
  Widget build(BuildContext context) {
    if (_isViewing) return _readView();

    final isEdit = _isEdit;

    return DetailDialog(
      accent: _accent,
      formKey: _formKey,
      title: [
        if (widget.assumption?.ref != null) ...[
          DetailRefChip(widget.assumption!.ref!),
          const SizedBox(width: 10),
        ],
        Expanded(
            child: DetailTitle(isEdit ? 'Edit Assumption' : 'New Assumption')),
        if (isEdit)
          RaidConvertButton(
            db: widget.db,
            from: RaidKind.assumption,
            itemId: widget.assumption!.id,
            itemRef: widget.assumption!.ref,
            sourceProjectId: widget.assumption!.sourceProjectId,
          ),
      ],
      left: [
        TextFormField(
          controller: _descCtrl,
          autofocus: !isEdit,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(color: KColors.text, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Description *',
            hintText: 'What we are taking as true, and what it underpins',
            alignLabelWithHint: true,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownField(
                label: 'Status',
                value: _status,
                items: _statuses,
                onChanged: (v) => setState(() => _status = v!),
              ),
            ),
            const SizedBox(width: 12),
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
          ],
        ),
        const SizedBox(height: 12),
      ],
      right: [
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
            itemId: widget.assumption!.id,
            itemText: widget.assumption!.description,
          ),
          const DetailDivider(),
          RaidLinksSection(
            db: widget.db,
            projectId: widget.projectId,
            itemType: RaidKind.assumption,
            itemId: widget.assumption!.id,
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
