import 'package:flutter/material.dart';
import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;

class JournalEntryCard extends StatelessWidget {
  final JournalEntry entry;
  final int linkCount;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const JournalEntryCard({
    super.key,
    required this.entry,
    required this.linkCount,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title = entry.title?.isNotEmpty == true
        ? entry.title!
        : _firstLine(entry.body);

    return Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 2,
                height: 56,
                color: entry.confirmedAt != null ? KColors.phosphor : KColors.amber,
                margin: const EdgeInsets.only(right: 12),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: KColors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (linkCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: KColors.amberDim,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '$linkCount item${linkCount == 1 ? '' : 's'}',
                              style: const TextStyle(
                                color: KColors.amber,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 10, color: KColors.textDim),
                        const SizedBox(width: 4),
                        Text(
                          du.formatDate(entry.entryDate),
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 10),
                        ),
                        const SizedBox(width: 12),
                        if (entry.confirmedAt != null) ...[
                          const Icon(Icons.check_circle_outline,
                              size: 10, color: KColors.phosphor),
                          const SizedBox(width: 3),
                          const Text('Parsed',
                              style: TextStyle(
                                  color: KColors.phosphor, fontSize: 10)),
                        ] else ...[
                          const Icon(Icons.hourglass_empty_outlined,
                              size: 10, color: KColors.textMuted),
                          const SizedBox(width: 3),
                          const Text('Draft',
                              style: TextStyle(
                                  color: KColors.textMuted, fontSize: 10)),
                        ],
                        if (entry.meetingContext != null) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.groups_outlined,
                              size: 10, color: KColors.textDim),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              entry.meetingContext!,
                              style: const TextStyle(
                                  color: KColors.textDim, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (entry.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _preview(entry.body),
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      size: 14, color: KColors.textMuted),
                  onSelected: (v) {
                    if (v == 'delete') onDelete!();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _firstLine(String body) {
    final lines = body.trim().split('\n');
    for (final line in lines) {
      final cleaned = line.replaceAll(RegExp(r'^#+\s*'), '').trim();
      if (cleaned.isNotEmpty) return cleaned;
    }
    return 'Journal entry';
  }

  String _preview(String body) {
    final text = body.replaceAll(RegExp(r'#+\s*'), '').replaceAll('**', '').trim();
    return text.length > 120 ? text.substring(0, 120) : text;
  }
}
