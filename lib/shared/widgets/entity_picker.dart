import 'package:flutter/material.dart';

import '../theme/keel_colors.dart';

/// Reusable picker for any "look it up; add it if it's missing" entity.
///
/// Two surfaces share the same lookup + add-new flow:
///   - [EntityPickerField] — inline autocomplete field for forms.
///   - [showEntityPicker]  — modal dialog for "assign to slot" use cases.
///
/// Concrete pickers (PersonPicker / RolePicker / SystemPicker / TermPicker)
/// build on these, plugging in their own item source, display, and
/// add-new dialog.

/// Optional pinned shortcut shown at the very top of the suggestion list.
/// Used by PersonPicker to surface "Me — [your name]".
class EntityPickerShortcut<T> {
  /// Label rendered as the shortcut's title.
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color textColor;

  /// Called when the user picks the shortcut. Must return the entity to set
  /// (or null to leave selection cleared).
  final Future<T?> Function() onSelected;

  /// Display string written to the text field when picked.
  final String displayString;

  /// Whether the shortcut should appear for the current query. Defaults to
  /// always shown.
  final bool Function(String query) showFor;

  EntityPickerShortcut({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.displayString,
    required this.onSelected,
    bool Function(String query)? showFor,
  }) : showFor = showFor ?? ((_) => true);
}

/// Inline autocomplete field — drop-in for forms.
class EntityPickerField<T> extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final List<T> items;
  final String Function(T) displayName;
  final String Function(T)? secondaryLine;
  final IconData itemIcon;
  final Color itemIconColor;

  /// Called when the user accepts the "Add new …" affordance.
  /// The returned entity (if any) is committed; otherwise selection is left
  /// unchanged.
  final Future<T?> Function(BuildContext context, String query)? onAddNew;

  /// Label suffix for the add-new row, e.g. 'as new person'.
  final String addNewSuffix;

  /// Called whenever a real entity is selected from the list. Receives null
  /// when the user accepts the add-new affordance but cancels its dialog.
  final ValueChanged<T?>? onSelected;

  /// Optional pinned shortcut row (e.g. "Me — Paul").
  final EntityPickerShortcut<T>? shortcut;

  /// Max items shown in the dropdown (excluding shortcut and add-new).
  final int maxItems;

  /// Optional text style for the typed-in input. When null, falls back
  /// to the field's compact default (fontSize 12). Callers wanting a
  /// roomier field (e.g. larger dialogs) can pass a bigger style.
  final TextStyle? textStyle;

  /// Optional label style override. When null, uses the compact default.
  final TextStyle? labelStyle;

  /// Optional content padding for the underlying TextFormField. Larger
  /// padding combined with a larger [textStyle] makes the field feel
  /// roomier without re-laying-out the dropdown.
  final EdgeInsetsGeometry? contentPadding;

  const EntityPickerField({
    super.key,
    required this.controller,
    required this.label,
    required this.items,
    required this.displayName,
    this.secondaryLine,
    this.itemIcon = Icons.circle_outlined,
    this.itemIconColor = KColors.textDim,
    this.onAddNew,
    this.addNewSuffix = '',
    this.onSelected,
    this.shortcut,
    this.maxItems = 6,
    this.textStyle,
    this.labelStyle,
    this.contentPadding,
  });

  @override
  State<EntityPickerField<T>> createState() => _EntityPickerFieldState<T>();
}

class _EntityPickerFieldState<T> extends State<EntityPickerField<T>> {
  static const _kAddSentinel = '\x00__add__';
  static const _kShortcutSentinel = '\x00__shortcut__';

  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  List<String> _buildOptions(String query) {
    final q = query.toLowerCase().trim();
    final out = <String>[];
    if (widget.shortcut != null && widget.shortcut!.showFor(query)) {
      out.add(_kShortcutSentinel);
    }
    final matches = widget.items
        .where((it) => widget.displayName(it).toLowerCase().contains(q))
        .map(widget.displayName)
        .take(widget.maxItems)
        .toList();
    out.addAll(matches);
    if (q.isNotEmpty && widget.onAddNew != null) {
      // Don't offer add-new when the query exactly matches an existing item.
      final exact = widget.items.any(
        (it) => widget.displayName(it).toLowerCase().trim() == q,
      );
      if (!exact) out.add(_kAddSentinel);
    }
    return out;
  }

  Future<void> _handleAddNew(String query) async {
    final result = await widget.onAddNew!.call(context, query);
    if (!mounted) return;
    if (result != null) {
      widget.controller.text = widget.displayName(result);
      widget.onSelected?.call(result);
    } else {
      widget.onSelected?.call(null);
    }
  }

  T? _findByDisplay(String value) {
    for (final it in widget.items) {
      if (widget.displayName(it) == value) return it;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (v) => _buildOptions(v.text),
      displayStringForOption: (opt) {
        if (opt == _kShortcutSentinel) {
          return widget.shortcut!.displayString;
        }
        if (opt == _kAddSentinel) return widget.controller.text;
        return opt;
      },
      fieldViewBuilder: (ctx, ctrl, focusNode, onSubmitted) => TextFormField(
        controller: ctrl,
        focusNode: focusNode,
        style: widget.textStyle ??
            const TextStyle(color: KColors.text, fontSize: 12),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: widget.labelStyle ??
              const TextStyle(color: KColors.textDim, fontSize: 11),
          border: const OutlineInputBorder(),
          isDense: widget.contentPadding == null,
          contentPadding: widget.contentPadding ??
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        onFieldSubmitted: (_) => onSubmitted(),
      ),
      optionsViewBuilder: (ctx, onSelected, options) {
        final query = widget.controller.text.trim();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: KColors.surface2,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: KColors.border2),
            ),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxHeight: 260, maxWidth: 320),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: options.map((opt) {
                  if (opt == _kShortcutSentinel) {
                    final s = widget.shortcut!;
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(s.icon, size: 14, color: s.iconColor),
                      title: Text(
                        s.label,
                        style: TextStyle(
                          color: s.textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () async {
                        final picked = await s.onSelected();
                        widget.controller.text = s.displayString;
                        onSelected(opt);
                        widget.onSelected?.call(picked);
                      },
                    );
                  }
                  if (opt == _kAddSentinel) {
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: const Icon(Icons.add_circle_outline,
                          size: 14, color: KColors.phosphor),
                      title: Text(
                        widget.addNewSuffix.isEmpty
                            ? 'Add "$query"'
                            : 'Add "$query" ${widget.addNewSuffix}',
                        style: const TextStyle(
                          color: KColors.phosphor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        onSelected(opt);
                        _handleAddNew(query);
                      },
                    );
                  }
                  final entity = _findByDisplay(opt);
                  final subtitle = entity != null
                      ? widget.secondaryLine?.call(entity)
                      : null;
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(widget.itemIcon,
                        size: 14, color: widget.itemIconColor),
                    title: Text(opt,
                        style: const TextStyle(
                            color: KColors.text, fontSize: 12)),
                    subtitle: subtitle != null && subtitle.isNotEmpty
                        ? Text(subtitle,
                            style: const TextStyle(
                                color: KColors.textMuted, fontSize: 10))
                        : null,
                    onTap: () => onSelected(opt),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
      onSelected: (opt) {
        if (opt == _kShortcutSentinel || opt == _kAddSentinel) return;
        widget.controller.text = opt;
        final entity = _findByDisplay(opt);
        if (entity != null) widget.onSelected?.call(entity);
      },
    );
  }
}

/// Modal "search and pick" dialog. Returns the picked entity, or null.
///
/// Used for slot-assignment flows like "assign someone to this stakeholder
/// role". Includes the same add-new affordance as the inline field.
Future<T?> showEntityPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) displayName,
  String Function(T)? secondaryLine,
  IconData itemIcon = Icons.circle_outlined,
  Color itemIconColor = KColors.textDim,
  String addNewLabel = 'Add new…',
  Future<T?> Function(BuildContext, String query)? onAddNew,
  String searchHint = 'Search…',
}) {
  return showDialog<T>(
    context: context,
    builder: (_) => _EntityPickerDialog<T>(
      title: title,
      items: items,
      displayName: displayName,
      secondaryLine: secondaryLine,
      itemIcon: itemIcon,
      itemIconColor: itemIconColor,
      addNewLabel: addNewLabel,
      onAddNew: onAddNew,
      searchHint: searchHint,
    ),
  );
}

class _EntityPickerDialog<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) displayName;
  final String Function(T)? secondaryLine;
  final IconData itemIcon;
  final Color itemIconColor;
  final String addNewLabel;
  final Future<T?> Function(BuildContext, String query)? onAddNew;
  final String searchHint;

  const _EntityPickerDialog({
    required this.title,
    required this.items,
    required this.displayName,
    required this.secondaryLine,
    required this.itemIcon,
    required this.itemIconColor,
    required this.addNewLabel,
    required this.onAddNew,
    required this.searchHint,
  });

  @override
  State<_EntityPickerDialog<T>> createState() => _EntityPickerDialogState<T>();
}

class _EntityPickerDialogState<T> extends State<_EntityPickerDialog<T>> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _addNew() async {
    if (widget.onAddNew == null) return;
    final created = await widget.onAddNew!(context, _ctrl.text.trim());
    if (!mounted) return;
    if (created != null) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().trim();
    final matches = q.isEmpty
        ? widget.items
        : widget.items
            .where(
              (it) => widget.displayName(it).toLowerCase().contains(q),
            )
            .toList();
    final exactExists = matches
        .any((it) => widget.displayName(it).toLowerCase().trim() == q);

    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Text(widget.title,
          style: const TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: InputDecoration(
                labelText: widget.searchHint,
                prefixIcon: const Icon(Icons.search,
                    size: 16, color: KColors.textDim),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        q.isEmpty ? 'Nothing yet.' : 'No matches.',
                        style: const TextStyle(
                          color: KColors.textMuted,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      itemBuilder: (ctx, i) {
                        final it = matches[i];
                        final sub = widget.secondaryLine?.call(it);
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(widget.itemIcon,
                              size: 14, color: widget.itemIconColor),
                          title: Text(widget.displayName(it),
                              style: const TextStyle(
                                  color: KColors.text, fontSize: 12)),
                          subtitle: sub != null && sub.isNotEmpty
                              ? Text(sub,
                                  style: const TextStyle(
                                      color: KColors.textMuted,
                                      fontSize: 10))
                              : null,
                          onTap: () => Navigator.of(context).pop(it),
                        );
                      },
                    ),
            ),
            if (widget.onAddNew != null && !exactExists) ...[
              const Divider(color: KColors.border, height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addNew,
                  icon: const Icon(Icons.add_circle_outline,
                      size: 14, color: KColors.phosphor),
                  label: Text(
                    q.isEmpty
                        ? widget.addNewLabel
                        : 'Add "${_ctrl.text.trim()}" ${widget.addNewLabel.toLowerCase()}',
                    style: const TextStyle(
                        color: KColors.phosphor, fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
      ],
    );
  }
}
