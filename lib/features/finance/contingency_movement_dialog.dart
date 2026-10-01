import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/finance/contingency_ledger.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';
import '../../shared/widgets/date_picker_field.dart';
import 'finance_form.dart' show financeActor;

/// Records one contingency movement: an initial allocation, a draw from
/// contingency, or a return to it. Draws and returns must name the
/// decision that authorised them — that is what keeps contingency in the
/// open. On save the project's allocation is re-sent down the link.
class ContingencyMovementDialog extends StatefulWidget {
  final AppDatabase db;
  final String programmeId;
  /// Preselect a kind ('allocate' | 'draw' | 'return').
  final String? initialKind;
  final String? initialProjectId;
  /// When opened from a decision, that decision is fixed.
  final String? decisionId;

  const ContingencyMovementDialog({
    super.key,
    required this.db,
    required this.programmeId,
    this.initialKind,
    this.initialProjectId,
    this.decisionId,
  });

  @override
  State<ContingencyMovementDialog> createState() =>
      _ContingencyMovementDialogState();
}

class _ContingencyMovementDialogState extends State<ContingencyMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _kind;
  String? _projectId;
  String? _decisionId;
  String _movedOn = _todayIso();
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  List<(String id, String name)> _projects = const [];
  List<Decision> _decisions = const [];
  bool _saving = false;

  static String _todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind ?? kMovementDraw;
    _projectId = widget.initialProjectId;
    _decisionId = widget.decisionId;
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final names = {for (final p in context.read<ProjectProvider>().projects) p.id: p.name};
    final links = await widget.db.programmeLinksDao.getLinksForEntity(widget.programmeId);
    final projects = <(String, String)>[
      for (final l in links)
        if (l.status == 'active' && l.partnerLocalId != null)
          (l.partnerLocalId!, names[l.partnerLocalId!] ?? l.partnerName ?? 'Linked project'),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final decisions = await widget.db.decisionsDao.getDecisionsForProject(widget.programmeId);
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _decisions = decisions.where((d) => d.sourceProjectId == null).toList()
        ..sort((a, b) => (b.ref ?? '').compareTo(a.ref ?? ''));
      _projectId ??= projects.length == 1 ? projects.first.$1 : null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final minor = Money.parseToMinor(_amountCtrl.text);
    if (minor == null || minor <= 0) return;
    setState(() => _saving = true);
    final actor = financeActor(context);
    try {
      await widget.db.financeDao.recordMovement(
        id: const Uuid().v4(),
        programmeId: widget.programmeId,
        kind: _kind,
        amountMinor: minor,
        linkedProjectId: _projectId!,
        decisionId: _decisionId,
        reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
        movedOn: _movedOn,
        changedBy: actor,
      );
      if (mounted) {
        await buildCascadeService(context)
            .pushAllocation(widget.programmeId, _projectId!);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsDecision = movementNeedsDecision(_kind);
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Text(movementLabel(_kind),
          style: const TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: kMovementAllocate, label: Text('Allocate')),
                ButtonSegment(value: kMovementDraw, label: Text('Draw')),
                ButtonSegment(value: kMovementReturn, label: Text('Return')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 6),
            Text(
              switch (_kind) {
                kMovementAllocate =>
                  'Carves part of the funding envelope out to a project. Stands on the funding approval; no decision needed.',
                kMovementDraw =>
                  'Moves money from the contingency pool to a project. Needs the decision that authorised it.',
                _ =>
                  'A project hands unspent money back to the pool. Needs the decision that authorised it.',
              },
              style: const TextStyle(color: KColors.textMuted, fontSize: 11, height: 1.35),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _projectId,
              dropdownColor: KColors.surface2,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Project *', isDense: true),
              items: [
                for (final p in _projects)
                  DropdownMenuItem(value: p.$1, child: Text(p.$2)),
              ],
              onChanged: (v) => setState(() => _projectId = v),
              validator: (v) => v == null ? 'Pick the project' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _amountCtrl,
                  autofocus: true,
                  style: const TextStyle(color: KColors.text, fontSize: 13, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                      labelText: 'Amount *', hintText: 'e.g. 250k or 1.2m', isDense: true),
                  validator: (v) {
                    final m = Money.parseToMinor(v ?? '');
                    return m == null || m <= 0 ? 'Enter a positive amount' : null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DatePickerField(
                  label: 'Date',
                  isoValue: _movedOn,
                  onChanged: (v) => setState(() => _movedOn = v ?? _todayIso()),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _decisionId,
              dropdownColor: KColors.surface2,
              isExpanded: true,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: InputDecoration(
                  labelText: needsDecision ? 'Authorising decision *' : 'Authorising decision',
                  isDense: true),
              items: [
                for (final d in _decisions)
                  DropdownMenuItem(
                    value: d.id,
                    child: Text('${d.ref ?? ''}  ${d.description}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: widget.decisionId != null
                  ? null
                  : (v) => setState(() => _decisionId = v),
              validator: (v) => needsDecision && (v == null || v.isEmpty)
                  ? 'A ${_kind == kMovementDraw ? 'draw' : 'return'} needs the decision behind it — record one in Decisions first'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reasonCtrl,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(
                  labelText: 'Reason', hintText: 'One line for the ledger', isDense: true),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Record'),
        ),
      ],
    );
  }
}
