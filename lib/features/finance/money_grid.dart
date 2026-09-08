import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';

/// One grid cell's worth of data, decoupled from which table it lives
/// in: budget lines, forecast lines, and actuals all render through
/// the same grid — only the column key differs (FY vs month).
class MoneyCell {
  final String id;
  final String categoryId;
  final String? workstreamId;
  final String columnKey;
  final int amountMinor;
  final String? notes;

  const MoneyCell({
    required this.id,
    required this.categoryId,
    required this.workstreamId,
    required this.columnKey,
    required this.amountMinor,
    this.notes,
  });
}

typedef MoneyCommit = Future<void> Function({
  required MoneyCell? existing,
  required String categoryId,
  required String? workstreamId,
  required String columnKey,
  required int amountMinor,
});

typedef MoneyDelete = Future<void> Function(List<MoneyCell> cells);

typedef MoneyDetail = Future<void> Function(
    String categoryId, String? workstreamId, String columnKey,
    MoneyCell? cell);

/// The Excel-feel finance grid. Rows are category × optional-workstream;
/// columns are arbitrary keys (financial years for budget/forecast,
/// months for actuals). Click a cell and type — Enter commits and moves
/// down, Tab commits and moves right, Esc cancels, empty clears. A
/// pristine editor commits as a pure no-op so navigating never deletes.
class MoneyGrid extends StatefulWidget {
  final Stream<List<MoneyCell>> cells;
  final List<CostCategory> categories;
  final List<TimelineWorkPackage> workPackages;
  final String currency;
  final bool readOnly;

  /// 'Financial Year' or 'Month' — used by the add-column dialog.
  final String columnNoun;
  final String columnHint;
  final String defaultColumnKey;

  final MoneyCommit onCommit;
  final MoneyDelete onDelete;

  /// Secondary-tap/long-press handler (notes, workstream, etc.). Cells
  /// simply don't respond when null.
  final MoneyDetail? onDetail;

  /// Called when the user taps a cell on a read-only grid — lets the
  /// parent offer the edit path instead of dead silence.
  final VoidCallback? onReadOnlyTap;

  const MoneyGrid({
    super.key,
    required this.cells,
    required this.categories,
    required this.workPackages,
    required this.currency,
    required this.readOnly,
    required this.columnNoun,
    required this.columnHint,
    required this.defaultColumnKey,
    required this.onCommit,
    required this.onDelete,
    this.onDetail,
    this.onReadOnlyTap,
  });

  @override
  State<MoneyGrid> createState() => _MoneyGridState();
}

const _labelMinW = 250.0;
const _colW = 120.0;
const _totalW = 130.0;
const _trailW = 36.0;

enum _Move { right, down, none }

class _MoneyGridState extends State<MoneyGrid> {
  /// Rows added this session with no committed cells yet, keyed
  /// "categoryId|workstreamId" (empty ws = no workstream).
  final Set<String> _pendingRows = {};

  /// Columns added this session with no cells yet.
  final Set<String> _pendingCols = {};

  /// The cell currently being edited: "rowKey|columnKey". Null = none.
  String? _editingCell;
  final TextEditingController _cellCtrl = TextEditingController();
  bool _cellInvalid = false;

  /// False until the user actually types. Committing a pristine editor
  /// is a pure no-op move — otherwise Enter-ing through cells after an
  /// advance (which starts the editor empty) would delete their cells.
  bool _cellDirty = false;

  @override
  void dispose() {
    _cellCtrl.dispose();
    super.dispose();
  }

  String _rowKey(String catId, String? wsId) => '$catId|${wsId ?? ''}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MoneyCell>>(
      stream: widget.cells,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cells = snap.data!;

        final cols = <String>{
          for (final c in cells) c.columnKey,
          ..._pendingCols,
        }.toList()
          ..sort();
        if (cols.isEmpty) cols.add(widget.defaultColumnKey);

        // Rows grouped per category: no-workstream row first, then
        // workstream rows in work-package order, then pending rows.
        final wpOrder = {
          for (var i = 0; i < widget.workPackages.length; i++)
            widget.workPackages[i].id: i,
        };
        final cellsByKey = <String, List<MoneyCell>>{};
        final rowKeysByCat = <String, List<String>>{};
        for (final c in cells) {
          final rk = _rowKey(c.categoryId, c.workstreamId);
          cellsByKey.putIfAbsent('$rk|${c.columnKey}', () => []).add(c);
          final catRows = rowKeysByCat.putIfAbsent(c.categoryId, () => []);
          if (!catRows.contains(rk)) catRows.add(rk);
        }
        for (final rk in _pendingRows) {
          final catId = rk.split('|').first;
          final catRows = rowKeysByCat.putIfAbsent(catId, () => []);
          if (!catRows.contains(rk)) catRows.add(rk);
        }
        for (final rows in rowKeysByCat.values) {
          rows.sort((a, b) {
            final wsA = a.split('|').last;
            final wsB = b.split('|').last;
            if (wsA.isEmpty != wsB.isEmpty) return wsA.isEmpty ? -1 : 1;
            return (wpOrder[wsA] ?? 999).compareTo(wpOrder[wsB] ?? 999);
          });
        }
        final flatRows = <String>[
          for (final cat in widget.categories) ...?rowKeysByCat[cat.id],
        ];

        var grandTotal = 0;
        final byCat = <String, int>{};
        final byCol = <String, int>{};
        for (final c in cells) {
          grandTotal += c.amountMinor;
          byCat[c.categoryId] = (byCat[c.categoryId] ?? 0) + c.amountMinor;
          byCol[c.columnKey] = (byCol[c.columnKey] ?? 0) + c.amountMinor;
        }

        // Fill the width the surrounding panels get: fixed data columns,
        // label column absorbs any surplus. Falls back to horizontal
        // scrolling when the columns genuinely overflow.
        return LayoutBuilder(builder: (context, constraints) {
          final fixedW = cols.length * _colW + _totalW + _trailW;
          final availW = constraints.maxWidth - 2; // container border
          final labelW = (availW - fixedW) > _labelMinW
              ? availW - fixedW
              : _labelMinW;
          final gridW = labelW + fixedW;

          return SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                decoration: BoxDecoration(
                  color: KColors.surface,
                  border: Border.all(color: KColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SizedBox(
                  width: gridW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _headerRow(cols, labelW),
                      for (final cat in widget.categories)
                        if ((rowKeysByCat[cat.id]?.isNotEmpty ?? false) ||
                            !widget.readOnly) ...[
                          _categoryHeaderRow(cat, cols, byCat, labelW),
                          for (final rk in rowKeysByCat[cat.id] ?? const [])
                            _dataRow(rk, cat, cols, cellsByKey, flatRows,
                                labelW),
                        ],
                      _totalsRow(cols, byCol, grandTotal, labelW),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
  }

  // ── Rows ──────────────────────────────────────────────────────────────

  Widget _headerRow(List<String> cols, double labelW) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: labelW),
          for (final col in cols)
            SizedBox(
              width: _colW,
              child: Text(col,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: KColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
            ),
          const SizedBox(
            width: _totalW,
            child: Text('TOTAL',
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
          ),
          SizedBox(
            width: _trailW,
            child: widget.readOnly
                ? null
                : Tooltip(
                    message: 'Add ${widget.columnNoun.toLowerCase()} column',
                    child: InkWell(
                      onTap: _addColumn,
                      child: const Icon(Icons.add,
                          size: 14, color: KColors.textMuted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _categoryHeaderRow(CostCategory cat, List<String> cols,
      Map<String, int> byCat, double labelW) {
    return Container(
      color: KColors.surface2,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: labelW,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Text(cat.name.toUpperCase(),
                      style: const TextStyle(
                          color: KColors.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                  if (!widget.readOnly) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Add row',
                      child: InkWell(
                        onTap: () => _addRow(cat),
                        child: const Icon(Icons.add_circle_outline,
                            size: 13, color: KColors.textMuted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(width: cols.length * _colW),
          SizedBox(
            width: _totalW,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                Money.formatMinorCompact(
                    byCat[cat.id] ?? 0, widget.currency),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: KColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: _trailW),
        ],
      ),
    );
  }

  Widget _dataRow(String rowKey, CostCategory cat, List<String> cols,
      Map<String, List<MoneyCell>> cellsByKey, List<String> flatRows,
      double labelW) {
    final wsId = rowKey.split('|').last;
    final wsName = wsId.isEmpty
        ? null
        : widget.workPackages
                .where((wp) => wp.id == wsId)
                .map((wp) => wp.name)
                .firstOrNull ??
            'Unknown workstream';
    var rowTotal = 0;
    for (final col in cols) {
      for (final c in cellsByKey['$rowKey|$col'] ?? const <MoneyCell>[]) {
        rowTotal += c.amountMinor;
      }
    }

    return Container(
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: KColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: labelW,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: wsName == null
                  ? const Text('General',
                      style:
                          TextStyle(color: KColors.textMuted, fontSize: 11))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.table_chart_outlined,
                            size: 11, color: KColors.textDim),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(wsName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: KColors.textDim, fontSize: 11)),
                        ),
                      ],
                    ),
            ),
          ),
          for (final col in cols)
            _cell(rowKey, cat, col,
                cellsByKey['$rowKey|$col'] ?? const [], cols, flatRows),
          SizedBox(
            width: _totalW,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                rowTotal == 0
                    ? '—'
                    : Money.formatMinorCompact(rowTotal, widget.currency),
                textAlign: TextAlign.right,
                style: const TextStyle(color: KColors.text, fontSize: 12),
              ),
            ),
          ),
          SizedBox(
            width: _trailW,
            child: widget.readOnly
                ? null
                : Tooltip(
                    message: 'Delete row',
                    child: InkWell(
                      onTap: () => _deleteRow(rowKey, cols, cellsByKey),
                      child: const Icon(Icons.close,
                          size: 12, color: KColors.textMuted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _totalsRow(List<String> cols, Map<String, int> byCol,
      int grandTotal, double labelW) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: KColors.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: labelW,
            child: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text('TOTAL',
                  style: TextStyle(
                      color: KColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
          ),
          for (final col in cols)
            SizedBox(
              width: _colW,
              child: Text(
                Money.formatMinorCompact(byCol[col] ?? 0, widget.currency),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: KColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          SizedBox(
            width: _totalW,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                Money.formatMinorCompact(grandTotal, widget.currency),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: _trailW),
        ],
      ),
    );
  }

  // ── Cells ─────────────────────────────────────────────────────────────

  Widget _cell(String rowKey, CostCategory cat, String col,
      List<MoneyCell> cells, List<String> cols, List<String> flatRows) {
    final cellKey = '$rowKey|$col';
    final sum = cells.fold<int>(0, (s, c) => s + c.amountMinor);
    final display = cells.isEmpty ? '' : Money.formatMinorPlain(sum);
    final notes = cells
        .map((c) => c.notes)
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .join(' · ');

    if (_editingCell == cellKey && !widget.readOnly) {
      return SizedBox(
        width: _colW,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.tab) {
              _commitCell(rowKey, cat, col, cells, cols, flatRows,
                  move: _Move.right);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(() {
                _editingCell = null;
                _cellInvalid = false;
              });
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: ValueKey('edit-$cellKey'),
            controller: _cellCtrl,
            autofocus: true,
            textAlign: TextAlign.right,
            style: const TextStyle(color: KColors.text, fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                    color: _cellInvalid ? KColors.red : KColors.amber),
                borderRadius: BorderRadius.circular(2),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                    color: _cellInvalid ? KColors.red : KColors.amber),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            onChanged: (_) => _cellDirty = true,
            onSubmitted: (_) => _commitCell(
                rowKey, cat, col, cells, cols, flatRows,
                move: _Move.down),
            onTapOutside: (_) => _commitCell(
                rowKey, cat, col, cells, cols, flatRows,
                move: _Move.none),
          ),
        ),
      );
    }

    final text = Text(
      display.isEmpty ? '—' : display,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: display.isEmpty ? KColors.textMuted : KColors.text,
        fontSize: 12,
      ),
    );
    final detail = widget.onDetail;
    return SizedBox(
      width: _colW,
      child: InkWell(
        key: ValueKey('cell-$cellKey'),
        onTap: widget.readOnly
            ? widget.onReadOnlyTap
            : () => _startEdit(cellKey, sum, cells),
        onSecondaryTap: widget.readOnly || detail == null
            ? null
            : () => detail(cat.id, rowKey.split('|').last.isEmpty ? null : rowKey.split('|').last, col, cells.firstOrNull),
        onLongPress: widget.readOnly || detail == null
            ? null
            : () => detail(cat.id, rowKey.split('|').last.isEmpty ? null : rowKey.split('|').last, col, cells.firstOrNull),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: notes.isEmpty ? text : Tooltip(message: notes, child: text),
        ),
      ),
    );
  }

  void _startEdit(String cellKey, int sum, List<MoneyCell> cells) {
    setState(() {
      _editingCell = cellKey;
      _cellInvalid = false;
      _cellDirty = false;
      _cellCtrl.text = cells.isEmpty ? '' : Money.formatMinorPlain(sum);
      _cellCtrl.selection = TextSelection(
          baseOffset: 0, extentOffset: _cellCtrl.text.length);
    });
  }

  Future<void> _commitCell(String rowKey, CostCategory cat, String col,
      List<MoneyCell> cells, List<String> cols, List<String> flatRows,
      {required _Move move}) async {
    if (_editingCell != '$rowKey|$col') return; // stale focus callback
    final text = _cellCtrl.text.trim();
    final minor = text.isEmpty ? null : Money.parseToMinor(text);
    if (text.isNotEmpty && minor == null) {
      setState(() => _cellInvalid = true);
      return;
    }
    final wsId = rowKey.split('|').last;
    if (!_cellDirty) {
      // Pristine editor — pure navigation, write nothing.
    } else if (minor == null) {
      await widget.onDelete(cells);
    } else {
      await widget.onCommit(
        existing: cells.firstOrNull,
        categoryId: cat.id,
        workstreamId: wsId.isEmpty ? null : wsId,
        columnKey: col,
        amountMinor: minor,
      );
    }
    if (!mounted) return;

    // Advance Excel-style: Tab → next column, Enter → same column next
    // row. Falls off the edge → stop editing.
    String? next;
    if (move == _Move.right) {
      final i = cols.indexOf(col);
      if (i >= 0 && i + 1 < cols.length) next = '$rowKey|${cols[i + 1]}';
    } else if (move == _Move.down) {
      final r = flatRows.indexOf(rowKey);
      if (r >= 0 && r + 1 < flatRows.length) {
        next = '${flatRows[r + 1]}|$col';
      }
    }
    setState(() {
      _editingCell = next;
      _cellInvalid = false;
      _cellDirty = false;
      // Advanced cells start empty (type-over, like Excel); committing
      // without typing is a no-op thanks to the pristine guard.
      if (next != null) _cellCtrl.text = '';
    });
  }

  // ── Row / column actions ─────────────────────────────────────────────

  Future<void> _addRow(CostCategory cat) async {
    final wsId = await showDialog<String?>(
      context: context,
      builder: (_) => _AddRowDialog(workPackages: widget.workPackages),
    );
    // The dialog returns '' for "no workstream"; null = cancelled.
    if (wsId == null) return;
    setState(() =>
        _pendingRows.add(_rowKey(cat.id, wsId.isEmpty ? null : wsId)));
  }

  Future<void> _deleteRow(String rowKey, List<String> cols,
      Map<String, List<MoneyCell>> cellsByKey) async {
    final all = <MoneyCell>[
      for (final col in cols)
        ...cellsByKey['$rowKey|$col'] ?? const <MoneyCell>[],
    ];
    if (all.isNotEmpty) await widget.onDelete(all);
    setState(() => _pendingRows.remove(rowKey));
  }

  Future<void> _addColumn() async {
    final ctrl = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${widget.columnNoun}'),
        content: SizedBox(
          width: 260,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
                labelText: widget.columnNoun,
                hintText: widget.columnHint),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (key != null && key.isNotEmpty) {
      setState(() => _pendingCols.add(key));
    }
  }
}

/// Pick the workstream (or none) for a new grid row.
class _AddRowDialog extends StatelessWidget {
  final List<TimelineWorkPackage> workPackages;

  const _AddRowDialog({required this.workPackages});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Row'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.remove, size: 16),
              title: const Text('No workstream (General)',
                  style: TextStyle(fontSize: 13)),
              onTap: () => Navigator.of(context).pop(''),
            ),
            for (final wp in workPackages)
              ListTile(
                dense: true,
                leading: const Icon(Icons.table_chart_outlined, size: 16),
                title: Text(wp.name, style: const TextStyle(fontSize: 13)),
                onTap: () => Navigator.of(context).pop(wp.id),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
