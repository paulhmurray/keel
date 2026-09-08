import 'dart:convert';
import 'package:excel/excel.dart';

import '../database/database.dart';
import '../plan/variance_links.dart';
import '../platform/web_download.dart';
import 'excel_palette.dart';

// The workbook is styled for EXCEL, not for Keel: white ground, dark ink,
// light status tints. The whole point of the export is that a PM can
// generate it and send it on Teams in seconds, and whoever opens it on
// another machine can read every cell with zero touch-up. Do not
// reintroduce Keel's dark-theme colours here — that is exactly the bug
// this file used to have (near-white text on Excel's white ground).

// WP theme colours (solid band fills; text colour is picked by luminance)
const _kWpColors = {
  'wp1':        'FF3B82F6',
  'wp2':        'FF10B981',
  'wp3':        'FF8B5CF6',
  'wp4':        'FFF59E0B',
  'mpower':     'FF06B6D4',
  'governance': 'FF6B7280',
};

String _wpHex(String theme) => _kWpColors[theme] ?? 'FF64748B';

// ─── Helper: build a CellStyle ────────────────────────────────────────────────
CellStyle _style({
  String? bgHex,
  String fgHex  = kXlInk,
  bool bold      = false,
  bool italic    = false,
  int  fontSize  = 10,
  HorizontalAlign halign = HorizontalAlign.Left,
  VerticalAlign   valign = VerticalAlign.Center,
  bool wrap      = false,
  bool allBorders = false,
}) {
  assert(bgHex == null || bgHex != fgHex,
      'fg == bg renders an invisible cell');
  final border = allBorders
      ? Border(
          borderStyle: BorderStyle.Thin,
          borderColorHex: ExcelColor.fromHexString('#$kXlBorder'),
        )
      : null;

  return CellStyle(
    backgroundColorHex: bgHex != null
        ? ExcelColor.fromHexString('#$bgHex')
        : ExcelColor.none,
    fontColorHex: ExcelColor.fromHexString('#$fgHex'),
    bold: bold,
    italic: italic,
    fontSize: fontSize,
    horizontalAlign: halign,
    verticalAlign: valign,
    textWrapping: wrap ? TextWrapping.WrapText : TextWrapping.Clip,
    topBorder: border,
    bottomBorder: border,
    leftBorder: border,
    rightBorder: border,
  );
}

void _setCell(
  Sheet sheet,
  int row,
  int col,
  dynamic value, {
  CellStyle? style,
}) {
  final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
  if (value is String) {
    cell.value = TextCellValue(value);
  } else if (value is int) {
    cell.value = IntCellValue(value);
  } else if (value is double) {
    cell.value = DoubleCellValue(value);
  } else {
    cell.value = TextCellValue(value?.toString() ?? '');
  }
  if (style != null) cell.cellStyle = style;
}

// ─── Main exporter ────────────────────────────────────────────────────────────
class ProgrammeWorkbookExporter {
  /// Builds the workbook without touching the filesystem — split from
  /// [export] so tests can decode the bytes and assert the readability
  /// invariant over every styled cell.
  static Future<List<int>> buildBytes({
    required AppDatabase db,
    required String projectId,
    required String projectName,
    bool isProgramme = true,
  }) async {
    final excel = Excel.createExcel();
    // Remove default sheet
    excel.delete('Sheet1');

    await _buildTimelineSheet(
        excel, db, projectId, projectName, isProgramme);
    await _buildMilestoneRegisterSheet(excel, db, projectId);
    await _buildDependenciesSheet(excel, db, projectId);
    await _buildStakeholderSheet(excel, db, projectId);
    await _buildScopeSheet(excel, db, projectId);
    await _buildRaidSheet(excel, db, projectId);

    return excel.save()!;
  }

  static Future<String> export({
    required AppDatabase db,
    required String projectId,
    required String projectName,
    bool isProgramme = true,
  }) async {
    final bytes = await buildBytes(
      db: db,
      projectId: projectId,
      projectName: projectName,
      isProgramme: isProgramme,
    );
    final slug = projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final date = DateTime.now().toIso8601String().substring(0, 10);
    return saveAndOpen(
      'programme_workbook_${slug}_$date.xlsx',
      bytes,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  // ─── Sheet 1: Timeline ────────────────────────────────────────────────────

  // Gantt geometry: month columns ~4.5 chars wide (~36px) with 24pt
  // activity rows (~32px) — near-square cells, like a real gantt. Bars
  // carry NO text (pure colour); every label lives in the ink-on-white
  // name columns, so nothing in the grid can ever be unreadable.
  static const _kMonthColWidth = 4.5;
  static const _kActivityRowHeight = 24.0;
  static const _kFirstMonthCol = 6;

  static Future<void> _buildTimelineSheet(Excel excel, AppDatabase db,
      String projectId, String projectName, bool isProgramme) async {
    final dao    = db.programmeGanttDao;
    final header = await dao.getHeader(projectId);
    final wps    = await dao.getWorkPackages(projectId);
    final allActs = await dao.getActivitiesForProject(projectId);
    final deps   = await dao.getDependencies(projectId);

    // RAID refs for the RISK column (variance drivers).
    final raidRefById = <String, String>{};
    for (final r in await db.raidDao.getRisksForProject(projectId)) {
      raidRefById[r.id] = r.ref ?? 'Risk';
    }
    for (final a in await db.raidDao.getAssumptionsForProject(projectId)) {
      raidRefById[a.id] = a.ref ?? 'Assum.';
    }
    for (final i in await db.raidDao.getIssuesForProject(projectId)) {
      raidRefById[i.id] = i.ref ?? 'Issue';
    }
    for (final d in await db.raidDao.getDependenciesForProject(projectId)) {
      raidRefById[d.id] = d.ref ?? 'Dep';
    }

    final actsByWp = <String, List<TimelineActivity>>{};
    for (final a in allActs) {
      actsByWp.putIfAbsent(a.workPackageId, () => []).add(a);
    }

    List<String> months = [];
    if (header?.monthLabels != null) {
      try {
        months =
            (jsonDecode(header!.monthLabels!) as List).cast<String>();
      } catch (_) {}
    }
    if (months.isEmpty) months = List.generate(12, (i) => 'M$i');

    final sheet =
        excel[isProgramme ? 'Programme Timeline' : 'Project Timeline'];

    // Fixed column widths
    sheet.setColumnWidth(0, 5);   // # (activity number)
    sheet.setColumnWidth(1, 7);   // WP code
    sheet.setColumnWidth(2, 40);  // Activity
    sheet.setColumnWidth(3, 14);  // Owner
    sheet.setColumnWidth(4, 9);   // After (dependencies)
    sheet.setColumnWidth(5, 12);  // Risk(s) driving the variance
    for (int i = 0; i < months.length; i++) {
      sheet.setColumnWidth(_kFirstMonthCol + i, _kMonthColWidth);
    }

    // Number every activity in render order — the AFTER column and the
    // Plan Dependencies sheet reference these numbers, which is how the
    // dependency arrows survive as something a reader can follow.
    final numberByActivityId = <String, int>{};
    var nextNumber = 1;
    for (final wp in wps) {
      for (final act in _wbsOrder(actsByWp[wp.id] ?? [])) {
        numberByActivityId[act.id] = nextNumber++;
      }
    }
    // Predecessors per dependent activity, as '#n' (or EXT) references.
    final afterByActivityId = <String, List<String>>{};
    for (final d in deps) {
      final ref = (d.externalLabel?.isNotEmpty ?? false)
          ? 'EXT'
          : numberByActivityId[d.fromActivityId]?.toString();
      if (ref == null) continue;
      afterByActivityId.putIfAbsent(d.toActivityId, () => []).add(ref);
    }

    int row = 0;
    final totalCols = _kFirstMonthCol + months.length;

    // ── Header band ──────────────────────────────────────────────────────
    if (header != null) {
      final title = [
        header.title ?? projectName,
        if (header.subtitle != null) '  |  ${header.subtitle}',
      ].join();
      _setCell(sheet, row, 0, title,
          style: _style(bgHex: kXlHeaderBg, bold: true, fontSize: 13));
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(
            columnIndex: totalCols - 1, rowIndex: row),
      );
      sheet.setRowHeight(row, 22);
      row++;

      if (header.hardDeadline != null) {
        _setCell(sheet, row, 0, '⚠  ${header.hardDeadline}',
            style: _style(bgHex: kXlRedTint, fgHex: kXlRedText, bold: true));
        sheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          CellIndex.indexByColumnRow(
              columnIndex: totalCols - 1, rowIndex: row),
        );
        sheet.setRowHeight(row, 18);
        row++;
      }
    }

    // ── Column headers ────────────────────────────────────────────────────
    final hdrStyle = _style(
      bgHex: kXlHeaderBg, fgHex: kXlInkDim,
      bold: true, fontSize: 9, allBorders: true,
      halign: HorizontalAlign.Center,
    );
    _setCell(sheet, row, 0, '#',        style: hdrStyle);
    _setCell(sheet, row, 1, 'WP',       style: hdrStyle);
    _setCell(sheet, row, 2, 'ACTIVITY / STREAM', style: hdrStyle);
    _setCell(sheet, row, 3, 'OWNER',    style: hdrStyle);
    _setCell(sheet, row, 4, 'AFTER',    style: hdrStyle);
    _setCell(sheet, row, 5, 'RISK',     style: hdrStyle);
    for (int mi = 0; mi < months.length; mi++) {
      _setCell(sheet, row, _kFirstMonthCol + mi, months[mi],
          style: hdrStyle);
    }
    sheet.setRowHeight(row, 20);
    row++;

    // ── WP + activity rows ────────────────────────────────────────────────
    for (final wp in wps) {
      final wpHex  = _wpHex(wp.colourTheme);
      final wpTint = xlTint(wpHex, 0.75);
      final acts   = _wbsOrder(actsByWp[wp.id] ?? []);
      final wpCode = wp.shortCode ?? '';

      // WP header row — light tint of the theme colour with INK text.
      // No white-on-colour anywhere: text stays black even if a fill
      // fails to render in someone's spreadsheet app.
      final wpLabel = wp.shortCode != null
          ? '${wp.shortCode} — ${wp.name}'
          : wp.name;
      final wpStyle = _style(
          bgHex: wpTint, bold: true, fontSize: 11, allBorders: true);
      _setCell(sheet, row, 0, '',        style: wpStyle);
      _setCell(sheet, row, 1, wpCode,   style: wpStyle);
      _setCell(sheet, row, 2, wpLabel,  style: wpStyle);
      _setCell(sheet, row, 3, '',        style: wpStyle);
      _setCell(sheet, row, 4, '',        style: wpStyle);
      _setCell(sheet, row, 5, '',        style: wpStyle);
      for (int mi = 0; mi < months.length; mi++) {
        _setCell(sheet, row, _kFirstMonthCol + mi, '',
            style: _style(bgHex: wpTint, allBorders: true));
      }
      sheet.setRowHeight(row, 22);
      row++;

      // Activity rows (tasks indented under their parent activity)
      for (final act in acts) {
        final isTask = act.parentActivityId != null;
        var name = isTask ? '    ↳ ${act.name}' : act.name;
        // Bar labels moved off the bars (they're pure colour now) —
        // a custom cell label rides with the activity name instead.
        if (act.cellLabel != null &&
            act.cellLabel!.isNotEmpty &&
            act.cellLabel != act.name) {
          name = '$name · ${act.cellLabel}';
        }
        final nameStyle = act.isCritical
            ? _style(fgHex: kXlRedText, bold: true,
                fontSize: 10, allBorders: true)
            : _style(fontSize: 10, allBorders: true);
        final actStyle = _style(fontSize: 10, allBorders: true);
        final after = afterByActivityId[act.id];
        _setCell(sheet, row, 0, numberByActivityId[act.id] ?? '',
            style: _style(fgHex: kXlInkDim, fontSize: 9,
                allBorders: true, halign: HorizontalAlign.Center));
        _setCell(sheet, row, 1, wpCode,       style: actStyle);
        _setCell(sheet, row, 2,
            act.isCritical ? '$name  ★ critical path' : name,
            style: nameStyle);
        _setCell(sheet, row, 3, act.owner ?? '', style: actStyle);
        _setCell(sheet, row, 4,
            after == null ? '' : '← ${after.join(',')}',
            style: after == null
                ? actStyle
                : _style(fgHex: kXlVioletText, bgHex: kXlVioletTint,
                    fontSize: 9, allBorders: true,
                    halign: HorizontalAlign.Center));
        final raidRefs = _varianceRefs(act, raidRefById);
        _setCell(sheet, row, 5, raidRefs,
            style: raidRefs.isEmpty
                ? actStyle
                : _style(fgHex: kXlRedText, bgHex: kXlRedTint,
                    bold: true, fontSize: 9, allBorders: true,
                    halign: HorizontalAlign.Center));

        final start = act.startMonth;
        final end   = act.endMonth;

        for (int mi = 0; mi < months.length; mi++) {
          final isSingle = act.activityType == 'milestone' ||
              act.activityType == 'hard_deadline' ||
              act.activityType == 'gate';
          final isActive = isSingle
              ? (start != null && mi == start)
              : (start != null && end != null && mi >= start && mi <= end);

          if (isActive) {
            final (cellText, cellBg, cellFg) =
                _ganttCellContent(act, wpHex);
            _setCell(sheet, row, _kFirstMonthCol + mi, cellText,
                style: _style(
                  bgHex: cellBg,
                  fgHex: cellFg,
                  fontSize: 10,
                  allBorders: true,
                  halign: HorizontalAlign.Center,
                ));
          } else if (isSingle && mi == act.likelyMonth) {
            // Scenario ghosts: B — Likely (◇) and C — Safe (○) echo the
            // anchor ◆ so the spread reads directly off the grid.
            _setCell(sheet, row, _kFirstMonthCol + mi, '◇',
                style: _style(
                    fgHex: kXlInkDim, fontSize: 10, allBorders: true,
                    halign: HorizontalAlign.Center));
          } else if (isSingle && mi == act.safeMonth) {
            _setCell(sheet, row, _kFirstMonthCol + mi, '○',
                style: _style(
                    fgHex: kXlInkDim, fontSize: 9, allBorders: true,
                    halign: HorizontalAlign.Center));
          } else if (isSingle && _inScenarioGap(act, mi)) {
            // Dotted thread joining ◆ → ◇ → ○, mirroring the app.
            _setCell(sheet, row, _kFirstMonthCol + mi, '┄',
                style: _style(
                    fgHex: kXlInkDim, fontSize: 9, allBorders: true,
                    halign: HorizontalAlign.Center));
          } else {
            _setCell(sheet, row, _kFirstMonthCol + mi, '',
                style: _style(allBorders: true));
          }
        }
        sheet.setRowHeight(row, _kActivityRowHeight);
        row++;
      }
    }

    // Note: excel package does not support freeze panes natively.
  }

  /// Parents first, each followed by its child tasks — the same nesting
  /// the Plan view shows.
  static List<TimelineActivity> _wbsOrder(List<TimelineActivity> acts) {
    final byParent = <String, List<TimelineActivity>>{};
    for (final a in acts.where((a) => a.parentActivityId != null)) {
      byParent.putIfAbsent(a.parentActivityId!, () => []).add(a);
    }
    final ordered = <TimelineActivity>[];
    for (final a in acts.where((a) => a.parentActivityId == null)) {
      ordered.add(a);
      ordered.addAll(byParent[a.id] ?? const []);
      byParent.remove(a.id);
    }
    // Orphans whose parent is missing — keep them visible.
    for (final rest in byParent.values) {
      ordered.addAll(rest);
    }
    return ordered;
  }

  /// The refs (R19, A3, …) of the RAID items driving an activity's
  /// scenario spread — the JSON list when present, else the legacy
  /// single link.
  static String _varianceRefs(
      TimelineActivity a, Map<String, String> raidRefById) {
    final links = effectiveVarianceLinks(
      linksJson: a.varianceRaidLinksJson,
      legacyType: a.varianceRaidType,
      legacyId: a.varianceRaidId,
    );
    return links
        .map((l) => raidRefById[l.id])
        .whereType<String>()
        .join(', ');
  }

  /// Whether month [mi] lies strictly between the scenario extremes of a
  /// single-point activity — the cell gets the dotted thread.
  static bool _inScenarioGap(TimelineActivity act, int mi) {
    final anchor = act.startMonth;
    if (anchor == null ||
        (act.likelyMonth == null && act.safeMonth == null)) {
      return false;
    }
    var lo = anchor, hi = anchor;
    for (final m in [act.likelyMonth, act.safeMonth]) {
      if (m == null) continue;
      if (m < lo) lo = m;
      if (m > hi) hi = m;
    }
    return mi > lo && mi < hi;
  }

  /// (text, bgHex, fgHex) for an active gantt cell. Bars are PURE COLOUR
  /// (no text — labels live in the name column); single-cell markers use
  /// a dark glyph on a light tint. Nothing here can be unreadable.
  static (String, String, String) _ganttCellContent(
      TimelineActivity act, String wpHex) {
    switch (act.activityType) {
      case 'milestone':
        return ('◆', kXlHeaderBg, kXlInk);
      case 'hard_deadline':
        return ('⚠', kXlRedTint, kXlRedText);
      case 'gate':
        return ('◈', kXlAmberTint, kXlAmberText);
      case 'ongoing':
        return ('', xlTint(wpHex), kXlInk);
      case 'dependency_marker':
        return ('', kXlVioletTint, kXlVioletText);
      default: // activity
        return ('', wpHex, kXlInk); // fg irrelevant — cell is empty
    }
  }

  // ─── Sheet 2: Milestone Register (A / B / C scenario dates) ──────────────

  /// The reference-class register: every milestone/gate/hard-deadline
  /// with its Anchor / Likely / Safe months and the RAID item driving
  /// any spread. Hard dates repeat A across all three columns (they do
  /// not move); single-date items show '—' like external rows.
  static Future<void> _buildMilestoneRegisterSheet(
      Excel excel, AppDatabase db, String projectId) async {
    final dao = db.programmeGanttDao;
    final header = await dao.getHeader(projectId);
    final wps = await dao.getWorkPackages(projectId);
    final acts = await dao.getActivitiesForProject(projectId);

    final registerTypes = {'milestone', 'gate', 'hard_deadline'};
    final rows = acts
        .where((a) => registerTypes.contains(a.activityType))
        .toList()
      ..sort((x, y) => (x.startMonth ?? 999).compareTo(y.startMonth ?? 999));
    if (rows.isEmpty) return;

    List<String> months = [];
    if (header?.monthLabels != null) {
      try {
        months =
            (jsonDecode(header!.monthLabels!) as List).cast<String>();
      } catch (_) {}
    }
    String month(int? idx) => idx == null
        ? '—'
        : (idx >= 0 && idx < months.length ? months[idx] : 'M$idx');

    final wpById = {for (final w in wps) w.id: w};
    final raidRefById = <String, String>{};
    for (final r in await db.raidDao.getRisksForProject(projectId)) {
      raidRefById[r.id] = r.ref ?? 'Risk';
    }
    for (final a in await db.raidDao.getAssumptionsForProject(projectId)) {
      raidRefById[a.id] = a.ref ?? 'Assum.';
    }
    for (final i in await db.raidDao.getIssuesForProject(projectId)) {
      raidRefById[i.id] = i.ref ?? 'Issue';
    }
    for (final d in await db.raidDao.getDependenciesForProject(projectId)) {
      raidRefById[d.id] = d.ref ?? 'Dep';
    }

    final sheet = excel['Milestone Register'];
    sheet.setColumnWidth(0, 8);   // WP
    sheet.setColumnWidth(1, 42);  // Milestone
    sheet.setColumnWidth(2, 11);  // Type
    sheet.setColumnWidth(3, 10);  // A
    sheet.setColumnWidth(4, 10);  // B
    sheet.setColumnWidth(5, 10);  // C
    sheet.setColumnWidth(6, 18);  // Owner
    sheet.setColumnWidth(7, 14);  // Risk(s)
    sheet.setColumnWidth(8, 14);  // Status

    int row = 0;
    _setCell(sheet, row, 0,
        'Milestone Register — A Anchor / B Likely / C Safe',
        style: _style(bgHex: kXlHeaderBg, bold: true, fontSize: 13));
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row),
    );
    sheet.setRowHeight(row, 22);
    row++;

    _setCell(sheet, row, 0,
        'Hard dates do not move (A repeated). "—" = single-date item. '
        'RISK names the RAID item driving the spread.',
        style: _style(fgHex: kXlInkDim, italic: true, fontSize: 9));
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row),
    );
    row++;

    final hdr = _style(bgHex: kXlHeaderBg, fgHex: kXlInkDim,
        bold: true, fontSize: 9, allBorders: true);
    for (final (i, label) in [
      (0, 'WP'), (1, 'MILESTONE'), (2, 'TYPE'),
      (3, 'A — ANCHOR'), (4, 'B — LIKELY'), (5, 'C — SAFE'),
      (6, 'OWNER'), (7, 'RISK'), (8, 'STATUS'),
    ].indexed) {
      _setCell(sheet, row, i, label, style: hdr);
    }
    sheet.setRowHeight(row, 18);
    row++;

    for (final a in rows) {
      final isHard = a.activityType == 'hard_deadline';
      final wp = wpById[a.workPackageId];
      final typeLabel = switch (a.activityType) {
        'hard_deadline' => 'HARD',
        'gate' => 'Gate',
        _ => 'Milestone',
      };
      final raidRefs = _varianceRefs(a, raidRefById);
      final rs = _style(fontSize: 10, allBorders: true);
      final centered = _style(fontSize: 10, allBorders: true,
          halign: HorizontalAlign.Center);
      _setCell(sheet, row, 0, wp?.shortCode ?? wp?.name ?? '',
          style: rs);
      _setCell(sheet, row, 1, a.name,
          style: _style(fontSize: 10, allBorders: true, wrap: true));
      _setCell(sheet, row, 2, typeLabel,
          style: isHard
              ? _style(fgHex: kXlRedText, bgHex: kXlRedTint, bold: true,
                  fontSize: 9, allBorders: true,
                  halign: HorizontalAlign.Center)
              : centered);
      _setCell(sheet, row, 3, month(a.startMonth), style: centered);
      // A hard date "varies" to itself across all three plans.
      _setCell(sheet, row, 4,
          isHard ? month(a.startMonth) : month(a.likelyMonth),
          style: centered);
      _setCell(sheet, row, 5,
          isHard ? month(a.startMonth) : month(a.safeMonth),
          style: centered);
      _setCell(sheet, row, 6, a.owner ?? '', style: rs);
      _setCell(sheet, row, 7, raidRefs.isEmpty ? '—' : raidRefs,
          style: raidRefs.isEmpty
              ? centered
              : _style(fgHex: kXlRedText, bgHex: kXlRedTint, bold: true,
                  fontSize: 9, allBorders: true,
                  halign: HorizontalAlign.Center));
      _setCell(sheet, row, 8, a.status, style: rs);
      sheet.setRowHeight(row, 18);
      row++;
    }
  }

  // ─── Sheet 3: Plan Dependencies ───────────────────────────────────────────

  /// The dependency links the Plan draws as arrows — flattened to a
  /// readable FROM → TO list so the linking survives the trip to Excel.
  /// Skipped entirely when the plan has no dependencies.
  static Future<void> _buildDependenciesSheet(
      Excel excel, AppDatabase db, String projectId) async {
    final dao  = db.programmeGanttDao;
    final deps = await dao.getDependencies(projectId);
    if (deps.isEmpty) return;

    final acts = await dao.getActivitiesForProject(projectId);
    final wps  = await dao.getWorkPackages(projectId);
    final actById = {for (final a in acts) a.id: a};
    final wpById  = {for (final w in wps) w.id: w};

    // Same numbering as the timeline sheet (same render order), so a
    // reader can hop between the AFTER column and this list by #.
    final actsByWp = <String, List<TimelineActivity>>{};
    for (final a in acts) {
      actsByWp.putIfAbsent(a.workPackageId, () => []).add(a);
    }
    final numberByActivityId = <String, int>{};
    var nextNumber = 1;
    for (final wp in wps) {
      for (final act in _wbsOrder(actsByWp[wp.id] ?? [])) {
        numberByActivityId[act.id] = nextNumber++;
      }
    }

    String wpCodeFor(TimelineActivity? a) {
      if (a == null) return '';
      final wp = wpById[a.workPackageId];
      return wp?.shortCode ?? wp?.name ?? '';
    }

    String numberedName(TimelineActivity? a) {
      if (a == null) return '?';
      final n = numberByActivityId[a.id];
      return n == null ? a.name : '#$n  ${a.name}';
    }

    String typeLabel(String t) => switch (t) {
          'finish_to_start' => 'Finish → Start',
          'start_to_start'  => 'Start → Start',
          'finish_to_finish' => 'Finish → Finish',
          'start_to_finish' => 'Start → Finish',
          _ => t,
        };

    final sheet = excel['Plan Dependencies'];
    sheet.setColumnWidth(0, 36); // From
    sheet.setColumnWidth(1, 10); // From WP
    sheet.setColumnWidth(2, 36); // To
    sheet.setColumnWidth(3, 10); // To WP
    sheet.setColumnWidth(4, 16); // Type
    sheet.setColumnWidth(5, 34); // Notes

    int row = 0;
    _setCell(sheet, row, 0, 'Plan Dependencies',
        style: _style(bgHex: kXlHeaderBg, bold: true, fontSize: 13));
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
    );
    sheet.setRowHeight(row, 22);
    row++;

    _setCell(sheet, row, 0,
        'Each row reads: the TO activity depends on the FROM side. '
        '#numbers match the timeline sheet\'s # and AFTER columns.',
        style: _style(fgHex: kXlInkDim, italic: true, fontSize: 9));
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
    );
    row++;

    final hdr = _style(bgHex: kXlHeaderBg, fgHex: kXlInkDim,
        bold: true, fontSize: 9, allBorders: true);
    _setCell(sheet, row, 0, 'FROM (predecessor)', style: hdr);
    _setCell(sheet, row, 1, 'WP',                style: hdr);
    _setCell(sheet, row, 2, 'TO (dependent)',    style: hdr);
    _setCell(sheet, row, 3, 'WP',                style: hdr);
    _setCell(sheet, row, 4, 'TYPE',              style: hdr);
    _setCell(sheet, row, 5, 'NOTES',             style: hdr);
    sheet.setRowHeight(row, 18);
    row++;

    for (final d in deps) {
      final fromAct = actById[d.fromActivityId];
      final toAct   = actById[d.toActivityId];
      final isExternal = d.externalLabel?.isNotEmpty ?? false;
      final fromLabel = isExternal
          ? '${d.externalLabel} (external)'
          : numberedName(fromAct);

      final rs = _style(fontSize: 10, allBorders: true, wrap: true);
      _setCell(sheet, row, 0, fromLabel,
          style: isExternal
              ? _style(fgHex: kXlVioletText, bgHex: kXlVioletTint,
                  fontSize: 10, allBorders: true, wrap: true)
              : rs);
      _setCell(sheet, row, 1, isExternal ? '—' : wpCodeFor(fromAct),
          style: rs);
      _setCell(sheet, row, 2, numberedName(toAct), style: rs);
      _setCell(sheet, row, 3, wpCodeFor(toAct),   style: rs);
      _setCell(sheet, row, 4, typeLabel(d.dependencyType), style: rs);
      _setCell(sheet, row, 5, d.notes ?? '',      style: rs);
      sheet.setRowHeight(row, 18);
      row++;
    }
  }

  // ─── Sheet 3: Stakeholder Map ──────────────────────────────────────────────

  static Future<void> _buildStakeholderSheet(
      Excel excel, AppDatabase db, String projectId) async {
    final persons     = await db.peopleDao.getPersonsForProject(projectId);
    final roles       = await db.stakeholderRoleDao.getForProject(projectId);
    final personById  = {for (final p in persons) p.id: p};

    final sheet = excel['Stakeholder Map'];

    // Columns: Functional Area | Role | Name | Priority | Engagement | Relevance | Gap
    sheet.setColumnWidth(0, 26);  // Functional area
    sheet.setColumnWidth(1, 28);  // Role name
    sheet.setColumnWidth(2, 22);  // Name
    sheet.setColumnWidth(3, 14);  // Priority
    sheet.setColumnWidth(4, 22);  // Engagement status
    sheet.setColumnWidth(5, 36);  // Integration relevance
    sheet.setColumnWidth(6, 30);  // Gap description

    int row = 0;

    // Title row
    _setCell(sheet, row, 0, 'Stakeholder Map',
        style: _style(bgHex: kXlHeaderBg, bold: true, fontSize: 13));
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet.setRowHeight(row, 22);
    row++;

    // Column headers
    final hdr = _style(
        bgHex: kXlHeaderBg, fgHex: kXlInkDim,
        bold: true, fontSize: 9, allBorders: true);
    _setCell(sheet, row, 0, 'FUNCTIONAL AREA',      style: hdr);
    _setCell(sheet, row, 1, 'ROLE',                 style: hdr);
    _setCell(sheet, row, 2, 'NAME',                 style: hdr);
    _setCell(sheet, row, 3, 'PRIORITY',             style: hdr);
    _setCell(sheet, row, 4, 'ENGAGEMENT',           style: hdr);
    _setCell(sheet, row, 5, 'INTEGRATION RELEVANCE',style: hdr);
    _setCell(sheet, row, 6, 'GAP / NOTES',          style: hdr);
    sheet.setRowHeight(row, 18);
    row++;

    // Group by functionalArea (fall back to roleType for ungrouped rows)
    final grouped = <String, List<StakeholderRole>>{};
    for (final r in roles.where((r) => r.isApplicable)) {
      final key = r.functionalArea?.isNotEmpty == true
          ? r.functionalArea!
          : r.roleType[0].toUpperCase() + r.roleType.substring(1);
      grouped.putIfAbsent(key, () => []).add(r);
    }

    for (final entry in grouped.entries) {
      // Group header
      _setCell(sheet, row, 0, entry.key,
          style: _style(bgHex: kXlHeaderBg, fgHex: kXlInk,
              bold: true, fontSize: 10, allBorders: true));
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
      );
      sheet.setRowHeight(row, 18);
      row++;

      for (final role in entry.value) {
        final person = role.personId != null
            ? personById[role.personId]
            : null;

        // Priority cell colouring — tint fill + matching dark text
        final (priorityFg, priorityBg) = switch (role.priority) {
          'critical' => (kXlRedText,   kXlRedTint),
          'high'     => (kXlAmberText, kXlAmberTint),
          'medium'   => (kXlGreenText, kXlGreenTint),
          _          => (kXlInkDim,    null),
        };

        // Engagement cell colouring
        final (engFg, engBg) = switch (role.engagementStatus) {
          'engaged'             => (kXlGreenText, kXlGreenTint),
          'gap_action_required' => (kXlRedText,   kXlRedTint),
          'not_engaged'         => (kXlAmberText, kXlAmberTint),
          'complete'            => (kXlGreenText, kXlGreenTint),
          _                     => (kXlInkDim,    null),
        };

        final engLabel = switch (role.engagementStatus) {
          'engaged'             => 'Engaged',
          'gap_action_required' => 'Gap — action required',
          'not_engaged'         => 'Not engaged',
          'complete'            => 'Complete',
          _                     => '—',
        };

        final gapText = role.gapFlag
            ? '⚠ ${role.gapDescription ?? 'Gap flagged'}'
            : (role.notes ?? '');

        final rowStyle = _style(fontSize: 10, allBorders: true);
        _setCell(sheet, row, 0, '',                          style: rowStyle);
        _setCell(sheet, row, 1, role.roleName,               style: rowStyle);
        _setCell(sheet, row, 2, person?.name ?? '—',         style: rowStyle);
        _setCell(sheet, row, 3,
            role.priority != null
                ? role.priority![0].toUpperCase() + role.priority!.substring(1)
                : '—',
            style: _style(fgHex: priorityFg, bgHex: priorityBg,
                bold: true, fontSize: 9, allBorders: true,
                halign: HorizontalAlign.Center));
        _setCell(sheet, row, 4, engLabel,
            style: _style(fgHex: engFg, bgHex: engBg,
                fontSize: 9, allBorders: true));
        _setCell(sheet, row, 5, role.integrationRelevance ?? '',
            style: _style(fgHex: kXlInkDim, fontSize: 9,
                allBorders: true, wrap: true));
        _setCell(sheet, row, 6, gapText,
            style: _style(
                fgHex: role.gapFlag ? kXlRedText : kXlInkDim,
                bgHex: role.gapFlag ? kXlRedTint : null,
                fontSize: 9, allBorders: true, wrap: true));
        sheet.setRowHeight(row, 18);
        row++;
      }
    }
  }

  // ─── Sheet 4: Scope ────────────────────────────────────────────────────────

  static Future<void> _buildScopeSheet(
      Excel excel, AppDatabase db, String projectId) async {
    final scope   = await db.programmeGanttDao.getScope(projectId);
    final domains = await db.programmeGanttDao.getDomains(projectId);
    final sources = await db.programmeGanttDao.getSources(projectId);

    final sheet = excel['Scope & Prioritisation'];
    sheet.setColumnWidth(0, 12);
    sheet.setColumnWidth(1, 36);
    sheet.setColumnWidth(2, 40);
    sheet.setColumnWidth(3, 18);
    sheet.setColumnWidth(4, 14);

    int row = 0;

    void sectionHeader(String title) {
      _setCell(sheet, row, 0, title,
          style: _style(bgHex: kXlHeaderBg, bold: true, fontSize: 11));
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
      );
      sheet.setRowHeight(row, 20);
      row++;
    }

    // ── In scope ──────────────────────────────────────────────────────────
    sectionHeader('IN SCOPE');
    if (scope?.inScopeItems != null) {
      try {
        final items = (jsonDecode(scope!.inScopeItems!) as List)
            .cast<Map<String, dynamic>>();
        for (final item in items) {
          _setCell(sheet, row, 0, item['number']?.toString() ?? '',
              style: _style(fgHex: kXlAmberText, bold: true,
                  allBorders: true));
          _setCell(sheet, row, 1, item['title'] ?? '',
              style: _style(bold: true, allBorders: true));
          _setCell(sheet, row, 2, item['description'] ?? '',
              style: _style(fgHex: kXlInkDim, fontSize: 9,
                  allBorders: true, wrap: true));
          sheet.setRowHeight(row, 18);
          row++;
        }
      } catch (_) {}
    }
    row++;

    // ── Out of scope ──────────────────────────────────────────────────────
    sectionHeader('OUT OF SCOPE');
    if (scope?.outOfScope != null) {
      try {
        final items =
            (jsonDecode(scope!.outOfScope!) as List).cast<String>();
        for (final item in items) {
          _setCell(sheet, row, 0, '✗',
              style: _style(fgHex: kXlRedText, bold: true,
                  allBorders: true));
          _setCell(sheet, row, 1, item,
              style: _style(fgHex: kXlInkDim, fontSize: 10,
                  allBorders: true));
          sheet.setRowHeight(row, 18);
          row++;
        }
      } catch (_) {}
    }
    row++;

    // ── API Prioritisation Sources ─────────────────────────────────────────
    if (sources.isNotEmpty) {
      sectionHeader('API PRIORITISATION FRAMEWORK');
      final hdr = _style(bgHex: kXlHeaderBg, fgHex: kXlInkDim,
          bold: true, fontSize: 9, allBorders: true);
      _setCell(sheet, row, 0, 'SOURCE',       style: hdr);
      _setCell(sheet, row, 1, 'INPUT TYPE',   style: hdr);
      _setCell(sheet, row, 2, 'OWNER',        style: hdr);
      _setCell(sheet, row, 3, 'MECHANISM',    style: hdr);
      _setCell(sheet, row, 4, 'WEIGHT',       style: hdr);
      row++;
      for (final s in sources) {
        final rs = _style(fontSize: 10, allBorders: true);
        _setCell(sheet, row, 0, s.sourceName,   style: rs);
        _setCell(sheet, row, 1, s.inputType ?? '', style: rs);
        _setCell(sheet, row, 2, s.owner ?? '',  style: rs);
        _setCell(sheet, row, 3, s.mechanism ?? '', style: rs);
        _setCell(sheet, row, 4, s.weight ?? '', style: rs);
        sheet.setRowHeight(row, 18);
        row++;
      }
      row++;
    }

    // ── Known Integration Domains ──────────────────────────────────────────
    if (domains.isNotEmpty) {
      sectionHeader('KNOWN INTEGRATION DOMAINS');
      final hdr = _style(bgHex: kXlHeaderBg, fgHex: kXlInkDim,
          bold: true, fontSize: 9, allBorders: true);
      _setCell(sheet, row, 0, 'PRIORITY',        style: hdr);
      _setCell(sheet, row, 1, 'DOMAIN',          style: hdr);
      _setCell(sheet, row, 2, 'LIKELY SYSTEMS',  style: hdr);
      _setCell(sheet, row, 3, 'PRIORITY SIGNAL', style: hdr);
      _setCell(sheet, row, 4, 'STATUS',          style: hdr);
      row++;
      for (final d in domains) {
        final (statusFg, statusBg) = switch (d.status) {
          'complete'    => (kXlGreenText, kXlGreenTint),
          'in_progress' => (kXlAmberText, kXlAmberTint),
          'at_risk'     => (kXlRedText,   kXlRedTint),
          _             => (kXlInk,       null),
        };
        final rs = _style(fontSize: 10, allBorders: true);
        _setCell(sheet, row, 0, d.priority ?? '',        style: rs);
        _setCell(sheet, row, 1, d.domain,                style: rs);
        _setCell(sheet, row, 2, d.likelySystems ?? '',   style: rs);
        _setCell(sheet, row, 3, d.prioritySignal ?? '',  style: rs);
        _setCell(sheet, row, 4, d.status,
            style: _style(bgHex: statusBg, fgHex: statusFg,
                fontSize: 10, allBorders: true));
        sheet.setRowHeight(row, 18);
        row++;
      }
    }
  }

  // ─── Sheet 5: RAID ────────────────────────────────────────────────────────

  static Future<void> _buildRaidSheet(
      Excel excel, AppDatabase db, String projectId) async {
    final risks       = await db.raidDao.getRisksForProject(projectId);
    final assumptions = await db.raidDao.getAssumptionsForProject(projectId);
    final issues      = await db.raidDao.getIssuesForProject(projectId);
    final deps        = await db.raidDao.getDependenciesForProject(projectId);

    final sheet = excel['RAID Log'];
    sheet.setColumnWidth(0, 8);   // Ref
    sheet.setColumnWidth(1, 8);   // Type
    sheet.setColumnWidth(2, 40);  // Description
    sheet.setColumnWidth(3, 12);  // Likelihood / Priority
    sheet.setColumnWidth(4, 12);  // Impact / Status
    sheet.setColumnWidth(5, 34);  // Mitigation / Resolution
    sheet.setColumnWidth(6, 16);  // Owner
    sheet.setColumnWidth(7, 12);  // Status
    sheet.setColumnWidth(8, 14);  // Raised date

    int row = 0;

    // Column headers
    final hdr = _style(bgHex: kXlHeaderBg, fgHex: kXlInkDim,
        bold: true, fontSize: 9, allBorders: true);
    for (final (i, label) in [
      (0, 'REF'), (1, 'TYPE'), (2, 'DESCRIPTION'),
      (3, 'LIKELIHOOD'), (4, 'IMPACT'), (5, 'MITIGATION'),
      (6, 'OWNER'), (7, 'STATUS'), (8, 'RAISED'),
    ].indexed) {
      _setCell(sheet, row, i, label, style: hdr);
    }
    row++;

    void sectionBand(String label) {
      _setCell(sheet, row, 0, label,
          style: _style(bgHex: kXlHeaderBg,
              bold: true, fontSize: 10, allBorders: true));
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row),
      );
      sheet.setRowHeight(row, 18);
      row++;
    }

    (String, String?) ragStyle(String l, String i) {
      if (l == 'high' && i == 'high') return (kXlRedText, kXlRedTint);
      if (l == 'high' || i == 'high') return (kXlAmberText, kXlAmberTint);
      if (l == 'low' && i == 'low') return (kXlGreenText, kXlGreenTint);
      return (kXlInk, null);
    }

    // ── Risks ──────────────────────────────────────────────────────────────
    sectionBand('RISKS');
    for (final r in risks) {
      final (ragFg, ragBg) = ragStyle(r.likelihood, r.impact);
      final rs = _style(fontSize: 10, allBorders: true);
      _setCell(sheet, row, 0, r.ref ?? '',         style: rs);
      _setCell(sheet, row, 1, 'Risk',              style: rs);
      _setCell(sheet, row, 2, r.description,
          style: _style(fontSize: 10, allBorders: true, wrap: true));
      _setCell(sheet, row, 3, r.likelihood,
          style: _style(bgHex: ragBg, fgHex: ragFg,
              fontSize: 10, allBorders: true));
      _setCell(sheet, row, 4, r.impact,
          style: _style(bgHex: ragBg, fgHex: ragFg,
              fontSize: 10, allBorders: true));
      _setCell(sheet, row, 5, r.mitigation ?? '',  style: rs);
      _setCell(sheet, row, 6, r.owner ?? '',       style: rs);
      _setCell(sheet, row, 7, r.status,            style: rs);
      _setCell(sheet, row, 8,
          r.createdAt.toIso8601String().substring(0, 10), style: rs);
      sheet.setRowHeight(row, 18);
      row++;
    }

    // ── Assumptions ────────────────────────────────────────────────────────
    sectionBand('ASSUMPTIONS');
    for (final a in assumptions) {
      final rs = _style(fontSize: 10, allBorders: true);
      _setCell(sheet, row, 0, a.ref ?? '',       style: rs);
      _setCell(sheet, row, 1, 'Assumption',      style: rs);
      _setCell(sheet, row, 2, a.description,
          style: _style(fontSize: 10, allBorders: true, wrap: true));
      _setCell(sheet, row, 3, '',                style: rs);
      _setCell(sheet, row, 4, '',                style: rs);
      _setCell(sheet, row, 5, '',                style: rs);
      _setCell(sheet, row, 6, a.owner ?? '',     style: rs);
      _setCell(sheet, row, 7, a.status,          style: rs);
      _setCell(sheet, row, 8,
          a.createdAt.toIso8601String().substring(0, 10), style: rs);
      sheet.setRowHeight(row, 18);
      row++;
    }

    // ── Issues ─────────────────────────────────────────────────────────────
    sectionBand('ISSUES');
    for (final i in issues) {
      final (priorityFg, priorityBg) = switch (i.priority) {
        'high'   => (kXlRedText,   kXlRedTint),
        'medium' => (kXlAmberText, kXlAmberTint),
        'low'    => (kXlGreenText, kXlGreenTint),
        _        => (kXlInk,       null),
      };
      final rs = _style(fontSize: 10, allBorders: true);
      _setCell(sheet, row, 0, i.ref ?? '',      style: rs);
      _setCell(sheet, row, 1, 'Issue',          style: rs);
      _setCell(sheet, row, 2, i.description,
          style: _style(fontSize: 10, allBorders: true, wrap: true));
      _setCell(sheet, row, 3, i.priority,
          style: _style(bgHex: priorityBg, fgHex: priorityFg,
              fontSize: 10, allBorders: true));
      _setCell(sheet, row, 4, '',               style: rs);
      _setCell(sheet, row, 5, i.resolution ?? '', style: rs);
      _setCell(sheet, row, 6, i.owner ?? '',    style: rs);
      _setCell(sheet, row, 7, i.status,         style: rs);
      _setCell(sheet, row, 8,
          i.createdAt.toIso8601String().substring(0, 10), style: rs);
      sheet.setRowHeight(row, 18);
      row++;
    }

    // ── Dependencies ───────────────────────────────────────────────────────
    sectionBand('DEPENDENCIES');
    for (final d in deps) {
      final rs = _style(fontSize: 10, allBorders: true);
      _setCell(sheet, row, 0, d.ref ?? '',       style: rs);
      _setCell(sheet, row, 1, 'Dependency',      style: rs);
      _setCell(sheet, row, 2, d.description,
          style: _style(fontSize: 10, allBorders: true, wrap: true));
      _setCell(sheet, row, 3, d.dependencyType,  style: rs);
      _setCell(sheet, row, 4, '',                style: rs);
      _setCell(sheet, row, 5, '',                style: rs);
      _setCell(sheet, row, 6, d.owner ?? '',     style: rs);
      _setCell(sheet, row, 7, d.status,          style: rs);
      _setCell(sheet, row, 8,
          d.createdAt.toIso8601String().substring(0, 10), style: rs);
      sheet.setRowHeight(row, 18);
      row++;
    }
  }
}
