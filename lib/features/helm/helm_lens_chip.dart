import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/helm/helm_lens.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';

/// The header chip naming which projects Helm looks through: "All
/// projects", one project by name, or "3 projects". Click to choose.
/// Amber when a lens is set so a narrowed Helm is never mistaken for an
/// empty one. The choice is local to this machine (see [HelmLens]).
/// [compact] drops the label for a narrow header — the tooltip still
/// names the lens, and the chip stays amber when narrowed.
class HelmLensChip extends StatelessWidget {
  final bool compact;
  const HelmLensChip({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<ProjectProvider>().projects;
    final settings = context.watch<SettingsProvider>();
    final lens = settings.settings.helmLens.restrictedTo(
      projects.map((p) => p.id),
    );
    final label = helmLensLabel(lens, {for (final p in projects) p.id: p.name});
    final narrowed = lens.active;
    final colour = narrowed ? KColors.amber : KColors.textDim;
    return Tooltip(
      message: narrowed
          ? 'Helm is planning around $label only. Click to change — '
                'local to this machine.'
          : 'Helm draws from every project. Click to narrow it — '
                'local to this machine.',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: () async {
          final picked = await showDialog<HelmLens>(
            context: context,
            builder: (_) => HelmLensDialog(projects: projects, lens: lens),
          );
          if (picked != null) await settings.setHelmLens(picked);
        },
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: narrowed ? KColors.amberDim : KColors.surface2,
            border: Border.all(
              color: narrowed ? KColors.amber : KColors.border2,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_outlined, size: 12, color: colour),
              if (!compact) ...[
                const SizedBox(width: 5),
                // Flexible: in a tight header the label ellipsizes rather
                // than pushing the row past its edge.
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colour,
                        fontSize: 11,
                        fontWeight: narrowed
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 3),
              Icon(Icons.arrow_drop_down, size: 14, color: colour),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick the projects Helm plans around. Returns the chosen lens, or null
/// on cancel. Pure of providers so it can be tested on its own.
class HelmLensDialog extends StatefulWidget {
  final List<Project> projects;
  final HelmLens lens;
  const HelmLensDialog({super.key, required this.projects, required this.lens});

  @override
  State<HelmLensDialog> createState() => _HelmLensDialogState();
}

class _HelmLensDialogState extends State<HelmLensDialog> {
  late bool _all = !widget.lens.active;
  late final Set<String> _picked = {...widget.lens.projectIds};

  static const _kindOrder = ['portfolio', 'programme', 'project'];
  static String _kindLabel(String kind) => switch (kind) {
    'portfolio' => 'Portfolio',
    'programme' => 'Programme',
    _ => 'Project',
  };

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.projects]
      ..sort((a, b) {
        final k = _kindOrder
            .indexOf(a.kind)
            .compareTo(_kindOrder.indexOf(b.kind));
        return k != 0
            ? k
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Text(
        'What Helm plans around',
        style: TextStyle(color: KColors.text, fontSize: 15),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The planning columns and the week ritual draw their actions, '
              'risks, decisions and plan dates from these projects. Nothing '
              'else changes, and the choice stays on this machine.',
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeThumbColor: KColors.amber,
              title: Text(
                'All projects',
                style: TextStyle(color: KColors.text, fontSize: 13),
              ),
              value: _all,
              onChanged: (v) => setState(() => _all = v),
            ),
            Divider(color: KColors.border2, height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in sorted)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: KColors.amber,
                      enabled: !_all,
                      title: Text(
                        p.name,
                        style: TextStyle(
                          color: _all ? KColors.textMuted : KColors.text,
                          fontSize: 13,
                        ),
                      ),
                      secondary: Text(
                        _kindLabel(p.kind),
                        style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      value: _picked.contains(p.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _picked.add(p.id);
                        } else {
                          _picked.remove(p.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
            if (!_all && _picked.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Pick at least one project, or Helm shows all of them.',
                style: TextStyle(color: KColors.amber, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(HelmLens(projectIds: _picked, on: !_all && _picked.isNotEmpty)),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
