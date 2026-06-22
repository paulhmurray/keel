import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';
import 'instances/pre_mortem/pre_mortem_view.dart';
import 'instances/raci_matrix/raci_view.dart';
import 'instances/retrospective/retro_view.dart';
import 'instances/stakeholder_map/stakeholder_map_view.dart';
import 'instances/swot/swot_view.dart';
import 'instances/user_story_map/usm_view.dart';
import 'template_presentation.dart';
import 'template_registry.dart';

/// Common shell wrapping every per-template view: a back button, an
/// inline-editable title, a relative "last edited" timestamp, and the
/// template's own body widget below.
///
/// In Phase 2 the body is a placeholder (`_ComingSoonBody`) — Phase 3
/// will swap in real per-type widgets via the dispatcher in this file.
class TemplateShell extends StatefulWidget {
  final String templateId;
  final VoidCallback onBack;

  const TemplateShell({
    super.key,
    required this.templateId,
    required this.onBack,
  });

  @override
  State<TemplateShell> createState() => _TemplateShellState();
}

class _TemplateShellState extends State<TemplateShell> {
  /// True while the title chip is in inline-edit mode.
  bool _editingTitle = false;
  late final TextEditingController _titleCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveTitle(String id, String current, String next) async {
    final trimmed = next.trim();
    if (trimmed.isEmpty || trimmed == current) {
      setState(() => _editingTitle = false);
      return;
    }
    final db = context.read<AppDatabase>();
    await db.canvasTemplatesDao.patchTemplate(
      id,
      CanvasTemplatesCompanion(name: Value(trimmed)),
    );
    if (mounted) setState(() => _editingTitle = false);
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return StreamBuilder<CanvasTemplate?>(
      stream: db.canvasTemplatesDao.watchTemplateById(widget.templateId),
      builder: (context, snap) {
        final t = snap.data;
        if (t == null) {
          // Either still loading the first event or the template was
          // deleted out from under us — either way show a neutral
          // placeholder rather than blowing up.
          return const Center(
            child: Text(
              'Template not found.',
              style: TextStyle(color: KColors.textMuted),
            ),
          );
        }
        final def = TemplateRegistry.byType(t.templateType);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShellHeader(
              template: t,
              definition: def,
              editingTitle: _editingTitle,
              titleCtrl: _titleCtrl,
              onStartEdit: () {
                _titleCtrl.text = t.name;
                setState(() => _editingTitle = true);
              },
              onCommitEdit: (v) => _saveTitle(t.id, t.name, v),
              onBack: widget.onBack,
              onPresentation: (def?.supportsFullscreen ?? false)
                  ? () => openTemplatePresentation(
                        context,
                        title: t.name,
                        icon: def?.icon ??
                            Icons.dashboard_customize_outlined,
                        child: _dispatchBody(t, def),
                      )
                  : null,
            ),
            Expanded(
              child: _dispatchBody(t, def),
            ),
          ],
        );
      },
    );
  }

  /// Per-type body dispatcher. Phase 3 fills these in one type at a
  /// time; everything not yet implemented falls through to the
  /// coming-soon placeholder.
  Widget _dispatchBody(CanvasTemplate t, TemplateDefinition? def) {
    switch (t.templateType) {
      case CanvasTemplateType.preMortem:
        return PreMortemView(template: t);
      case CanvasTemplateType.swot:
        return SwotView(template: t);
      case CanvasTemplateType.retrospective:
        return RetroView(template: t);
      case CanvasTemplateType.stakeholderMap:
        return StakeholderMapView(template: t);
      case CanvasTemplateType.raciMatrix:
        return RaciView(template: t);
      case CanvasTemplateType.userStoryMap:
        return UsmView(template: t);
      default:
        return _ComingSoonBody(template: t, definition: def);
    }
  }
}

class _ShellHeader extends StatelessWidget {
  final CanvasTemplate template;
  final TemplateDefinition? definition;
  final bool editingTitle;
  final TextEditingController titleCtrl;
  final VoidCallback onStartEdit;
  final ValueChanged<String> onCommitEdit;
  final VoidCallback onBack;
  // Null when the template type doesn't support a presentation overlay.
  final VoidCallback? onPresentation;

  const _ShellHeader({
    required this.template,
    required this.definition,
    required this.editingTitle,
    required this.titleCtrl,
    required this.onStartEdit,
    required this.onCommitEdit,
    required this.onBack,
    this.onPresentation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: KColors.surface,
        border: Border(
          bottom: BorderSide(color: KColors.border, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Back to Templates',
            visualDensity: VisualDensity.compact,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back,
                size: 18, color: KColors.textDim),
          ),
          const SizedBox(width: 4),
          Icon(definition?.icon ?? Icons.description_outlined,
              size: 16, color: KColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: editingTitle
                ? TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                    ),
                    onSubmitted: onCommitEdit,
                    onTapOutside: (_) => onCommitEdit(titleCtrl.text),
                  )
                : InkWell(
                    onTap: onStartEdit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        template.name,
                        style: const TextStyle(
                          color: KColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Text(
            '${definition?.name ?? template.templateType}  ·  '
            'edited ${_relativeTime(template.updatedAt)}',
            style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 11,
            ),
          ),
          if (onPresentation != null) ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onPresentation,
              icon: const Icon(Icons.fullscreen, size: 14),
              label: const Text('Presentation'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KColors.amber,
                side: const BorderSide(color: KColors.amber),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 12),
                minimumSize: const Size(0, 30),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComingSoonBody extends StatelessWidget {
  final CanvasTemplate template;
  final TemplateDefinition? definition;

  const _ComingSoonBody({required this.template, required this.definition});

  @override
  Widget build(BuildContext context) {
    final name = definition?.name ?? template.templateType;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(definition?.icon ?? Icons.construction,
                  size: 28, color: KColors.amber),
              const SizedBox(height: 14),
              Text(
                '$name coming next',
                style: const TextStyle(
                  color: KColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'ve created the instance — Phase 3 of Canvas v2 '
                'plugs in the actual ${name.toLowerCase()} surface. '
                'Until then, the saved record is here whenever you '
                'come back.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 12.5,
                  height: 1.45,
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
