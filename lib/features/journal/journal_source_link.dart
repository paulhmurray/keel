import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/journal/journal_match.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;
import 'journal_link_renderer.dart';
import 'journal_overlay.dart';

/// "From journal" chips for an item that was extracted from one or more
/// journal entries. Resolves `journal_entry_links` for [itemId]; renders
/// nothing when there are none, so manually-created items look
/// unchanged. Tapping a chip opens a read-only peek at the entry with
/// the passage the item most likely came from highlighted.
class JournalSourceLink extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final String itemId;

  /// The item's own text, used to find the originating passage.
  final String itemText;

  const JournalSourceLink({
    super.key,
    required this.db,
    required this.projectId,
    required this.itemId,
    required this.itemText,
  });

  @override
  State<JournalSourceLink> createState() => _JournalSourceLinkState();
}

class _JournalSourceLinkState extends State<JournalSourceLink> {
  List<JournalEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final links = await widget.db.journalDao.getLinksForItem(widget.itemId);
    final entries = <JournalEntry>[];
    final seen = <String>{};
    for (final l in links) {
      if (!seen.add(l.entryId)) continue;
      final e = await widget.db.journalDao.getEntryById(l.entryId);
      if (e != null) entries.add(e);
    }
    entries.sort((a, b) => b.entryDate.compareTo(a.entryDate));
    if (mounted) setState(() => _entries = entries);
  }

  static String labelFor(JournalEntry e) {
    final date = du.formatDate(e.entryDate);
    final title = e.title?.trim();
    return title == null || title.isEmpty ? date : '$title · $date';
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FROM JOURNAL',
            style: TextStyle(
              color: KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _entries)
                Tooltip(
                  message: 'Re-read the journal entry this came from',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(3),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => JournalEntryPeekDialog(
                        db: widget.db,
                        projectId: widget.projectId,
                        entry: e,
                        highlightText: widget.itemText,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: KColors.violetDim,
                        border: Border.all(
                            color: KColors.violet.withAlpha(90)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.menu_book_outlined,
                              size: 12, color: KColors.violet),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 260),
                            child: Text(
                              labelFor(e),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: KColors.violet,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.open_in_new,
                              size: 10, color: KColors.violet),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Read-only view of a journal entry, opened from an item that was
/// extracted from it. The paragraph that best matches [highlightText]
/// is tinted so the PM lands on the relevant passage; the whole entry
/// stays readable around it. "Open in Journal" hands off to the full
/// editor.
class JournalEntryPeekDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final JournalEntry entry;
  final String? highlightText;

  const JournalEntryPeekDialog({
    super.key,
    required this.db,
    required this.projectId,
    required this.entry,
    this.highlightText,
  });

  @override
  State<JournalEntryPeekDialog> createState() => _JournalEntryPeekDialogState();
}

class _JournalEntryPeekDialogState extends State<JournalEntryPeekDialog> {
  List<Person> _persons = const [];
  List<GlossaryEntry> _glossary = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final persons =
        await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    final glossary =
        await widget.db.glossaryDao.getForProject(widget.projectId);
    if (mounted) {
      setState(() {
        _persons = persons;
        _glossary = glossary;
      });
    }
  }

  void _openInJournal() {
    final settings = context.read<SettingsProvider>().settings;
    final navigator = Navigator.of(context);
    navigator.pop();
    showGeneralDialog(
      context: navigator.context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      pageBuilder: (_, _, _) => JournalOverlay(
        projectId: widget.projectId,
        db: widget.db,
        settings: settings,
        existingEntry: widget.entry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final paragraphs = splitParagraphs(e.body);
    final match = widget.highlightText == null
        ? null
        : bestMatchingParagraph(e.body, widget.highlightText!);
    final size = MediaQuery.of(context).size;

    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Row(children: [
        const Icon(Icons.menu_book_outlined, size: 16, color: KColors.violet),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            e.title?.trim().isNotEmpty == true ? e.title!.trim() : 'Journal entry',
            style: const TextStyle(color: KColors.text, fontSize: 15),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(du.formatDate(e.entryDate),
            style: const TextStyle(color: KColors.textDim, fontSize: 12)),
      ]),
      content: SizedBox(
        width: (size.width * 0.7).clamp(360.0, 820.0),
        height: (size.height * 0.75).clamp(300.0, 760.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.meetingContext != null && e.meetingContext!.isNotEmpty) ...[
              Text(e.meetingContext!,
                  style: const TextStyle(
                      color: KColors.textDim,
                      fontSize: 11,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
            ],
            if (match != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Highlighted: the passage this item was most likely '
                  'extracted from.',
                  style: TextStyle(color: KColors.textMuted, fontSize: 10),
                ),
              ),
            Expanded(
              child: paragraphs.isEmpty
                  ? const Text('(empty entry)',
                      style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 12,
                          fontStyle: FontStyle.italic))
                  : ListView.builder(
                      itemCount: paragraphs.length,
                      itemBuilder: (_, i) {
                        final hit = match?.paragraphIndex == i;
                        return Container(
                          key: hit ? const Key('journal-peek-highlight') : null,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: hit
                              ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
                              : EdgeInsets.zero,
                          decoration: hit
                              ? BoxDecoration(
                                  color: KColors.amberDim,
                                  border: Border(
                                      left: BorderSide(
                                          color: KColors.amber, width: 2)),
                                  borderRadius: BorderRadius.circular(3),
                                )
                              : null,
                          child: JournalLinkRenderer(
                            text: paragraphs[i],
                            persons: _persons,
                            glossaryEntries: _glossary,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
        ElevatedButton.icon(
          onPressed: _openInJournal,
          icon: const Icon(Icons.edit_note, size: 14),
          label: const Text('Open in Journal', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
