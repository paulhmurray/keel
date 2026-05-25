import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../features/context/glossary_form.dart';
import '../theme/keel_colors.dart';
import 'entity_picker.dart';

/// Inline term/acronym picker — autocomplete from glossary entries where
/// `type='term'`. Matches against both [GlossaryEntry.name] and
/// [GlossaryEntry.acronym]. "Add new" opens the GlossaryFormDialog seeded as
/// a Term entry.
class TermPickerField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final AppDatabase db;
  final String projectId;
  final ValueChanged<GlossaryEntry?>? onSelected;

  const TermPickerField({
    super.key,
    required this.controller,
    required this.label,
    required this.db,
    required this.projectId,
    this.onSelected,
  });

  @override
  State<TermPickerField> createState() => _TermPickerFieldState();
}

class _TermPickerFieldState extends State<TermPickerField> {
  late Future<List<GlossaryEntry>> _terms;

  @override
  void initState() {
    super.initState();
    _terms = _load();
  }

  Future<List<GlossaryEntry>> _load() async {
    final all = await widget.db.glossaryDao.getForProject(widget.projectId);
    return all.where((g) => g.type == 'term').toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GlossaryEntry>>(
      future: _terms,
      builder: (ctx, snap) {
        final terms = snap.data ?? const <GlossaryEntry>[];
        // For acronym matching, we treat the displayName as "Term (ACR)" so
        // a query against the acronym still hits a match in the shell.
        String label(GlossaryEntry e) {
          final acr = e.acronym;
          if (acr != null && acr.trim().isNotEmpty) return '${e.name} ($acr)';
          return e.name;
        }

        return EntityPickerField<GlossaryEntry>(
          controller: widget.controller,
          label: widget.label,
          items: terms,
          displayName: label,
          secondaryLine: (e) =>
              e.description == null ? '' : e.description!,
          itemIcon: Icons.menu_book_outlined,
          itemIconColor: KColors.amber,
          addNewSuffix: 'as new term',
          onSelected: (e) {
            // Strip the parenthesised acronym from the committed string so the
            // caller stores just the canonical term name.
            if (e != null) {
              widget.controller.text = e.name;
              widget.onSelected?.call(e);
            }
          },
          onAddNew: (ctx, query) async {
            final created = await showDialog<GlossaryEntry>(
              context: ctx,
              builder: (_) => GlossaryFormDialog(
                projectId: widget.projectId,
                db: widget.db,
                initialName: query,
                initialType: 'term',
              ),
            );
            if (created != null) {
              setState(() => _terms = _load());
            }
            return created;
          },
        );
      },
    );
  }
}

/// Modal variant.
Future<GlossaryEntry?> showTermPicker({
  required BuildContext context,
  required AppDatabase db,
  required String projectId,
  String title = 'Pick a term',
}) async {
  final all = await db.glossaryDao.getForProject(projectId);
  final terms = all.where((g) => g.type == 'term').toList();
  if (!context.mounted) return null;
  return showEntityPicker<GlossaryEntry>(
    context: context,
    title: title,
    items: terms,
    displayName: (e) {
      final acr = e.acronym;
      if (acr != null && acr.trim().isNotEmpty) return '${e.name} ($acr)';
      return e.name;
    },
    secondaryLine: (e) => e.description ?? '',
    itemIcon: Icons.menu_book_outlined,
    itemIconColor: KColors.amber,
    addNewLabel: 'term',
    searchHint: 'Search terms & acronyms…',
    onAddNew: (ctx, query) async {
      return showDialog<GlossaryEntry>(
        context: ctx,
        builder: (_) => GlossaryFormDialog(
          projectId: projectId,
          db: db,
          initialName: query,
          initialType: 'term',
        ),
      );
    },
  );
}
