import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/database/database.dart';
import '../../core/search/project_search.dart';
import '../../shared/theme/keel_colors.dart';

/// Opens the project-wide find palette and resolves with the chosen hit,
/// or null when dismissed. The caller (the shell) decides what opening a
/// hit means; the palette only finds and returns.
Future<SearchHit?> showSearchPalette(
  BuildContext context, {
  required AppDatabase db,
  required String projectId,
  required bool isProgramme,
}) {
  return showDialog<SearchHit>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => SearchPalette(
      index: ProjectSearchIndex.load(db, projectId, isProgramme: isProgramme),
    ),
  );
}

/// Spotlight-style find: a text box, grouped results, arrows + Enter.
class SearchPalette extends StatefulWidget {
  final Future<ProjectSearchIndex> index;

  /// Rows shown per group before "+N more". The best hit overall is
  /// always shown even when its group is capped.
  final int groupCap;

  const SearchPalette({super.key, required this.index, this.groupCap = 6});

  @override
  State<SearchPalette> createState() => _SearchPaletteState();
}

class _SearchPaletteState extends State<SearchPalette> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  ProjectSearchIndex? _index;
  Object? _loadError;
  List<SearchHit> _ranked = const [];
  List<_Row> _rows = const [];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    widget.index.then((ix) {
      if (!mounted) return;
      setState(() {
        _index = ix;
        _recompute();
      });
    }, onError: (e) {
      if (mounted) setState(() => _loadError = e);
    });
    _ctrl.addListener(() => setState(_recompute));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _recompute() {
    final ix = _index;
    if (ix == null) return;
    _ranked = ix.search(_ctrl.text);
    _rows = _layout(_ranked, _ctrl.text.trim().isNotEmpty);
    // Default selection: the best hit anywhere, not the first group's
    // first row — so "R12, Enter" opens R12 even though sections and
    // people sit above risks.
    final best = _ranked.isEmpty ? null : _ranked.first;
    _selected = best == null
        ? 0
        : _rows.indexWhere((r) => r.hit != null && identical(r.hit, best));
    if (_selected < 0) _selected = _rows.indexWhere((r) => r.hit != null);
    if (_selected < 0) _selected = 0;
  }

  /// Flattens grouped hits into header + item rows with a per-group cap.
  List<_Row> _layout(List<SearchHit> ranked, bool hasQuery) {
    final groups = groupHits(ranked);
    final best = ranked.isEmpty ? null : ranked.first;
    final rows = <_Row>[];
    for (final entry in groups.entries) {
      final hits = entry.value;
      final cap = widget.groupCap;
      var shown = hits.take(cap).toList();
      if (best != null &&
          best.kind == entry.key &&
          !shown.any((h) => identical(h, best))) {
        shown = [best, ...shown.take(cap - 1)];
      }
      final hidden = hits.length - shown.length;
      rows.add(_Row.header(entry.key, hits.length));
      for (final h in shown) {
        rows.add(_Row.hit(h));
      }
      if (hidden > 0) rows.add(_Row.more(hidden));
    }
    return rows;
  }

  void _move(int delta) {
    if (_rows.isEmpty) return;
    var i = _selected;
    for (var step = 0; step < _rows.length; step++) {
      i = (i + delta) % _rows.length;
      if (i < 0) i += _rows.length;
      if (_rows[i].hit != null) break;
    }
    setState(() => _selected = i);
    _ensureVisible(i);
  }

  void _ensureVisible(int i) {
    if (!_scroll.hasClients) return;
    final target = (i * _Row.height) - 120;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
    );
  }

  void _choose([SearchHit? hit]) {
    final h = hit ??
        (_selected >= 0 && _selected < _rows.length
            ? _rows[_selected].hit
            : null);
    if (h == null) return;
    Navigator.of(context).pop(h);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      _choose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _ctrl.text.trim().isNotEmpty;
    final itemCount = _ranked.where((h) => h.kind != SearchKind.section).length;
    return Dialog(
      alignment: const Alignment(0, -0.6),
      backgroundColor: KColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: KColors.border),
      ),
      child: Focus(
        onKeyEvent: _onKey,
        child: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Find a person, risk, action, section…',
                    hintStyle:
                        TextStyle(color: KColors.textMuted, fontSize: 16),
                    prefixIcon: Icon(Icons.search, color: KColors.textDim),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const Divider(height: 1, color: KColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  _loadError != null
                      ? 'Search failed: $_loadError'
                      : _index == null
                          ? 'Loading…'
                          : !hasQuery
                              ? 'Type to search this project. ↑↓ to move, Enter to open, Esc to close.'
                              : itemCount == 0
                                  ? 'Nothing in this project matches "${_ctrl.text.trim()}".'
                                  : '$itemCount ${itemCount == 1 ? 'item' : 'items'} match.',
                  style: TextStyle(
                    fontSize: 11,
                    color: _loadError != null ? KColors.red : KColors.textDim,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 440),
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                  itemCount: _rows.length,
                  itemExtent: _Row.height,
                  itemBuilder: (ctx, i) {
                    final row = _rows[i];
                    if (row.hit == null) {
                      return _HeaderOrMore(row: row);
                    }
                    return _HitRow(
                      hit: row.hit!,
                      selected: i == _selected,
                      onTap: () => _choose(row.hit),
                      onHover: () {
                        if (_selected != i) setState(() => _selected = i);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row {
  static const double height = 40;
  final SearchHit? hit;
  final SearchKind? headerKind;
  final int count;

  const _Row._({this.hit, this.headerKind, this.count = 0});
  factory _Row.hit(SearchHit h) => _Row._(hit: h);
  factory _Row.header(SearchKind k, int total) =>
      _Row._(headerKind: k, count: total);
  factory _Row.more(int hidden) => _Row._(count: hidden);
}

class _HeaderOrMore extends StatelessWidget {
  final _Row row;
  const _HeaderOrMore({required this.row});

  @override
  Widget build(BuildContext context) {
    if (row.headerKind != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
        child: Text(
          '${row.headerKind!.label.toUpperCase()}  ·  ${row.count}',
          style: const TextStyle(
            color: KColors.amber,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Text(
        '+${row.count} more — keep typing to narrow',
        style: const TextStyle(color: KColors.textMuted, fontSize: 11),
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  final SearchHit hit;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _HitRow({
    required this.hit,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? KColors.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(iconForKind(hit.kind),
                  size: 16,
                  color: selected ? KColors.amber : KColors.textDim),
              const SizedBox(width: 10),
              if ((hit.ref ?? '').isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: KColors.bg,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: KColors.border2, width: 0.5),
                  ),
                  child: Text(hit.ref!,
                      style: const TextStyle(
                          fontSize: 10,
                          color: KColors.textDim,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  hit.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if ((hit.subtitle ?? '').isNotEmpty) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    hit.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: KColors.textMuted),
                  ),
                ),
              ],
              if (selected) ...[
                const SizedBox(width: 10),
                const Icon(Icons.keyboard_return,
                    size: 14, color: KColors.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

IconData iconForKind(SearchKind kind) => switch (kind) {
      SearchKind.section => Icons.arrow_forward,
      SearchKind.person => Icons.person_outline,
      SearchKind.risk => Icons.warning_amber_outlined,
      SearchKind.issue => Icons.error_outline,
      SearchKind.assumption => Icons.help_outline,
      SearchKind.dependency => Icons.link_outlined,
      SearchKind.action => Icons.task_alt_outlined,
      SearchKind.decision => Icons.gavel_outlined,
      SearchKind.milestone => Icons.flag_outlined,
      SearchKind.planActivity => Icons.view_timeline_outlined,
      SearchKind.workstream => Icons.account_tree_outlined,
      SearchKind.glossary => Icons.menu_book_outlined,
    };
