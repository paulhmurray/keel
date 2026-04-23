import 'package:flutter/material.dart';
import '../../core/journal/journal_parser.dart';
import '../../shared/theme/keel_colors.dart';

class _EditField {
  final String key;
  final String label;
  final TextEditingController ctrl;
  _EditField(this.key, this.label, String initial)
      : ctrl = TextEditingController(text: initial);
}

class JournalDeltaItemWidget extends StatefulWidget {
  final DetectedDelta delta;
  final bool isActive;
  final bool isEditing;
  final VoidCallback onConfirm;
  final VoidCallback onIgnore;
  final VoidCallback onEdit;
  final VoidCallback onCancelEdit;

  const JournalDeltaItemWidget({
    super.key,
    required this.delta,
    required this.isActive,
    this.isEditing = false,
    required this.onConfirm,
    required this.onIgnore,
    required this.onEdit,
    required this.onCancelEdit,
  });

  @override
  State<JournalDeltaItemWidget> createState() => _JournalDeltaItemWidgetState();
}

class _JournalDeltaItemWidgetState extends State<JournalDeltaItemWidget> {
  late TextEditingController _descCtrl;
  late FocusNode _descFocus;
  late DeltaType _editType;
  List<_EditField> _fields = [];

  @override
  void initState() {
    super.initState();
    _descFocus = FocusNode();
    _editType = widget.delta.type;
    _initControllers();
  }

  @override
  void didUpdateWidget(JournalDeltaItemWidget old) {
    super.didUpdateWidget(old);
    if (!old.isEditing && widget.isEditing) {
      _editType = widget.delta.type;
      _rebuildFields(_editType);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _descFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _descFocus.dispose();
    _descCtrl.dispose();
    for (final f in _fields) {
      f.ctrl.dispose();
    }
    super.dispose();
  }

  void _initControllers() {
    final ef = widget.delta.editFields;
    _descCtrl = TextEditingController(
        text: ef['description'] ?? widget.delta.title);
    _fields = _buildFieldsForType(_editType, ef);
  }

  List<_EditField> _buildFieldsForType(
      DeltaType type, Map<String, String?> ef) {
    switch (type) {
      case DeltaType.action:
        return [
          _EditField('owner', 'Owner', ef['owner'] ?? ''),
          _EditField('dueDate', 'Due date', ef['dueDate'] ?? ''),
        ];
      case DeltaType.decision:
        return [
          _EditField('decisionMaker', 'Decision-maker',
              ef['decisionMaker'] ?? ''),
        ];
      case DeltaType.risk:
        return [
          _EditField('likelihood', 'Likelihood', ef['likelihood'] ?? ''),
          _EditField('impact', 'Impact', ef['impact'] ?? ''),
        ];
      case DeltaType.issue:
        return [
          _EditField('owner', 'Owner', ef['owner'] ?? ''),
          _EditField('priority', 'Priority', ef['priority'] ?? ''),
        ];
      case DeltaType.dependency:
        return [
          _EditField('owner', 'Owner', ef['owner'] ?? ''),
        ];
      case DeltaType.timelineChange:
        return [
          _EditField('item', 'Item', ef['item'] ?? ''),
          _EditField('previousDate', 'Was', ef['previousDate'] ?? ''),
          _EditField('newDate', 'Now', ef['newDate'] ?? ''),
        ];
    }
  }

  void _rebuildFields(DeltaType newType) {
    final oldFields = List<_EditField>.from(_fields);
    _fields = _buildFieldsForType(newType, widget.delta.editFields);
    // Defer disposal — old controllers may still be attached to TextFields
    // in the current frame; disposing them immediately causes errors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final f in oldFields) {
        f.ctrl.dispose();
      }
    });
  }

  void _changeType(DeltaType newType) {
    if (newType == _editType) return;
    setState(() {
      _rebuildFields(newType);
      _editType = newType;
    });
  }

  void _saveEdit() {
    widget.delta.type = _editType;
    final desc = _descCtrl.text.trim();
    if (desc.isNotEmpty) {
      widget.delta.editFields['description'] = desc;
    }
    for (final f in _fields) {
      final v = f.ctrl.text.trim();
      widget.delta.editFields[f.key] = v.isEmpty ? null : v;
    }
    widget.onConfirm();
  }

  Color _colorForType(DeltaType t) {
    switch (t) {
      case DeltaType.decision: return KColors.blue;
      case DeltaType.action: return KColors.phosphor;
      case DeltaType.risk: return KColors.amber;
      case DeltaType.issue: return KColors.red;
      case DeltaType.dependency: return KColors.blue;
      case DeltaType.timelineChange: return KColors.amber;
    }
  }

  Color _bgForType(DeltaType t) {
    switch (t) {
      case DeltaType.decision: return KColors.blueDim;
      case DeltaType.action: return KColors.phosDim;
      case DeltaType.risk: return KColors.amberDim;
      case DeltaType.issue: return KColors.redDim;
      case DeltaType.dependency: return KColors.blueDim;
      case DeltaType.timelineChange: return KColors.amberDim;
    }
  }

  Color get _typeColor => _colorForType(widget.delta.type);
  Color get _typeBg => _bgForType(widget.delta.type);

  @override
  Widget build(BuildContext context) {
    final delta = widget.delta;
    final isConfirmed = delta.confirmed;
    final isIgnored = delta.ignored;
    final isActive = widget.isActive;
    final isEditing = widget.isEditing && isActive && !isConfirmed && !isIgnored;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isIgnored
            ? KColors.surface
            : isConfirmed
                ? KColors.phosDim
                : isActive
                    ? KColors.surface2
                    : KColors.surface,
        border: Border.all(
          color: isEditing
              ? KColors.amber.withValues(alpha: 0.6)
              : isConfirmed
                  ? KColors.phosphor.withValues(alpha: 0.4)
                  : isActive
                      ? _typeColor.withValues(alpha: 0.4)
                      : KColors.border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type badge row
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _typeBg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(delta.typeIcon,
                          style:
                              TextStyle(color: _typeColor, fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        delta.typeLabel.toUpperCase(),
                        style: TextStyle(
                          color: _typeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.08,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (isEditing)
                  const Text(
                    'EDITING',
                    style: TextStyle(
                      color: KColors.amber,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                    ),
                  )
                else if (isConfirmed)
                  const Icon(Icons.check_circle,
                      size: 14, color: KColors.phosphor)
                else if (isIgnored)
                  const Icon(Icons.cancel_outlined,
                      size: 14, color: KColors.textMuted),
              ],
            ),
            const SizedBox(height: 8),

            if (isEditing) ...[
              // Type selector
              _TypeSelector(
                selected: _editType,
                onChanged: _changeType,
                colorForType: _colorForType,
                bgForType: _bgForType,
              ),
              const SizedBox(height: 10),
              // Description + type-specific fields
              _EditTextField(
                label: 'Description',
                controller: _descCtrl,
                focusNode: _descFocus,
                maxLines: 3,
              ),
              for (final f in _fields) ...[
                const SizedBox(height: 6),
                _EditTextField(label: f.label, controller: f.ctrl),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _ActionBtn(
                    label: 'Save',
                    color: KColors.phosphor,
                    onTap: _saveEdit,
                  ),
                  const SizedBox(width: 8),
                  _ActionBtn(
                    label: 'Cancel',
                    color: KColors.textDim,
                    onTap: widget.onCancelEdit,
                  ),
                ],
              ),
            ] else ...[
              // Title display
              Text(
                delta.title,
                style: TextStyle(
                  color: isIgnored ? KColors.textDim : KColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  decoration:
                      isIgnored ? TextDecoration.lineThrough : null,
                ),
              ),
              // Fields display
              if (!isIgnored) ...[
                const SizedBox(height: 6),
                ..._buildFieldRows(),
              ],
              // Action buttons
              if (!isConfirmed && !isIgnored && isActive) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ActionBtn(
                      label: 'Y  Confirm',
                      color: KColors.phosphor,
                      onTap: widget.onConfirm,
                    ),
                    const SizedBox(width: 8),
                    _ActionBtn(
                      label: 'E  Edit',
                      color: KColors.amber,
                      onTap: widget.onEdit,
                    ),
                    const SizedBox(width: 8),
                    _ActionBtn(
                      label: 'N  Ignore',
                      color: KColors.textDim,
                      onTap: widget.onIgnore,
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFieldRows() {
    final rows = <Widget>[];
    final f = widget.delta.editFields;
    void addRow(String label, String? value) {
      if (value == null || value.isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Text(
              '$label: ',
              style:
                  const TextStyle(color: KColors.textDim, fontSize: 11),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(color: KColors.text, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ));
    }

    switch (widget.delta.type) {
      case DeltaType.action:
        addRow('Owner', f['owner']);
        addRow('Due', f['dueDate']);
        break;
      case DeltaType.decision:
        addRow('Decision-maker', f['decisionMaker']);
        break;
      case DeltaType.risk:
        addRow('Likelihood', f['likelihood']);
        addRow('Impact', f['impact']);
        break;
      case DeltaType.issue:
        addRow('Owner', f['owner']);
        addRow('Priority', f['priority']);
        break;
      case DeltaType.dependency:
        addRow('Owner', f['owner']);
        break;
      case DeltaType.timelineChange:
        addRow('Item', f['item']);
        if (f['previousDate'] != null) addRow('Was', f['previousDate']);
        if (f['newDate'] != null) addRow('Now', f['newDate']);
        break;
    }
    return rows;
  }
}

// ---------------------------------------------------------------------------
// Edit text field
// ---------------------------------------------------------------------------

class _EditTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final int maxLines;

  const _EditTextField({
    required this.label,
    required this.controller,
    this.focusNode,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: KColors.textDim, fontSize: 10),
        ),
        const SizedBox(height: 3),
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: maxLines,
          style: const TextStyle(color: KColors.text, fontSize: 11),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide: const BorderSide(color: KColors.border2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(3),
              borderSide: const BorderSide(color: KColors.amber),
            ),
            filled: true,
            fillColor: KColors.bg,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Action button
// ---------------------------------------------------------------------------

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.05,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Type selector
// ---------------------------------------------------------------------------

class _TypeSelector extends StatelessWidget {
  final DeltaType selected;
  final void Function(DeltaType) onChanged;
  final Color Function(DeltaType) colorForType;
  final Color Function(DeltaType) bgForType;

  const _TypeSelector({
    required this.selected,
    required this.onChanged,
    required this.colorForType,
    required this.bgForType,
  });

  static const _allTypes = [
    DeltaType.action,
    DeltaType.decision,
    DeltaType.risk,
    DeltaType.issue,
    DeltaType.dependency,
    DeltaType.timelineChange,
  ];

  static String _labelFor(DeltaType t) {
    switch (t) {
      case DeltaType.action: return 'Action';
      case DeltaType.decision: return 'Decision';
      case DeltaType.risk: return 'Risk';
      case DeltaType.issue: return 'Issue';
      case DeltaType.dependency: return 'Dep.';
      case DeltaType.timelineChange: return 'Timeline';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Type',
            style: TextStyle(color: KColors.textDim, fontSize: 10)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: _allTypes.map((t) {
            final isSelected = t == selected;
            final color = colorForType(t);
            final bg = bgForType(t);
            return InkWell(
              onTap: () => onChanged(t),
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected ? bg : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? color.withValues(alpha: 0.7)
                        : KColors.border2,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _labelFor(t),
                  style: TextStyle(
                    color: isSelected ? color : KColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.05,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
