import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/person_picker_field.dart';

const kCurrencies = ['AUD', 'GBP', 'USD', 'EUR', 'NZD'];

/// The audit actor for finance mutations — the user's name from
/// settings, or null when unset (the DAO stores it nullable).
String? financeActor(BuildContext context) {
  final name = context.read<SettingsProvider>().settings.myName.trim();
  return name.isEmpty ? null : name;
}

/// Australian FY label for today (FY starts 1 July): Jul 2026 → FY27.
String defaultFyLabel() {
  final now = DateTime.now();
  final fyEndYear = now.month >= 7 ? now.year + 1 : now.year;
  return 'FY${fyEndYear % 100}';
}

/// Current calendar period label: 'YYYY-MM'.
String currentPeriodLabel() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

/// Create a budget, or edit a DRAFT budget's metadata.
class BudgetFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ProjectBudget? budget;

  const BudgetFormDialog(
      {super.key, required this.projectId, required this.db, this.budget});

  @override
  State<BudgetFormDialog> createState() => _BudgetFormDialogState();
}

class _BudgetFormDialogState extends State<BudgetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _fundingCtrl;
  late TextEditingController _notesCtrl;
  String _currency = 'AUD';

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    _nameCtrl = TextEditingController(text: b?.name ?? '');
    _fundingCtrl = TextEditingController(text: b?.fundingSource ?? '');
    _notesCtrl = TextEditingController(text: b?.notes ?? '');
    _currency = b?.currency ?? 'AUD';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fundingCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final actor = financeActor(context);
    final name = _nameCtrl.text.trim();
    final funding =
        _fundingCtrl.text.trim().isEmpty ? null : _fundingCtrl.text.trim();
    final notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    if (widget.budget == null) {
      await widget.db.financeDao.createBudget(
        projectId: widget.projectId,
        name: name,
        currency: _currency,
        fundingSource: funding,
        notes: notes,
        changedBy: actor,
      );
    } else {
      await widget.db.financeDao.updateDraftBudget(
        id: widget.budget!.id,
        name: name,
        currency: _currency,
        fundingSource: funding,
        notes: notes,
        changedBy: actor,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.budget != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Budget' : 'New Budget'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Name *',
                    hintText: 'e.g. Approved Business Case v2'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownField(
                      label: 'Currency',
                      value: _currency,
                      items: kCurrencies,
                      onChanged: (v) => setState(() => _currency = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _fundingCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Funding Source',
                          hintText: 'e.g. Capex pool'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
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
          child: Text(isEdit ? 'Save' : 'Create Draft'),
        ),
      ],
    );
  }
}

/// Approve a draft budget — supersedes the current approved budget.
class ApproveBudgetDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ProjectBudget budget;

  const ApproveBudgetDialog(
      {super.key,
      required this.projectId,
      required this.db,
      required this.budget});

  @override
  State<ApproveBudgetDialog> createState() => _ApproveBudgetDialogState();
}

class _ApproveBudgetDialogState extends State<ApproveBudgetDialog> {
  final _approverCtrl = TextEditingController();
  List<Person> _persons = [];

  @override
  void initState() {
    super.initState();
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final persons =
        await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = persons);
  }

  @override
  void dispose() {
    _approverCtrl.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    final approver = _approverCtrl.text.trim();
    await widget.db.financeDao.approveBudget(
      widget.budget.id,
      approvedBy: approver.isEmpty ? null : approver,
      changedBy: financeActor(context),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve Budget'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${widget.budget.name}" becomes the approved budget. '
              'Any currently approved budget is superseded (history kept). '
              'Approved budgets are read-only.',
              style: const TextStyle(color: KColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 16),
            PersonPickerField(
              controller: _approverCtrl,
              label: 'Approved By',
              persons: _persons,
              db: widget.db,
              projectId: widget.projectId,
              onPersonCreated: _loadPersons,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _approve,
          icon: const Icon(Icons.check, size: 14),
          label: const Text('Approve'),
        ),
      ],
    );
  }
}

/// Add or edit a budget line on a DRAFT budget.
class BudgetLineFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ProjectBudget budget;
  final List<CostCategory> categories;
  final List<TimelineWorkPackage> workPackages;
  final BudgetLine? line;

  /// Pre-selects fields when opened from a grid cell or category row.
  final String? initialCategoryId;
  final String? initialFinancialYear;
  final String? initialWorkstreamId;

  const BudgetLineFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    required this.budget,
    required this.categories,
    required this.workPackages,
    this.line,
    this.initialCategoryId,
    this.initialFinancialYear,
    this.initialWorkstreamId,
  });

  @override
  State<BudgetLineFormDialog> createState() => _BudgetLineFormDialogState();
}

class _BudgetLineFormDialogState extends State<BudgetLineFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountCtrl;
  late TextEditingController _fyCtrl;
  late TextEditingController _notesCtrl;
  String? _categoryId;
  String? _workstreamId;

  @override
  void initState() {
    super.initState();
    final l = widget.line;
    _amountCtrl = TextEditingController(
        text: l == null ? '' : Money.formatMinorPlain(l.amountMinor));
    _fyCtrl = TextEditingController(
        text: l?.financialYear ??
            widget.initialFinancialYear ??
            defaultFyLabel());
    _notesCtrl = TextEditingController(text: l?.notes ?? '');
    _categoryId = l?.costCategoryId ?? widget.initialCategoryId;
    _workstreamId = l?.workstreamId ?? widget.initialWorkstreamId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _fyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amountMinor = Money.parseToMinor(_amountCtrl.text)!;
    await widget.db.financeDao.upsertLine(
      id: widget.line?.id ?? const Uuid().v4(),
      projectId: widget.projectId,
      budgetId: widget.budget.id,
      costCategoryId: _categoryId!,
      workstreamId: _workstreamId,
      financialYear: _fyCtrl.text.trim(),
      amountMinor: amountMinor,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      changedBy: financeActor(context),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.line != null;
    final wpNames = {
      for (final wp in widget.workPackages) wp.id: wp.name,
    };
    return AlertDialog(
      title: Text(isEdit ? 'Edit Budget Line' : 'New Budget Line'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      decoration:
                          const InputDecoration(labelText: 'Category *'),
                      items: widget.categories
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _categoryId = v),
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _fyCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Financial Year *', hintText: 'FY27'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                autofocus: !isEdit,
                decoration: InputDecoration(
                  labelText: 'Amount (${widget.budget.currency}) *',
                  hintText: 'e.g. 120,000 or 120k',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  return Money.parseToMinor(v) == null
                      ? 'Not a valid amount'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue:
                    wpNames.containsKey(_workstreamId) ? _workstreamId : null,
                decoration: const InputDecoration(
                    labelText: 'Workstream (optional)'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('—')),
                  ...widget.workPackages.map((wp) => DropdownMenuItem<String?>(
                      value: wp.id, child: Text(wp.name))),
                ],
                onChanged: (v) => setState(() => _workstreamId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
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
          child: Text(isEdit ? 'Save' : 'Add Line'),
        ),
      ],
    );
  }
}
