import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/analytics/keel_events.dart';
import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';
import 'template_registry.dart';

/// Gallery: lists the project's existing template instances ("Your
/// Templates") and the available types from the registry ("Available
/// Templates"). Tap an instance to open it; tap an available type to
/// instantiate a new one (prompts for a name first).
class TemplatesGalleryView extends StatelessWidget {
  final String projectId;
  final ValueChanged<String> onOpen;

  const TemplatesGalleryView({
    super.key,
    required this.projectId,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<CanvasTemplate>>(
      stream: db.canvasTemplatesDao.watchTemplatesForProject(projectId),
      builder: (context, snap) {
        final yours = snap.data ?? const <CanvasTemplate>[];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (yours.isNotEmpty) ...[
                const _SectionHeader('Your Templates'),
                const SizedBox(height: 12),
                _GalleryGrid(
                  children: yours
                      .map((t) => _YourTemplateCard(
                            template: t,
                            onOpen: () {
                              context.analytics.track(
                                KeelEvents.templateOpened,
                                props: {
                                  KeelEventProps.templateType:
                                      t.templateType,
                                },
                              );
                              onOpen(t.id);
                            },
                            onAction: (action) =>
                                _handleAction(context, t, action),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 32),
              ],
              const _SectionHeader('Available Templates'),
              const SizedBox(height: 12),
              _GalleryGrid(
                children: TemplateRegistry.available
                    .map((def) => _AvailableTemplateCard(
                          def: def,
                          onTap: () => _createInstance(context, def),
                        ))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createInstance(
      BuildContext context, TemplateDefinition def) async {
    final ctrl =
        TextEditingController(text: 'New ${def.name.toLowerCase()}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KColors.surface,
        title: Text(
          'Create new ${def.name}',
          style: const TextStyle(
              color: KColors.amber,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final db = context.read<AppDatabase>();
    final id = const Uuid().v4();
    await db.canvasTemplatesDao.insertTemplate(
      CanvasTemplatesCompanion.insert(
        id: id,
        projectId: projectId,
        templateType: def.type,
        name: name,
        content: def.defaultContent,
      ),
    );
    if (context.mounted) {
      context.analytics.track(
        KeelEvents.templateCreated,
        props: {KeelEventProps.templateType: def.type},
      );
    }
    onOpen(id);
  }

  Future<void> _handleAction(
      BuildContext context, CanvasTemplate t, _TemplateRowAction a) async {
    final db = context.read<AppDatabase>();
    switch (a) {
      case _TemplateRowAction.rename:
        final ctrl = TextEditingController(text: t.name);
        final newName = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: KColors.surface,
            title: const Text('Rename template',
                style: TextStyle(color: KColors.amber)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (newName == null || newName.isEmpty || newName == t.name) return;
        await db.canvasTemplatesDao.patchTemplate(
          t.id,
          CanvasTemplatesCompanion(name: Value(newName)),
        );
        break;
      case _TemplateRowAction.duplicate:
        await db.canvasTemplatesDao.insertTemplate(
          CanvasTemplatesCompanion.insert(
            id: const Uuid().v4(),
            projectId: t.projectId,
            templateType: t.templateType,
            name: '${t.name} (copy)',
            content: t.content,
          ),
        );
        break;
      case _TemplateRowAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: KColors.surface,
            title: const Text('Delete template?',
                style: TextStyle(color: KColors.amber)),
            content: Text(
              '"${t.name}" will be permanently removed.',
              style: const TextStyle(
                  color: KColors.textDim, fontSize: 12.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColors.redDim,
                  foregroundColor: KColors.red,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await db.canvasTemplatesDao.deleteTemplate(t.id);
        }
        break;
    }
  }
}

enum _TemplateRowAction { rename, duplicate, delete }

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: KColors.amber,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
      ),
    );
  }
}

class _GalleryGrid extends StatelessWidget {
  final List<Widget> children;

  const _GalleryGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: children,
    );
  }
}

class _AvailableTemplateCard extends StatelessWidget {
  final TemplateDefinition def;
  final VoidCallback onTap;

  const _AvailableTemplateCard({required this.def, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KColors.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 220,
          height: 150,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: KColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(def.icon, size: 22, color: KColors.amber),
              const SizedBox(height: 14),
              Text(
                def.name,
                style: const TextStyle(
                  color: KColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  def.description,
                  style: const TextStyle(
                    color: KColors.textDim,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YourTemplateCard extends StatelessWidget {
  final CanvasTemplate template;
  final VoidCallback onOpen;
  final ValueChanged<_TemplateRowAction> onAction;

  const _YourTemplateCard({
    required this.template,
    required this.onOpen,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final def = TemplateRegistry.byType(template.templateType);
    return Material(
      color: KColors.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 220,
          height: 150,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: KColors.amber.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(def?.icon ?? Icons.description_outlined,
                      size: 18, color: KColors.amber),
                  const Spacer(),
                  PopupMenuButton<_TemplateRowAction>(
                    tooltip: 'Template actions',
                    icon: const Icon(Icons.more_horiz,
                        size: 16, color: KColors.textMuted),
                    onSelected: onAction,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: _TemplateRowAction.rename,
                          child: Text('Rename')),
                      PopupMenuItem(
                          value: _TemplateRowAction.duplicate,
                          child: Text('Duplicate')),
                      PopupMenuItem(
                          value: _TemplateRowAction.delete,
                          child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                template.name,
                style: const TextStyle(
                  color: KColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                '${def?.name ?? template.templateType}  ·  '
                'edited ${_relativeTime(template.updatedAt)}',
                style: const TextStyle(
                  color: KColors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime then) {
  final delta = DateTime.now().difference(then);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  if (delta.inDays < 30) return '${delta.inDays}d ago';
  return '${(delta.inDays / 30).floor()}mo ago';
}
