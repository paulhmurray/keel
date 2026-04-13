import 'dart:convert';
import 'package:flutter/material.dart';
import '../../shared/theme/keel_colors.dart';

class ChecklistWidget extends StatefulWidget {
  /// JSON string: [{"label": "...", "checked": false}, ...]
  final String? checklistJson;
  final ValueChanged<String> onChanged;

  const ChecklistWidget({
    super.key,
    required this.checklistJson,
    required this.onChanged,
  });

  @override
  State<ChecklistWidget> createState() => _ChecklistWidgetState();
}

class _ChecklistWidgetState extends State<ChecklistWidget> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = _parse(widget.checklistJson);
  }

  @override
  void didUpdateWidget(ChecklistWidget old) {
    super.didUpdateWidget(old);
    if (old.checklistJson != widget.checklistJson) {
      _items = _parse(widget.checklistJson);
    }
  }

  static List<Map<String, dynamic>> _parse(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final raw = jsonDecode(json) as List<dynamic>;
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _toggle(int index) {
    setState(() => _items[index]['checked'] = !(_items[index]['checked'] as bool));
    widget.onChanged(jsonEncode(_items));
  }

  void _addItem() {
    setState(() => _items.add({'label': '', 'checked': false}));
    widget.onChanged(jsonEncode(_items));
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
    widget.onChanged(jsonEncode(_items));
  }

  void _updateLabel(int index, String value) {
    _items[index]['label'] = value;
    widget.onChanged(jsonEncode(_items));
  }

  int get _checkedCount => _items.where((i) => i['checked'] == true).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.checklist_outlined, size: 12, color: KColors.textDim),
            const SizedBox(width: 5),
            Text(
              'CHECKLIST · $_checkedCount/${_items.length}',
              style: const TextStyle(
                color: KColors.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ..._items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          final checked = item['checked'] == true;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _toggle(i),
                  child: Icon(
                    checked
                        ? Icons.check_box_outlined
                        : Icons.check_box_outline_blank,
                    size: 16,
                    color: checked ? KColors.phosphor : KColors.textDim,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(
                        text: item['label'] as String? ?? '')
                      ..selection = TextSelection.collapsed(
                          offset:
                              (item['label'] as String? ?? '').length),
                    style: TextStyle(
                      color: checked ? KColors.textMuted : KColors.text,
                      fontSize: 12,
                      decoration:
                          checked ? TextDecoration.lineThrough : null,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Checklist item…',
                      hintStyle:
                          TextStyle(color: KColors.textMuted, fontSize: 12),
                    ),
                    onChanged: (v) => _updateLabel(i, v),
                  ),
                ),
                GestureDetector(
                  onTap: () => _removeItem(i),
                  child: const Icon(Icons.close, size: 12, color: KColors.textMuted),
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add, size: 12, color: KColors.textDim),
          label: const Text(
            'Add item',
            style: TextStyle(color: KColors.textDim, fontSize: 11),
          ),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}
