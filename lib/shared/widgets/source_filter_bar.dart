import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/programme/source_filter.dart';
import '../../providers/project_provider.dart';
import '../theme/keel_colors.dart';

/// Programme-side chip row for registers that mix native rows with
/// cascaded copies: All · This programme · one chip per linked project,
/// plus an "Escalated only" switch. Renders nothing on a plain project
/// or on a programme with no active links, so it can be mounted
/// unconditionally.
class SourceFilterBar extends StatelessWidget {
  final SourceFilter filter;
  final ValueChanged<SourceFilter> onChanged;
  final EdgeInsetsGeometry padding;

  const SourceFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(24, 10, 24, 0),
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final current = provider.currentProject;
    if (current == null || !provider.isProgramme) {
      return const SizedBox.shrink();
    }
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<ProgrammeLink>>(
      stream: db.programmeLinksDao.watchLinksForEntity(current.id),
      builder: (context, snap) {
        final links = (snap.data ?? const <ProgrammeLink>[])
            .where((l) => l.status == 'active')
            .toList();
        if (links.isEmpty) return const SizedBox.shrink();
        final projects = {for (final p in provider.projects) p.id: p.name};
        final sources = <(String id, String name)>[];
        for (final l in links) {
          final id = l.partnerLocalId;
          if (id == null) continue;
          sources.add((id, projects[id] ?? l.partnerName ?? 'Linked project'));
        }
        sources.sort((a, b) => a.$2.compareTo(b.$2));

        return Padding(
          padding: padding,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 2),
                child: Text('SHOW',
                    style: TextStyle(
                        color: KColors.textMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
              ),
              _Chip(
                label: 'All',
                selected: filter.sourceId == null,
                onTap: () => onChanged(filter.copyWith(clearSource: true)),
              ),
              _Chip(
                label: 'This programme',
                selected: filter.sourceId == SourceFilter.kProgrammeOnly,
                onTap: () => onChanged(
                    filter.copyWith(sourceId: SourceFilter.kProgrammeOnly)),
              ),
              for (final s in sources)
                _Chip(
                  label: s.$2,
                  icon: Icons.link,
                  selected: filter.sourceId == s.$1,
                  onTap: () => onChanged(filter.copyWith(sourceId: s.$1)),
                ),
              const SizedBox(width: 6),
              _Chip(
                label: 'Escalated only',
                icon: Icons.arrow_upward,
                selected: filter.escalatedOnly,
                accent: KColors.amber,
                tooltip: filter.escalatedOnly
                    ? 'Showing only items the project PMs escalated. '
                        'Click to see the full registers.'
                    : 'Full-detail links carry every item. Click to keep '
                        'only what the project PMs escalated.',
                onTap: () => onChanged(
                    filter.copyWith(escalatedOnly: !filter.escalatedOnly)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final String? tooltip;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accent = KColors.phosphor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accent : KColors.textDim;
    final chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : KColors.surface2,
          border: Border.all(color: selected ? accent : KColors.border2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
    return tooltip == null
        ? chip
        : Tooltip(
            message: tooltip!,
            waitDuration: const Duration(milliseconds: 350),
            child: chip);
  }
}
