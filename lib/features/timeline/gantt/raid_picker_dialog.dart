import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/database.dart';
import '../../../core/search/fuzzy_match.dart';
import '../../../shared/theme/keel_colors.dart';
import '../../journal/menu_scroll_list.dart';
import '../../raid/assumption_form.dart';
import '../../raid/risk_form.dart';

/// One open RAID item as the picker shows it.
class RaidPickItem {
  final String type; // risk | assumption | issue | dependency
  final String id;
  final String ref;
  final String text; // title, else description
  final String detail; // description when a title exists, plus extras
  final String owner;

  const RaidPickItem({
    required this.type,
    required this.id,
    required this.ref,
    required this.text,
    this.detail = '',
    this.owner = '',
  });

  /// Field order matters: the dialog highlights by index.
  /// 0 ref · 1 text · 2 owner · 3 detail · 4 register name.
  List<FuzzyField> get searchFields => [
        FuzzyField(ref, 1.6),
        FuzzyField(text, 1.2),
        FuzzyField(owner, 0.8),
        FuzzyField(detail, 0.7),
        FuzzyField(raidTypeLabel(type), 0.5),
      ];
}

String raidTypeLabel(String type) => switch (type) {
      'risk' => 'Risk',
      'assumption' => 'Assumption',
      'issue' => 'Issue',
      _ => 'Dependency',
    };

/// Ranks [items] for [query] within the [type] filter (null = all).
List<RaidPickItem> rankRaidItems(
  List<RaidPickItem> items,
  String query, {
  String? type,
}) =>
    fuzzyRank(
      type == null ? items : items.where((i) => i.type == type),
      query,
      (i) => i.searchFields,
    );

// ---------------------------------------------------------------------------
// RAID picker — link a plan item's schedule variance to the RAID item
// that drives it. Lists all four registers with a forgiving search
// (refs, words, owners, typos); risks and assumptions — the usual
// variance drivers — can be created inline without losing the form.
// ---------------------------------------------------------------------------

class RaidPickerDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  // Already-linked items — hidden so the same item can't link twice.
  final Set<String> excludeIds;
  // The plan item being linked, shown in the title for context.
  final String? itemName;

  const RaidPickerDialog({
    super.key,
    required this.db,
    required this.projectId,
    this.excludeIds = const {},
    this.itemName,
  });

  @override
  State<RaidPickerDialog> createState() => _RaidPickerDialogState();
}

class _RaidPickerDialogState extends State<RaidPickerDialog> {
  List<RaidPickItem> _items = [];
  bool _loading = true;
  final _query = TextEditingController();
  final _searchFocus = FocusNode();
  String? _type;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() => _selected = 0));
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dao = widget.db.raidDao;
    final risks = await dao.getRisksForProject(widget.projectId);
    final assumptions = await dao.getAssumptionsForProject(widget.projectId);
    final issues = await dao.getIssuesForProject(widget.projectId);
    final deps = await dao.getDependenciesForProject(widget.projectId);
    if (!mounted) return;
    String titled(String? title, String description) =>
        (title != null && title.trim().isNotEmpty) ? title : description;
    String rest(String? title, String description, [List<String?> more = const []]) =>
        [
          if (title != null && title.trim().isNotEmpty) description,
          ...more.whereType<String>().where((s) => s.trim().isNotEmpty),
        ].join(' · ');
    setState(() {
      _items = [
        for (final r in risks.where((r) => r.status != 'closed'))
          RaidPickItem(
            type: 'risk',
            id: r.id,
            ref: r.ref ?? 'Risk',
            text: titled(r.title, r.description),
            detail: rest(r.title, r.description, [r.mitigation]),
            owner: r.owner ?? '',
          ),
        for (final a in assumptions.where((a) => a.status != 'closed'))
          RaidPickItem(
            type: 'assumption',
            id: a.id,
            ref: a.ref ?? 'Assumption',
            text: a.description,
            owner: a.owner ?? '',
          ),
        for (final i in issues.where((i) => i.status != 'closed'))
          RaidPickItem(
            type: 'issue',
            id: i.id,
            ref: i.ref ?? 'Issue',
            text: titled(i.title, i.description),
            detail: rest(i.title, i.description, [i.impactStatement]),
            owner: i.owner ?? '',
          ),
        for (final d in deps.where((d) => d.status != 'closed'))
          RaidPickItem(
            type: 'dependency',
            id: d.id,
            ref: d.ref ?? 'Dep',
            text: d.description,
            detail: [d.counterparty, d.impactStatement]
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .join(' · '),
            owner: d.owner ?? '',
          ),
      ].where((i) => !widget.excludeIds.contains(i.id)).toList();
      _loading = false;
      _selected = 0;
    });
  }

  Future<void> _newRisk() async {
    await showDialog(
      context: context,
      builder: (_) =>
          RiskFormDialog(projectId: widget.projectId, db: widget.db),
    );
    await _load(); // the new risk appears in the list — tap to link it
  }

  Future<void> _newAssumption() async {
    await showDialog(
      context: context,
      builder: (_) =>
          AssumptionFormDialog(projectId: widget.projectId, db: widget.db),
    );
    await _load();
  }

  Color _typeColor(String type) => switch (type) {
        'risk' => KColors.amber,
        'assumption' => KColors.blue,
        'issue' => KColors.red,
        _ => const Color(0xFF8B5CF6),
      };

  void _pick(RaidPickItem item) =>
      Navigator.of(context).pop((type: item.type, id: item.id));

  KeyEventResult _onKey(FocusNode _, KeyEvent e, List<RaidPickItem> shown) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (shown.isEmpty) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % shown.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(() =>
          _selected = (_selected - 1 + shown.length) % shown.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _pick(shown[_selected.clamp(0, shown.length - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final shown = rankRaidItems(_items, _query.text, type: _type);
    final q = _query.text;
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Text(
        widget.itemName == null || widget.itemName!.trim().isEmpty
            ? 'Link a RAID item'
            : 'Link a RAID item to “${widget.itemName!.trim()}”',
        style: TextStyle(color: KColors.text, fontSize: 14),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 560,
        height: 460,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 1.5))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Focus(
                    onKeyEvent: (n, e) => _onKey(n, e, shown),
                    child: TextField(
                      key: const ValueKey('raid-picker-search'),
                      controller: _query,
                      focusNode: _searchFocus,
                      autofocus: true,
                      style: TextStyle(color: KColors.text, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search,
                            size: 16, color: KColors.textMuted),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 32),
                        hintText: 'Search ref, words, owner — typos are fine',
                        hintStyle:
                            TextStyle(color: KColors.textMuted, fontSize: 12),
                        suffixIcon: q.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(Icons.close, size: 14),
                                onPressed: () {
                                  _query.clear();
                                  _searchFocus.requestFocus();
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _typeFilter(),
                  const SizedBox(height: 6),
                  Expanded(child: _results(shown)),
                  const SizedBox(height: 4),
                  Text(
                    '↑ ↓ to move · Enter to link · Esc to cancel',
                    style: TextStyle(color: KColors.textMuted, fontSize: 10),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _newRisk,
          icon: const Icon(Icons.add, size: 13),
          label: const Text('New risk', style: TextStyle(fontSize: 12)),
        ),
        TextButton.icon(
          onPressed: _newAssumption,
          icon: const Icon(Icons.add, size: 13),
          label: const Text('New assumption', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _typeFilter() {
    // Counts follow the search, so the chips say where the matches are.
    int count(String? t) => rankRaidItems(_items, _query.text, type: t).length;
    Widget chip(String? t, String label) {
      final on = _type == t;
      final color = t == null ? KColors.textDim : _typeColor(t);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _type = t;
            _selected = 0;
            _searchFocus.requestFocus();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: on ? color.withValues(alpha: 0.18) : null,
              border: Border.all(
                color: on ? color : KColors.border,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$label ${count(t)}',
              style: TextStyle(
                fontSize: 11,
                color: on ? color : KColors.textDim,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      runSpacing: 4,
      children: [
        chip(null, 'All'),
        chip('risk', 'Risks'),
        chip('assumption', 'Assumptions'),
        chip('issue', 'Issues'),
        chip('dependency', 'Dependencies'),
      ],
    );
  }

  Widget _results(List<RaidPickItem> shown) {
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No open RAID items yet — create one below.',
          style: TextStyle(color: KColors.textDim, fontSize: 12),
        ),
      );
    }
    if (shown.isEmpty) {
      return Center(
        child: Text(
          _query.text.trim().isEmpty
              ? 'Nothing open in this register.'
              : 'Nothing matches “${_query.text.trim()}”. '
                  'Try fewer words, or create it below.',
          textAlign: TextAlign.center,
          style: TextStyle(color: KColors.textDim, fontSize: 12),
        ),
      );
    }
    final sel = _selected.clamp(0, shown.length - 1);
    return MenuScrollList(
      selectedIndex: sel,
      children: [
        for (var i = 0; i < shown.length; i++) _row(shown[i], i == sel),
      ],
    );
  }

  Widget _row(RaidPickItem item, bool selected) {
    final m = fuzzyMatch(_query.text, item.searchFields);
    List<FuzzySpan> spans(int f) => m?.spansFor(f) ?? const [];
    final color = _typeColor(item.type);
    final detailBits = [
      if (item.owner.isNotEmpty) item.owner,
      if (item.detail.isNotEmpty) item.detail,
    ];
    return InkWell(
      onTap: () => _pick(item),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? KColors.blue.withValues(alpha: 0.12) : null,
          border: Border(
            bottom: BorderSide(color: KColors.border, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: _highlighted(
                item.ref,
                spans(0),
                TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlighted(
                    item.text,
                    spans(1),
                    TextStyle(color: KColors.text, fontSize: 12),
                    maxLines: 2,
                  ),
                  if (detailBits.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    // Owner and detail share a line; highlight each part.
                    Text.rich(
                      TextSpan(children: [
                        if (item.owner.isNotEmpty)
                          _spans(item.owner, spans(2), _detailStyle),
                        if (item.owner.isNotEmpty && item.detail.isNotEmpty)
                          TextSpan(text: ' · ', style: _detailStyle),
                        if (item.detail.isNotEmpty)
                          _spans(item.detail, spans(3), _detailStyle),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle get _detailStyle =>
      TextStyle(color: KColors.textMuted, fontSize: 11);

  Widget _highlighted(
    String text,
    List<FuzzySpan> spans,
    TextStyle style, {
    int maxLines = 1,
  }) =>
      Text.rich(
        _spans(text, spans, style),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );

  TextSpan _spans(String text, List<FuzzySpan> spans, TextStyle style) {
    if (spans.isEmpty) return TextSpan(text: text, style: style);
    final hi = style.copyWith(
      fontWeight: FontWeight.w700,
      backgroundColor: KColors.amber.withValues(alpha: 0.22),
    );
    final out = <TextSpan>[];
    var at = 0;
    for (final (s, e) in spans) {
      if (s > at) out.add(TextSpan(text: text.substring(at, s), style: style));
      out.add(TextSpan(text: text.substring(s, e), style: hi));
      at = e;
    }
    if (at < text.length) {
      out.add(TextSpan(text: text.substring(at), style: style));
    }
    return TextSpan(children: out);
  }
}
