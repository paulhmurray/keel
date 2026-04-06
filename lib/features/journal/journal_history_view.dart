import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import 'journal_entry_card.dart';
import 'journal_overlay.dart';

class JournalHistoryView extends StatefulWidget {
  const JournalHistoryView({super.key});

  @override
  State<JournalHistoryView> createState() => _JournalHistoryViewState();
}

class _JournalHistoryViewState extends State<JournalHistoryView> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openNewEntry(BuildContext context) {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    final db = context.read<AppDatabase>();
    final settings = context.read<SettingsProvider>().settings;
    if (projectId == null) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      pageBuilder: (_, __, ___) => JournalOverlay(
        projectId: projectId,
        db: db,
        settings: settings,
      ),
    );
  }

  void _openEntry(BuildContext context, JournalEntry entry) {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    final db = context.read<AppDatabase>();
    final settings = context.read<SettingsProvider>().settings;
    if (projectId == null) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      pageBuilder: (_, __, ___) => JournalOverlay(
        projectId: projectId,
        db: db,
        settings: settings,
        existingEntry: entry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(
          child: Text('Select a project to view the journal.',
              style: TextStyle(color: KColors.textDim)));
    }
    final db = context.read<AppDatabase>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_outlined, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('JOURNAL',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _openNewEntry(context),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('New Entry'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Search
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search entries...',
              hintStyle: const TextStyle(color: KColors.textMuted, fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 14, color: KColors.textDim),
              filled: true,
              fillColor: KColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: KColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: KColors.border),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            style: const TextStyle(color: KColors.text, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<JournalEntry>>(
              stream: db.journalDao.watchEntriesForProject(projectId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var entries = snap.data!;
                if (_searchQuery.isNotEmpty) {
                  entries = entries.where((e) {
                    final body = e.body.toLowerCase();
                    final title = (e.title ?? '').toLowerCase();
                    return body.contains(_searchQuery) ||
                        title.contains(_searchQuery);
                  }).toList();
                }
                if (entries.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_outlined,
                            size: 40, color: KColors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No journal entries yet.'
                              : 'No entries match "$_searchQuery".',
                          style: const TextStyle(color: KColors.textDim),
                        ),
                        if (_searchQuery.isEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Press Cmd+J anywhere to open a new entry.',
                            style: TextStyle(
                                color: KColors.textMuted, fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => _openNewEntry(context),
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('New Entry'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final entry = entries[i];
                    return FutureBuilder<List<JournalEntryLink>>(
                      future: db.journalDao.getLinksForEntry(entry.id),
                      builder: (ctx, linkSnap) {
                        return JournalEntryCard(
                          entry: entry,
                          linkCount: linkSnap.data?.length ?? 0,
                          onTap: () => _openEntry(context, entry),
                          onDelete: () async {
                            await db.journalDao.deleteLinksForEntry(entry.id);
                            await db.journalDao.deleteEntry(entry.id);
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
