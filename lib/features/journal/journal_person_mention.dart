import 'package:flutter/material.dart';
import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

List<Person> filteredPersons(List<Person> persons, String query) {
  final q = query.toLowerCase();
  if (q.isEmpty) return persons.take(6).toList();
  return persons
      .where((p) =>
          p.name.toLowerCase().contains(q) ||
          (p.role?.toLowerCase().contains(q) ?? false))
      .take(6)
      .toList();
}

class JournalPersonMention extends StatelessWidget {
  final List<Person> persons;
  final String query;
  final int selectedIndex;
  final void Function(Person) onSelect;
  final VoidCallback? onAddNew; // shown when query is non-empty

  const JournalPersonMention({
    super.key,
    required this.persons,
    required this.query,
    required this.selectedIndex,
    required this.onSelect,
    this.onAddNew,
  });

  bool get _showAddNew => query.isNotEmpty && onAddNew != null;

  @override
  Widget build(BuildContext context) {
    final items = filteredPersons(persons, query);
    final showAdd = _showAddNew;
    if (items.isEmpty && !showAdd) return const SizedBox.shrink();
    final total = items.length + (showAdd ? 1 : 0);
    final sel = selectedIndex.clamp(0, total - 1);

    return Container(
      constraints: const BoxConstraints(maxWidth: 240, maxHeight: 220),
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
                  'PEOPLE',
                  style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08,
                  ),
                ),
                const Spacer(),
                const Text(
                  '↑↓ navigate  ↵ select',
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
              children: [
                ...items.asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  final isSelected = i == sel;
                  return InkWell(
                    onTap: () => onSelect(p),
                    child: Container(
                      color: isSelected ? KColors.amberDim : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isSelected ? KColors.amber : KColors.amberDim,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: isSelected ? KColors.bg : KColors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: TextStyle(
                                    color: isSelected ? KColors.amber : KColors.text,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (p.role != null)
                                  Text(
                                    p.role!,
                                    style: const TextStyle(
                                      color: KColors.textDim,
                                      fontSize: 10,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                // Add new person option
                if (showAdd)
                  InkWell(
                    onTap: onAddNew,
                    child: Container(
                      color: sel == items.length
                          ? KColors.phosDim
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: sel == items.length
                                  ? KColors.phosphor
                                  : KColors.surface2,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.person_add_outlined,
                                size: 13,
                                color: sel == items.length
                                    ? KColors.bg
                                    : KColors.textDim,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Add "$query" to People',
                              style: TextStyle(
                                color: sel == items.length
                                    ? KColors.phosphor
                                    : KColors.textDim,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
