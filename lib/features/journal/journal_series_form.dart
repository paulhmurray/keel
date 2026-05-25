import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';

/// Create / edit a journal series (recurring meeting / tag).
class JournalSeriesFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final JournalSeries? series;

  const JournalSeriesFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.series,
  });

  @override
  State<JournalSeriesFormDialog> createState() =>
      _JournalSeriesFormDialogState();
}

class _JournalSeriesFormDialogState extends State<JournalSeriesFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  String _cadenceHint = 'weekly';
  String? _color;

  static const _cadenceOptions = [
    'none',
    'daily',
    'weekly',
    'fortnightly',
    'monthly',
    'quarterly',
    'ad hoc',
  ];

  static const _colourSwatches = [
    '#3B82F6', // blue
    '#22C55E', // green
    '#F97316', // orange
    '#EAB308', // yellow
    '#A855F7', // purple
    '#EC4899', // pink
    '#14B8A6', // teal
    '#6B7280', // grey
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.series;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _descCtrl = TextEditingController(text: s?.description ?? '');
    _cadenceHint = s?.cadenceHint ?? 'weekly';
    _color = s?.color;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final id = widget.series?.id ?? const Uuid().v4();
    final now = DateTime.now();
    await widget.db.journalSeriesDao.upsert(JournalSeriesDefsCompanion(
      id: Value(id),
      projectId: Value(widget.projectId),
      name: Value(_nameCtrl.text.trim()),
      description: Value(
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
      cadenceHint: Value(_cadenceHint == 'none' ? null : _cadenceHint),
      color: Value(_color),
      sortOrder: Value(widget.series?.sortOrder ?? 0),
      createdAt: widget.series == null ? Value(now) : const Value.absent(),
      updatedAt: Value(now),
    ));
    if (!mounted) return;
    final saved = await widget.db.journalSeriesDao.getById(id);
    if (mounted) Navigator.of(context).pop(saved);
  }

  Future<void> _delete() async {
    final s = widget.series;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete series?'),
        content: Text(
          'Remove "${s.name}"? Journal entries tagged with it will be kept '
          '(they\'ll just lose the series tag).',
          style: const TextStyle(color: KColors.textDim, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.db.journalSeriesDao.deleteSeries(s.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.series != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Series' : 'New Series'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g. Daily Standup, Weekly PMO, 1:1 with Sarah',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownField(
                label: 'Cadence (informational)',
                value: _cadenceHint,
                items: _cadenceOptions,
                onChanged: (v) => setState(() => _cadenceHint = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              const SizedBox(height: 12),
              const Text('COLOUR',
                  style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ColourSwatch(
                    hex: null,
                    selected: _color == null,
                    onTap: () => setState(() => _color = null),
                  ),
                  for (final hex in _colourSwatches)
                    _ColourSwatch(
                      hex: hex,
                      selected: _color == hex,
                      onTap: () => setState(() => _color = hex),
                    ),
                ],
              ),
              if (isEdit) ...[
                const SizedBox(height: 18),
                const Divider(color: KColors.border, height: 1),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: KColors.red,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Delete this series',
                        style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
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
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

class _ColourSwatch extends StatelessWidget {
  final String? hex;
  final bool selected;
  final VoidCallback onTap;

  const _ColourSwatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  Color? _parse() {
    if (hex == null) return null;
    var s = hex!.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    return Color(int.parse(s, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final c = _parse();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: c ?? KColors.surface2,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : KColors.border2,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: c == null
            ? const Icon(Icons.block, size: 12, color: KColors.textMuted)
            : null,
      ),
    );
  }
}
