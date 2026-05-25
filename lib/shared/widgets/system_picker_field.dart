import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../features/context/glossary_form.dart';
import '../theme/keel_colors.dart';
import 'entity_picker.dart';

/// Inline system picker — autocomplete from glossary entries where
/// `type='system'`. "Add new" opens the full GlossaryFormDialog pre-seeded as
/// a System entry.
///
/// Stores the system's `name` back into [controller] (and surfaces the entry
/// via [onSelected] if you need the full object).
class SystemPickerField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final AppDatabase db;
  final String projectId;
  final ValueChanged<GlossaryEntry?>? onSelected;

  const SystemPickerField({
    super.key,
    required this.controller,
    required this.label,
    required this.db,
    required this.projectId,
    this.onSelected,
  });

  @override
  State<SystemPickerField> createState() => _SystemPickerFieldState();
}

class _SystemPickerFieldState extends State<SystemPickerField> {
  late Future<List<GlossaryEntry>> _systems;

  @override
  void initState() {
    super.initState();
    _systems = _load();
  }

  Future<List<GlossaryEntry>> _load() async {
    final all = await widget.db.glossaryDao.getForProject(widget.projectId);
    return all.where((g) => g.type == 'system').toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GlossaryEntry>>(
      future: _systems,
      builder: (ctx, snap) {
        final systems = snap.data ?? const <GlossaryEntry>[];
        return EntityPickerField<GlossaryEntry>(
          controller: widget.controller,
          label: widget.label,
          items: systems,
          displayName: (e) => e.name,
          secondaryLine: (e) => [
            if (e.acronym != null && e.acronym!.isNotEmpty) e.acronym!,
            if (e.environment != null) e.environment!,
            if (e.status != null) e.status!,
          ].join(' · '),
          itemIcon: Icons.dns_outlined,
          itemIconColor: KColors.blue,
          addNewSuffix: 'as new system',
          onSelected: widget.onSelected,
          onAddNew: (ctx, query) async {
            final created = await showDialog<GlossaryEntry>(
              context: ctx,
              builder: (_) => GlossaryFormDialog(
                projectId: widget.projectId,
                db: widget.db,
                initialName: query,
                initialType: 'system',
              ),
            );
            if (created != null) {
              setState(() => _systems = _load());
            }
            return created;
          },
        );
      },
    );
  }
}

/// Modal variant — useful for "tag a related system" buttons.
Future<GlossaryEntry?> showSystemPicker({
  required BuildContext context,
  required AppDatabase db,
  required String projectId,
  String title = 'Pick a system',
}) async {
  final all = await db.glossaryDao.getForProject(projectId);
  final systems = all.where((g) => g.type == 'system').toList();
  if (!context.mounted) return null;
  return showEntityPicker<GlossaryEntry>(
    context: context,
    title: title,
    items: systems,
    displayName: (e) => e.name,
    secondaryLine: (e) => [
      if (e.acronym != null && e.acronym!.isNotEmpty) e.acronym!,
      if (e.environment != null) e.environment!,
      if (e.status != null) e.status!,
    ].join(' · '),
    itemIcon: Icons.dns_outlined,
    itemIconColor: KColors.blue,
    addNewLabel: 'system',
    searchHint: 'Search systems…',
    onAddNew: (ctx, query) async {
      return showDialog<GlossaryEntry>(
        context: ctx,
        builder: (_) => GlossaryFormDialog(
          projectId: projectId,
          db: db,
          initialName: query,
          initialType: 'system',
        ),
      );
    },
  );
}
