import 'package:flutter/material.dart';
import '../../shared/theme/keel_colors.dart';

class KeelNavRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  // When true, the overview tab reads PROG and uses a workspaces icon
  // (programme-scoped install). Default false → reads PROJ. The rest
  // of the rail is identical for V1; per-section divergence happens
  // inside each view based on ProjectProvider.isProgramme.
  final bool isProgramme;
  // Opens the project-wide find palette (Ctrl+K). Hidden when null.
  final VoidCallback? onSearch;

  const KeelNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.isProgramme = false,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: KColors.bg,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // Find sits first: it reaches everything below, so the
                  // user never has to know which section holds a thing.
                  if (onSearch != null) ...[
                    _SearchNavItem(onTap: onSearch!),
                    const _NavDivider(),
                  ],
                  // Helm sits ABOVE the project navigation — it's the
                  // user's global day, not a view of the current project,
                  // so it keeps its place when the project switches.
                  _HelmNavItem(
                    selected: selectedIndex == 16,
                    onTap: onDestinationSelected,
                  ),
                  const _NavDivider(),
                  // A programme keeps its overview; a project's home is
                  // Helm, so it has no overview item.
                  if (isProgramme)
                    _NavItem(
                      icon: Icons.workspaces_outlined,
                      label: 'Prog',
                      index: 0,
                      selected: selectedIndex == 0,
                      onTap: onDestinationSelected,
                    ),
                  _NavItem(icon: Icons.bubble_chart_outlined, label: 'Canvas', index: 1, selected: selectedIndex == 1, onTap: onDestinationSelected),
                  _NavItem(icon: Icons.table_chart_outlined, label: 'Plan', index: 12, selected: selectedIndex == 12, onTap: onDestinationSelected),
                  _NavItem(icon: Icons.monitor_heart_outlined, label: 'Status', index: 13, selected: selectedIndex == 13, onTap: onDestinationSelected),
                  _NavItem(icon: Icons.article_outlined, label: 'Charter', index: 14, selected: selectedIndex == 14, onTap: onDestinationSelected),
                  _NavItem(icon: Icons.account_balance_outlined, label: 'Finance', index: 15, selected: selectedIndex == 15, onTap: onDestinationSelected),
                  const _NavDivider(),
                  _NavItem(icon: Icons.shield_outlined, label: 'RAID', index: 2, selected: selectedIndex == 2, onTap: onDestinationSelected),
                  _NavItem(icon: Icons.gavel_outlined, label: 'Dec', index: 3, selected: selectedIndex == 3, onTap: onDestinationSelected),
                  _NavItem(icon: Icons.group_outlined, label: 'People', index: 4, selected: selectedIndex == 4, onTap: onDestinationSelected),
                  _NavItem(icon: Icons.check_circle_outline, label: 'Actions', index: 5, selected: selectedIndex == 5, onTap: onDestinationSelected),
                  const _NavDivider(),
                  _NavItem(icon: Icons.inbox_outlined, label: 'Inbox', index: 6, selected: selectedIndex == 6, onTap: onDestinationSelected),
                  _NavItem(icon: Icons.library_books_outlined, label: 'Context', index: 7, selected: selectedIndex == 7, onTap: onDestinationSelected),
                  const _NavDivider(),
                  _NavItem(icon: Icons.description_outlined, label: 'Reports', index: 8, selected: selectedIndex == 8, onTap: onDestinationSelected),
                  const _NavDivider(),
                  _NavItem(icon: Icons.menu_book_outlined, label: 'Journal', index: 10, selected: selectedIndex == 10, onTap: onDestinationSelected),
                  const _NavDivider(),
                  _NavItem(icon: Icons.account_tree_outlined, label: 'Playbook', index: 11, selected: selectedIndex == 11, onTap: onDestinationSelected),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: KColors.border),
          _NavItem(icon: Icons.settings_outlined, label: 'Settings', index: 9, selected: selectedIndex == 9, onTap: onDestinationSelected),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool selected;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unselectedColor = const Color(0xFF8a9faf);
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        width: 64,
        height: 56,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: selected ? KColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? KColors.amber : unselectedColor,
            ),
            const SizedBox(height: 3),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: selected ? KColors.amber : unselectedColor,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helm gets its own visual treatment — a bordered slot marking it as
/// global ("you") rather than one more lens on the current project.
class _HelmNavItem extends StatelessWidget {
  final bool selected;
  final ValueChanged<int> onTap;

  const _HelmNavItem({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? KColors.amber : const Color(0xFF8a9faf);
    return GestureDetector(
      onTap: () => onTap(16),
      child: Container(
        width: 64,
        height: 56,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: selected ? KColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? KColors.amber
                : KColors.amber.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              'HELM',
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The find entry: never "selected", because it's a verb, not a place.
class _SearchNavItem extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchNavItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF8a9faf);
    return Tooltip(
      message: 'Find anything in this project (Ctrl+K)',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 56,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, size: 22, color: color),
              SizedBox(height: 3),
              Text(
                'FIND',
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavDivider extends StatelessWidget {
  const _NavDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: KColors.border,
    );
  }
}
