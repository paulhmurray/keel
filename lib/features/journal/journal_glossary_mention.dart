import 'package:flutter/material.dart';
import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

List<GlossaryEntry> filteredGlossaryEntries(
    List<GlossaryEntry> entries, String query) {
  final q = query.toLowerCase();
  if (q.isEmpty) return entries.take(6).toList();
  return entries
      .where((e) =>
          e.name.toLowerCase().contains(q) ||
          (e.acronym?.toLowerCase().contains(q) ?? false))
      .take(6)
      .toList();
}

class JournalGlossaryMention extends StatelessWidget {
  final List<GlossaryEntry> entries;
  final String query;
  final int selectedIndex;
  final void Function(GlossaryEntry) onSelect;
  final VoidCallback? onAddNew;

  const JournalGlossaryMention({
    super.key,
    required this.entries,
    required this.query,
    required this.selectedIndex,
    required this.onSelect,
    this.onAddNew,
  });

  bool get _showAddNew => query.isNotEmpty && onAddNew != null;

  @override
  Widget build(BuildContext context) {
    final items = filteredGlossaryEntries(entries, query);
    final showAdd = _showAddNew;
    if (items.isEmpty && !showAdd) return const SizedBox.shrink();
    final total = items.length + (showAdd ? 1 : 0);
    final sel = selectedIndex.clamp(0, total - 1);

    return Container(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 220),
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
              children: const [
                Text(
                  'GLOSSARY',
                  style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08,
                  ),
                ),
                Spacer(),
                Text(
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
                  final entry = e.value;
                  final isSelected = i == sel;
                  final isSystem = entry.type == 'system';
                  return InkWell(
                    onTap: () => onSelect(entry),
                    child: Container(
                      color: isSelected ? KColors.phosDim : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? KColors.phosphor
                                  : KColors.phosDim,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              isSystem ? 'SYS' : 'TRM',
                              style: TextStyle(
                                color: isSelected
                                    ? KColors.bg
                                    : KColors.phosphor,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.name,
                                  style: TextStyle(
                                    color: isSelected
                                        ? KColors.phosphor
                                        : KColors.text,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (entry.acronym?.isNotEmpty ?? false)
                                  Text(
                                    entry.acronym!,
                                    style: const TextStyle(
                                        color: KColors.textDim, fontSize: 10),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                // Add new glossary entry option
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
                            width: 28,
                            height: 20,
                            decoration: BoxDecoration(
                              color: sel == items.length
                                  ? KColors.phosphor
                                  : KColors.surface2,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.add,
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
                              'Add "$query" to Glossary',
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
