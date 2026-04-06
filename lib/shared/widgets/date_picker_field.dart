import 'package:flutter/material.dart';
import '../utils/date_utils.dart' as du;

/// A form field that shows and accepts dates in DD-MM-YYYY format,
/// but stores/returns values in YYYY-MM-DD (ISO) format for the DB.
///
/// [isoValue] — initial value as YYYY-MM-DD (or null/empty).
/// [onChanged] — called with new value as YYYY-MM-DD whenever the date changes.
class DatePickerField extends StatefulWidget {
  final String? isoValue;
  final ValueChanged<String?> onChanged;
  final String label;
  final bool required;

  const DatePickerField({
    super.key,
    required this.label,
    required this.onChanged,
    this.isoValue,
    this.required = false,
  });

  @override
  State<DatePickerField> createState() => _DatePickerFieldState();
}

class _DatePickerFieldState extends State<DatePickerField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: du.formatDate(widget.isoValue));
  }

  @override
  void didUpdateWidget(DatePickerField old) {
    super.didUpdateWidget(old);
    if (old.isoValue != widget.isoValue) {
      final display = du.formatDate(widget.isoValue);
      if (_ctrl.text != display) {
        _ctrl.text = display;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final initial = du.parseIsoDate(widget.isoValue) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final iso = du.toIsoDate(picked);
      _ctrl.text = du.toDisplayDate(picked);
      widget.onChanged(iso);
    }
  }

  void _onTextChanged(String value) {
    // Allow manual typing — parse on the way out
    widget.onChanged(du.parseDisplayDate(value));
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'DD-MM-YYYY',
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          onPressed: _pickDate,
          tooltip: 'Pick date',
        ),
      ),
      onChanged: _onTextChanged,
      validator: widget.required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }
}
