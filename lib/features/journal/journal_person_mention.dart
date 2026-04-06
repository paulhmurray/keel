import 'package:flutter/material.dart';
import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

class JournalPersonMention extends StatelessWidget {
  final List<Person> persons;
  final String query;
  final void Function(Person) onSelect;

  const JournalPersonMention({
    super.key,
    required this.persons,
    required this.query,
    required this.onSelect,
  });

  List<Person> get _filtered {
    final q = query.toLowerCase();
    if (q.isEmpty) return persons.take(6).toList();
    return persons
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            (p.role?.toLowerCase().contains(q) ?? false))
        .take(6)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 240, maxHeight: 200),
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
      child: ListView(
        shrinkWrap: true,
        children: items.map((p) => InkWell(
          onTap: () => onSelect(p),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: KColors.amberDim,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: KColors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: const TextStyle(
                            color: KColors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    if (p.role != null)
                      Text(p.role!,
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        )).toList(),
      ),
    );
  }
}
