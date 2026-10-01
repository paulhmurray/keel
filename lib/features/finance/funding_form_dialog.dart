import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/person_picker_field.dart';
import 'finance_form.dart' show financeActor;

/// Add or edit a funding approval — money the programme has been given.
class FundingFormDialog extends StatefulWidget {
  final AppDatabase db;
  final String programmeId;
  final FundingApproval? existing;
  const FundingFormDialog(
      {super.key, required this.db, required this.programmeId, this.existing});

  @override
  State<FundingFormDialog> createState() => _FundingFormDialogState();
}

class _FundingFormDialogState extends State<FundingFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _approverCtrl;
  late final TextEditingController _notesCtrl;
  late String _currency;
  String? _approvedOn;
  String? _decisionId;
  List<Decision> _decisions = const [];
  List<Person> _persons = const [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _amountCtrl = TextEditingController(
        text: e == null ? '' : Money.formatMinorPlain(e.amountMinor));
    _approverCtrl = TextEditingController(text: e?.approvedBy ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _currency = e?.currency ?? 'AUD';
    _approvedOn = e?.approvedOn;
    _decisionId = e?.decisionId;
    _load();
  }

  Future<void> _load() async {
    final d = await widget.db.decisionsDao.getDecisionsForProject(widget.programmeId);
    final p = await widget.db.peopleDao.getPersonsForProject(widget.programmeId);
    if (mounted) {
      setState(() {
        _decisions = d.where((x) => x.sourceProjectId == null).toList();
        _persons = p;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _approverCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final minor = Money.parseToMinor(_amountCtrl.text)!;
    await widget.db.financeDao.upsertFunding(
      id: widget.existing?.id ?? const Uuid().v4(),
      programmeId: widget.programmeId,
      name: _nameCtrl.text.trim(),
      amountMinor: minor,
      currency: _currency,
      approvedBy: _approverCtrl.text.trim().isEmpty ? null : _approverCtrl.text.trim(),
      approvedOn: _approvedOn,
      decisionId: _decisionId,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      changedBy: financeActor(context),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Text(widget.existing == null ? 'Add funding' : 'Edit funding',
          style: const TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(
                  labelText: 'Name *', hintText: 'e.g. FY27 business case, Tranche 2 top-up', isDense: true),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _amountCtrl,
                  style: const TextStyle(color: KColors.text, fontSize: 13, fontFamily: 'monospace'),
                  decoration: const InputDecoration(labelText: 'Amount *', isDense: true),
                  validator: (v) {
                    final m = Money.parseToMinor(v ?? '');
                    return m == null || m <= 0 ? 'Enter a positive amount' : null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _currency,
                  dropdownColor: KColors.surface2,
                  style: const TextStyle(color: KColors.text, fontSize: 13),
                  decoration: const InputDecoration(labelText: 'Currency', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'AUD', child: Text('AUD')),
                    DropdownMenuItem(value: 'NZD', child: Text('NZD')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? 'AUD'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: PersonPickerField(
                  controller: _approverCtrl,
                  label: 'Approved by',
                  persons: _persons,
                  db: widget.db,
                  projectId: widget.programmeId,
                  onPersonCreated: _load,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DatePickerField(
                  label: 'Approved on',
                  isoValue: _approvedOn,
                  onChanged: (v) => setState(() => _approvedOn = v),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _decisionId,
              dropdownColor: KColors.surface2,
              isExpanded: true,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Decision (optional)', isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('—')),
                for (final d in _decisions)
                  DropdownMenuItem<String?>(
                      value: d.id,
                      child: Text('${d.ref ?? ''}  ${d.description}',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _decisionId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Notes', isDense: true),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: Text(widget.existing == null ? 'Add' : 'Save')),
      ],
    );
  }
}
