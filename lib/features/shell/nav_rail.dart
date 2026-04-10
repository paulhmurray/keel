import 'package:flutter/material.dart';
import '../../shared/theme/keel_colors.dart';

class KeelNavRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const KeelNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: KColors.bg,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _NavItem(icon: Icons.dashboard_outlined, label: 'Prog', index: 0, selected: selectedIndex == 0, onTap: onDestinationSelected),
          _NavItem(icon: Icons.timeline_outlined, label: 'Time', index: 1, selected: selectedIndex == 1, onTap: onDestinationSelected),
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
          const Spacer(),
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
