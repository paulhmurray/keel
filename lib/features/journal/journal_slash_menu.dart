import 'package:flutter/material.dart';
import '../../shared/theme/keel_colors.dart';

class SlashCommand {
  final String command;
  final String description;
  final String template;
  final IconData icon;

  const SlashCommand({
    required this.command,
    required this.description,
    required this.template,
    required this.icon,
  });
}

// Placeholder markers use ⟨ ⟩ (U+27E8/27E9 — mathematical angle brackets).
// These are virtually never typed by hand, making them safe tab-stop markers.
// The editor selects each ⟨placeholder⟩ in turn as the user presses Tab.
const kSlashCommands = [
  SlashCommand(
    command: '/meeting',
    description: 'Meeting header',
    template: '## Meeting: ⟨title⟩\nDate: ⟨date⟩\nAttendees: ⟨names⟩\n\n',
    icon: Icons.groups_outlined,
  ),
  SlashCommand(
    command: '/action',
    description: 'Action item',
    template: '**Action:** ⟨name⟩ — ⟨task⟩ — by ⟨date⟩\n',
    icon: Icons.check_circle_outline,
  ),
  SlashCommand(
    command: '/decision',
    description: 'Decision',
    template: '**Decision:** ⟨description⟩\nDecision-maker: ⟨maker⟩\n',
    icon: Icons.gavel_outlined,
  ),
  SlashCommand(
    command: '/risk',
    description: 'Risk',
    template: '**Risk:** ⟨description⟩\nLikelihood: ⟨medium⟩ | Impact: ⟨medium⟩\n',
    icon: Icons.shield_outlined,
  ),
  SlashCommand(
    command: '/issue',
    description: 'Issue',
    template: '**Issue:** ⟨description⟩\nOwner: ⟨owner⟩\n',
    icon: Icons.warning_amber_outlined,
  ),
  SlashCommand(
    command: '/dep',
    description: 'Dependency',
    template: '**Dependency:** ⟨description⟩\nOwner: ⟨owner⟩\n',
    icon: Icons.link_outlined,
  ),
  SlashCommand(
    command: '/note',
    description: 'Plain note',
    template: '**Note:** ⟨note⟩',
    icon: Icons.sticky_note_2_outlined,
  ),
  SlashCommand(
    command: '/date',
    description: 'Insert today\'s date',
    template: '{{today}}',
    icon: Icons.calendar_today_outlined,
  ),
];

List<SlashCommand> filteredSlashCommands(String query) {
  final q = query.toLowerCase();
  if (q.isEmpty) return kSlashCommands;
  return kSlashCommands
      .where((c) =>
          c.command.toLowerCase().contains(q) ||
          c.description.toLowerCase().contains(q))
      .toList();
}

class JournalSlashMenu extends StatelessWidget {
  final String query;
  final int selectedIndex;
  final void Function(SlashCommand) onSelect;
  final VoidCallback onDismiss;

  const JournalSlashMenu({
    super.key,
    required this.query,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final items = filteredSlashCommands(query);
    if (items.isEmpty) return const SizedBox.shrink();
    final sel = selectedIndex.clamp(0, items.length - 1);

    return Container(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 240),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: KColors.border2),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Text(
                  'COMMANDS',
                  style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08,
                  ),
                ),
                const Spacer(),
                const Text(
                  '↑↓ navigate  ↵ select  Esc dismiss',
                  style: TextStyle(color: KColors.textMuted, fontSize: 9),
                ),
              ],
            ),
          ),
          const Divider(color: KColors.border, height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: items.asMap().entries.map((e) {
                final i = e.key;
                final cmd = e.value;
                final isSelected = i == sel;
                return InkWell(
                  onTap: () => onSelect(cmd),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: isSelected ? KColors.amberDim : Colors.transparent,
                    child: Row(
                      children: [
                        Icon(cmd.icon,
                            size: 14,
                            color: isSelected ? KColors.amber : KColors.textDim),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cmd.command,
                                style: TextStyle(
                                  color: isSelected ? KColors.amber : KColors.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                cmd.description,
                                style: const TextStyle(
                                  color: KColors.textDim,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
