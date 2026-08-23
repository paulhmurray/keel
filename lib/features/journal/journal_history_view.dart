import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import 'journal_entry_card.dart';
import 'journal_overlay.dart';
import 'journal_series_form.dart';

class JournalHistoryView extends StatefulWidget {
  /// When provided, "+ New Entry" opens the shell's docked journal pane
  /// (split view) instead of the modal quick-capture overlay.
  final VoidCallback? onNewEntryDocked;

  /// When provided, clicking an existing entry opens it in the docked
  /// split view instead of the modal overlay.
  final void Function(JournalEntry entry)? onOpenEntryDocked;

  const JournalHistoryView(
      {super.key, this.onNewEntryDocked, this.onOpenEntryDocked});

  @override
  State<JournalHistoryView> createState() => _JournalHistoryViewState();
}

class _JournalHistoryViewState extends State<JournalHistoryView> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _pinnedExpanded = true;
  // null = all entries; otherwise filter to this series.
  String? _seriesFilter;

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

  void _openNewEntry(BuildContext context, {String? seriesId}) {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    final db = context.read<AppDatabase>();
    final settings = context.read<SettingsProvider>().settings;
    if (projectId == null) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      pageBuilder: (_, _, _) => JournalOverlay(
        projectId: projectId,
        db: db,
        settings: settings,
        initialSeriesId: seriesId,
      ),
    );
  }

  void _openEntry(BuildContext context, JournalEntry entry) {
    if (widget.onOpenEntryDocked != null) {
      widget.onOpenEntryDocked!(entry);
      return;
    }
    final projectId = context.read<ProjectProvider>().currentProjectId;
    final db = context.read<AppDatabase>();
    final settings = context.read<SettingsProvider>().settings;
    if (projectId == null) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      pageBuilder: (_, _, _) => JournalOverlay(
        projectId: projectId,
        db: db,
        settings: settings,
        existingEntry: entry,
      ),
    );
  }

  Future<void> _newSeries(BuildContext context) async {
    final projectId = context.read<ProjectProvider>().currentProjectId;
    final db = context.read<AppDatabase>();
    if (projectId == null) return;
    await showDialog(
      context: context,
      builder: (_) => JournalSeriesFormDialog(projectId: projectId, db: db),
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
              const Icon(Icons.menu_book_outlined,
                  color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('JOURNAL',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => widget.onNewEntryDocked != null
                    ? widget.onNewEntryDocked!()
                    : _openNewEntry(context),
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
              hintStyle:
                  const TextStyle(color: KColors.textMuted, fontSize: 12),
              prefixIcon: const Icon(Icons.search,
                  size: 14, color: KColors.textDim),
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
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<JournalSeries>>(
              stream: db.journalSeriesDao.watchForProject(projectId),
              builder: (context, seriesSnap) {
                final allSeries = seriesSnap.data ?? const <JournalSeries>[];
                final seriesById = {for (final s in allSeries) s.id: s};
                return StreamBuilder<List<JournalEntry>>(
                  stream: db.journalDao.watchEntriesForProject(projectId),
                  builder: (context, entrySnap) {
                    if (!entrySnap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final all = entrySnap.data!;
                    return _buildBody(
                      context: context,
                      projectId: projectId,
                      db: db,
                      allEntries: all,
                      allSeries: allSeries,
                      seriesById: seriesById,
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

  Widget _buildBody({
    required BuildContext context,
    required String projectId,
    required AppDatabase db,
    required List<JournalEntry> allEntries,
    required List<JournalSeries> allSeries,
    required Map<String, JournalSeries> seriesById,
  }) {
    final scoped = _seriesFilter == null
        ? allEntries
        : allEntries.where((e) => e.seriesId == _seriesFilter).toList();

    final searched = _searchQuery.isEmpty
        ? scoped
        : scoped.where((e) {
            final body = e.body.toLowerCase();
            final title = (e.title ?? '').toLowerCase();
            return body.contains(_searchQuery) ||
                title.contains(_searchQuery);
          }).toList();

    final favouriteCount = allEntries.where((e) => e.isFavourite).length;
    final showPinned = _seriesFilter == null &&
        _searchQuery.isEmpty &&
        (favouriteCount > 0 || allSeries.isNotEmpty);

    return ListView(
      children: [
        if (showPinned)
          _PinnedSection(
            entries: allEntries.where((e) => e.isFavourite).toList(),
            series: allSeries,
            entriesBySeriesId: _groupBySeries(allEntries),
            seriesById: seriesById,
            expanded: _pinnedExpanded,
            onToggleExpanded: () =>
                setState(() => _pinnedExpanded = !_pinnedExpanded),
            onOpenEntry: (e) => _openEntry(context, e),
            onToggleFav: (e) =>
                db.journalDao.toggleFavourite(e.id, !e.isFavourite),
            onSelectSeries: (id) => setState(() => _seriesFilter = id),
            onNewSeries: () => _newSeries(context),
          ),
        if (_seriesFilter != null) ...[
          _SeriesFilterBanner(
            series: seriesById[_seriesFilter!],
            onClear: () => setState(() => _seriesFilter = null),
            onAddEntry: () =>
                _openNewEntry(context, seriesId: _seriesFilter),
          ),
          const SizedBox(height: 8),
        ],
        if (searched.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_outlined,
                      size: 40, color: KColors.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    _seriesFilter != null
                        ? 'No entries in this series yet.'
                        : _searchQuery.isEmpty
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
                      onPressed: () => _openNewEntry(context,
                          seriesId: _seriesFilter),
                      icon: const Icon(Icons.add, size: 14),
                      label: Text(_seriesFilter == null
                          ? 'New Entry'
                          : 'New Entry in Series'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        for (final entry in searched) ...[
          FutureBuilder<List<JournalEntryLink>>(
            future: db.journalDao.getLinksForEntry(entry.id),
            builder: (ctx, linkSnap) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: JournalEntryCard(
                  entry: entry,
                  linkCount: linkSnap.data?.length ?? 0,
                  seriesName: entry.seriesId != null
                      ? seriesById[entry.seriesId!]?.name
                      : null,
                  onTap: () => _openEntry(context, entry),
                  onToggleFavourite: () => db.journalDao
                      .toggleFavourite(entry.id, !entry.isFavourite),
                  onDelete: () async {
                    await db.journalDao.deleteLinksForEntry(entry.id);
                    await db.journalDao.deleteEntry(entry.id);
                  },
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Map<String, List<JournalEntry>> _groupBySeries(
      List<JournalEntry> entries) {
    final out = <String, List<JournalEntry>>{};
    for (final e in entries) {
      final sid = e.seriesId;
      if (sid != null) out.putIfAbsent(sid, () => []).add(e);
    }
    return out;
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Pinned section — starred entries + series cards, all in one strip.
// ───────────────────────────────────────────────────────────────────────────

class _PinnedSection extends StatelessWidget {
  final List<JournalEntry> entries;
  final List<JournalSeries> series;
  final Map<String, List<JournalEntry>> entriesBySeriesId;
  final Map<String, JournalSeries> seriesById;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final void Function(JournalEntry) onOpenEntry;
  final void Function(JournalEntry) onToggleFav;
  final void Function(String seriesId) onSelectSeries;
  final VoidCallback onNewSeries;

  const _PinnedSection({
    required this.entries,
    required this.series,
    required this.entriesBySeriesId,
    required this.seriesById,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onOpenEntry,
    required this.onToggleFav,
    required this.onSelectSeries,
    required this.onNewSeries,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: KColors.amber,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'PINNED',
                    style: TextStyle(
                      color: KColors.amber,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.15,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entries.length} starred · ${series.length} series',
                    style: const TextStyle(
                        color: KColors.textMuted, fontSize: 10),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onNewSeries,
                    icon: const Icon(Icons.add, size: 12),
                    label: const Text('Series'),
                    style: TextButton.styleFrom(
                      foregroundColor: KColors.textDim,
                      textStyle: const TextStyle(fontSize: 11),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(color: KColors.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (series.isNotEmpty) ...[
                    const Text('SERIES',
                        style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.15,
                        )),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in series)
                          _SeriesCard(
                            series: s,
                            entryCount:
                                entriesBySeriesId[s.id]?.length ?? 0,
                            latestEntry: (entriesBySeriesId[s.id] ?? const [])
                                    .isNotEmpty
                                ? entriesBySeriesId[s.id]!.reduce((a, b) =>
                                    a.entryDate.compareTo(b.entryDate) > 0
                                        ? a
                                        : b)
                                : null,
                            onTap: () => onSelectSeries(s.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (entries.isNotEmpty) ...[
                    const Text('STARRED',
                        style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.15,
                        )),
                    const SizedBox(height: 6),
                    for (final e in entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: JournalEntryCard(
                          entry: e,
                          linkCount: 0,
                          seriesName: e.seriesId != null
                              ? seriesById[e.seriesId!]?.name
                              : null,
                          onTap: () => onOpenEntry(e),
                          onToggleFavourite: () => onToggleFav(e),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  final JournalSeries series;
  final int entryCount;
  final JournalEntry? latestEntry;
  final VoidCallback onTap;

  const _SeriesCard({
    required this.series,
    required this.entryCount,
    required this.latestEntry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = series.color != null && series.color!.isNotEmpty
        ? _parseHex(series.color!) ?? KColors.blue
        : KColors.blue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 200,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.border2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.repeat, size: 11, color: KColors.blue),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    series.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              series.cadenceHint == null
                  ? '$entryCount entr${entryCount == 1 ? 'y' : 'ies'}'
                  : '${series.cadenceHint!} · $entryCount entr${entryCount == 1 ? 'y' : 'ies'}',
              style: const TextStyle(
                color: KColors.textDim,
                fontSize: 10,
              ),
            ),
            if (latestEntry != null) ...[
              const SizedBox(height: 2),
              Text(
                'last: ${latestEntry!.entryDate}',
                style: const TextStyle(
                    color: KColors.textMuted, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color? _parseHex(String hex) {
    var s = hex.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    return Color(int.parse(s, radix: 16));
  }
}

class _SeriesFilterBanner extends StatelessWidget {
  final JournalSeries? series;
  final VoidCallback onClear;
  final VoidCallback onAddEntry;

  const _SeriesFilterBanner({
    required this.series,
    required this.onClear,
    required this.onAddEntry,
  });

  @override
  Widget build(BuildContext context) {
    final name = series?.name ?? '(unknown series)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Back link — sits above the banner, like a browser back button.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to all notes'),
            style: TextButton.styleFrom(
              foregroundColor: KColors.textDim,
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: KColors.blueDim,
            border: Border.all(color: KColors.blue.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              const Icon(Icons.repeat, size: 13, color: KColors.blue),
              const SizedBox(width: 6),
              const Text('Filtering by series · ',
                  style: TextStyle(color: KColors.textDim, fontSize: 11)),
              // Expanded — not Flexible — so the name consumes all the
              // leftover space and the buttons sit flush against the
              // banner's right edge. Flexible+Spacer was claiming the
              // leftover 50/50 and parking the buttons in the middle.
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: KColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onAddEntry,
                icon: const Icon(Icons.add, size: 12),
                label: const Text('New in series'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 11),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Clear filter',
                child: InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(3),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 14, color: KColors.textDim),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
