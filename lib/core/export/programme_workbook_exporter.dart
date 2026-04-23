import 'dart:convert';
import 'package:excel/excel.dart';

import '../database/database.dart';
import '../platform/web_download.dart';

// ─── Colour palette (hex strings without #) ──────────────────────────────────
const _kSurface  = 'FF252B3B';
const _kSurface2 = 'FF2E3446';
const _kBorder   = 'FF2E3446';
const _kText     = 'FFE2E8F0';
const _kTextDim  = 'FF8A9FAF';
const _kAmber    = 'FFFBBF24';
const _kRed      = 'FFEF4444';
const _kRedDim   = 'FF3F1515';
const _kGreenDim = 'FF0D3325';
const _kAmberDim = 'FF3D2B05';
const _kWhite    = 'FFFFFFFF';

// WP theme colours
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
  String fgHex  = _kText,
  bool bold      = false,
  bool italic    = false,
  int  fontSize  = 10,
  HorizontalAlign halign = HorizontalAlign.Left,
  VerticalAlign   valign = VerticalAlign.Center,
  bool wrap      = false,
  bool topBorder = false,
  bool allBorders = false,
}) {
  final border = allBorders
      ? Border(
          borderStyle: BorderStyle.Thin,
          borderColorHex: ExcelColor.fromHexString('#$_kBorder'),
        )
      : topBorder
          ? Border(
              borderStyle: BorderStyle.Thin,
              borderColorHex: ExcelColor.fromHexString('#$_kBorder'),
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
  static Future<String> export({
    required AppDatabase db,
    required String projectId,
    required String projectName,
  }) async {
    final excel = Excel.createExcel();
    // Remove default sheet
    excel.delete('Sheet1');

    await _buildTimelineSheet(excel, db, projectId, projectName);
    await _buildStakeholderSheet(excel, db, projectId);
    await _buildScopeSheet(excel, db, projectId);
    await _buildRaidSheet(excel, db, projectId);

    final bytes = excel.save()!;
    final slug = projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final date = DateTime.now().toIso8601String().substring(0, 10);
    return saveAndOpen(
      'programme_workbook_${slug}_$date.xlsx',
      bytes,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  // ─── Sheet 1: Programme Timeline ──────────────────────────────────────────

  static Future<void> _buildTimelineSheet(
      Excel excel, AppDatabase db, String projectId, String projectName) async {
    final dao    = db.programmeGanttDao;
    final header = await dao.getHeader(projectId);
    final wps    = await dao.getWorkPackages(projectId);
    final allActs = await dao.getActivitiesForProject(projectId);

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

    final sheet = excel['Programme Timeline'];

    // Fixed column widths
    sheet.setColumnWidth(0, 12);  // WP code
    sheet.setColumnWidth(1, 36);  // Activity
    sheet.setColumnWidth(2, 18);  // Owner
    for (int i = 0; i < months.length; i++) {
      sheet.setColumnWidth(3 + i, 10);
    }

    int row = 0;
    final totalCols = 3 + months.length;

    // ── Header band ──────────────────────────────────────────────────────
    if (header != null) {
      final title = [
        header.title ?? projectName,
        if (header.subtitle != null) '  |  ${header.subtitle}',
      ].join();
      _setCell(sheet, row, 0, title,
          style: _style(bgHex: _kSurface2, fgHex: _kAmber,
              bold: true, fontSize: 13));
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(
            columnIndex: totalCols - 1, rowIndex: row),
      );
      sheet.setRowHeight(row, 22);
      row++;

      if (header.hardDeadline != null) {
        _setCell(sheet, row, 0, '⚠  ${header.hardDeadline}',
            style: _style(bgHex: _kRedDim, fgHex: _kRed, bold: true));
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
      bgHex: _kSurface2, fgHex: _kTextDim,
      bold: true, fontSize: 9, allBorders: true,
      halign: HorizontalAlign.Center,
    );
    _setCell(sheet, row, 0, 'WP',       style: hdrStyle);
    _setCell(sheet, row, 1, 'ACTIVITY / STREAM', style: hdrStyle);
    _setCell(sheet, row, 2, 'OWNER',    style: hdrStyle);
    for (int mi = 0; mi < months.length; mi++) {
      _setCell(sheet, row, 3 + mi, months[mi],
          style: _style(
            bgHex: _kSurface2, fgHex: _kTextDim,
            bold: true, fontSize: 9, allBorders: true,
            halign: HorizontalAlign.Center,
          ));
    }
    sheet.setRowHeight(row, 20);
    row++;

    // ── WP + activity rows ────────────────────────────────────────────────
    for (final wp in wps) {
      final wpHex  = _wpHex(wp.colourTheme);
      final acts   = actsByWp[wp.id] ?? [];
      final wpCode = wp.shortCode ?? '';

      // WP header row
      final wpLabel = wp.shortCode != null
          ? '${wp.shortCode} — ${wp.name}'
          : wp.name;
      final wpStyle = _style(
          bgHex: wpHex, fgHex: _kWhite,
          bold: true, fontSize: 11, allBorders: true);
      _setCell(sheet, row, 0, wpCode,   style: wpStyle);
      _setCell(sheet, row, 1, wpLabel,  style: wpStyle);
      _setCell(sheet, row, 2, '',        style: wpStyle);
      for (int mi = 0; mi < months.length; mi++) {
        _setCell(sheet, row, 3 + mi, '',
            style: _style(bgHex: wpHex, allBorders: true));
      }
      sheet.setRowHeight(row, 22);
      row++;

      // Activity rows
      for (final act in acts) {
        final actStyle = _style(
            fgHex: _kText, fontSize: 10, allBorders: true);
        _setCell(sheet, row, 0, wpCode,       style: actStyle);
        _setCell(sheet, row, 1, act.name,     style: actStyle);
        _setCell(sheet, row, 2, act.owner ?? '', style: actStyle);

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
                _ganttCellContent(act, mi == start, wpHex);
            _setCell(sheet, row, 3 + mi, cellText,
                style: _style(
                  bgHex: cellBg,
                  fgHex: cellFg ?? _kWhite,
                  fontSize: 9,
                  allBorders: true,
                  halign: HorizontalAlign.Center,
                ));
          } else {
            _setCell(sheet, row, 3 + mi, '',
                style: _style(allBorders: true));
          }
        }
        sheet.setRowHeight(row, 18);
        row++;
      }
    }

    // Note: excel package does not support freeze panes natively.
  }

  static (String, String, String?) _ganttCellContent(
      TimelineActivity act, bool isFirst, String wpHex) {
    switch (act.activityType) {
      case 'milestone':
        return ('◆ ${act.cellLabel ?? act.name}', _kSurface, wpHex);
      case 'hard_deadline':
        return ('⚠ ${act.cellLabel ?? act.name}', _kRedDim, _kRed);
      case 'gate':
        return ('◈', _kAmberDim, _kAmber);
      case 'ongoing':
        final label = isFirst ? (act.cellLabel ?? act.name) : '';
        return (label, '${wpHex}44', wpHex);
      case 'dependency_marker':
        final label = isFirst ? (act.cellLabel ?? '') : '';
        return (label, 'FF8B5CF644', 'FF8B5CF6');
      default: // activity
        final label = isFirst ? (act.cellLabel ?? act.name) : '';
        return (label, wpHex, _kWhite);
    }
  }

  // ─── Sheet 2: Stakeholder Map ──────────────────────────────────────────────

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
        style: _style(bgHex: _kSurface2, fgHex: _kAmber,
            bold: true, fontSize: 13));
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row),
    );
    sheet.setRowHeight(row, 22);
    row++;

    // Column headers
    final hdr = _style(
        bgHex: _kSurface2, fgHex: _kTextDim,
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
          style: _style(bgHex: _kSurface2, fgHex: _kAmber,
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

        // Priority cell colouring
        final (priorityFg, priorityBg) = switch (role.priority) {
          'critical' => (_kRed,    _kRedDim),
          'high'     => (_kAmber,  _kAmberDim),
          'medium'   => (_kGreenDim, _kGreenDim),
          _          => (_kTextDim, _kSurface),
        };

        // Engagement cell colouring
        final (engFg, engBg) = switch (role.engagementStatus) {
          'engaged'             => (_kGreenDim, _kGreenDim),
          'gap_action_required' => (_kRed,      _kRedDim),
          'not_engaged'         => (_kAmber,    _kAmberDim),
          'complete'            => (_kGreenDim, _kGreenDim),
          _                     => (_kTextDim,  _kSurface),
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

        final rowStyle = _style(fgHex: _kText, fontSize: 10, allBorders: true);
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
            style: _style(fgHex: _kTextDim, fontSize: 9,
                allBorders: true, wrap: true));
        _setCell(sheet, row, 6, gapText,
            style: _style(
                fgHex: role.gapFlag ? _kRed : _kTextDim,
                bgHex: role.gapFlag ? _kRedDim : null,
                fontSize: 9, allBorders: true, wrap: true));
        sheet.setRowHeight(row, 18);
        row++;
      }
    }
  }

  // ─── Sheet 3: Scope ────────────────────────────────────────────────────────

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
          style: _style(bgHex: _kSurface2, fgHex: _kAmber,
              bold: true, fontSize: 11));
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
              style: _style(fgHex: _kAmber, bold: true, allBorders: true));
          _setCell(sheet, row, 1, item['title'] ?? '',
              style: _style(fgHex: _kText, bold: true, allBorders: true));
          _setCell(sheet, row, 2, item['description'] ?? '',
              style: _style(fgHex: _kTextDim, fontSize: 9,
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
              style: _style(fgHex: _kRed, bold: true, allBorders: true));
          _setCell(sheet, row, 1, item,
              style: _style(fgHex: _kTextDim, fontSize: 10,
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
      final hdr = _style(bgHex: _kSurface2, fgHex: _kTextDim,
          bold: true, fontSize: 9, allBorders: true);
      _setCell(sheet, row, 0, 'SOURCE',       style: hdr);
      _setCell(sheet, row, 1, 'INPUT TYPE',   style: hdr);
      _setCell(sheet, row, 2, 'OWNER',        style: hdr);
      _setCell(sheet, row, 3, 'MECHANISM',    style: hdr);
      _setCell(sheet, row, 4, 'WEIGHT',       style: hdr);
      row++;
      for (final s in sources) {
        final rs = _style(fgHex: _kText, fontSize: 10, allBorders: true);
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
      final hdr = _style(bgHex: _kSurface2, fgHex: _kTextDim,
          bold: true, fontSize: 9, allBorders: true);
      _setCell(sheet, row, 0, 'PRIORITY',        style: hdr);
      _setCell(sheet, row, 1, 'DOMAIN',          style: hdr);
      _setCell(sheet, row, 2, 'LIKELY SYSTEMS',  style: hdr);
      _setCell(sheet, row, 3, 'PRIORITY SIGNAL', style: hdr);
      _setCell(sheet, row, 4, 'STATUS',          style: hdr);
      row++;
      for (final d in domains) {
        final statusBg = switch (d.status) {
          'complete'    => _kGreenDim,
          'in_progress' => _kAmberDim,
          'at_risk'     => _kRedDim,
          _             => null,
        };
        final rs = _style(fgHex: _kText, fontSize: 10, allBorders: true);
        _setCell(sheet, row, 0, d.priority ?? '',        style: rs);
        _setCell(sheet, row, 1, d.domain,                style: rs);
        _setCell(sheet, row, 2, d.likelySystems ?? '',   style: rs);
        _setCell(sheet, row, 3, d.prioritySignal ?? '',  style: rs);
        _setCell(sheet, row, 4, d.status,
            style: _style(bgHex: statusBg, fgHex: _kText,
                fontSize: 10, allBorders: true));
        sheet.setRowHeight(row, 18);
        row++;
      }
    }
  }

  // ─── Sheet 4: RAID ────────────────────────────────────────────────────────

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
    final hdr = _style(bgHex: _kSurface2, fgHex: _kTextDim,
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
          style: _style(bgHex: _kSurface2, fgHex: _kAmber,
              bold: true, fontSize: 10, allBorders: true));
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row),
      );
      sheet.setRowHeight(row, 18);
      row++;
    }

    String? _ragBg(String l, String i) {
      if (l == 'high' && i == 'high') return _kRedDim;
      if (l == 'high' || i == 'high') return _kAmberDim;
      if (l == 'low' && i == 'low') return _kGreenDim;
      return null;
    }

    // ── Risks ──────────────────────────────────────────────────────────────
    sectionBand('RISKS');
    for (final r in risks) {
      final bg = _ragBg(r.likelihood, r.impact);
      final rs = _style(fgHex: _kText, fontSize: 10, allBorders: true);
      _setCell(sheet, row, 0, r.ref ?? '',         style: rs);
      _setCell(sheet, row, 1, 'Risk',              style: rs);
      _setCell(sheet, row, 2, r.description,
          style: _style(fgHex: _kText, fontSize: 10, allBorders: true, wrap: true));
      _setCell(sheet, row, 3, r.likelihood,
          style: _style(bgHex: bg, fgHex: _kText, fontSize: 10, allBorders: true));
      _setCell(sheet, row, 4, r.impact,
          style: _style(bgHex: bg, fgHex: _kText, fontSize: 10, allBorders: true));
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
      final rs = _style(fgHex: _kText, fontSize: 10, allBorders: true);
      _setCell(sheet, row, 0, a.ref ?? '',       style: rs);
      _setCell(sheet, row, 1, 'Assumption',      style: rs);
      _setCell(sheet, row, 2, a.description,
          style: _style(fgHex: _kText, fontSize: 10, allBorders: true, wrap: true));
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
      final priorityBg = switch (i.priority) {
        'high'   => _kRedDim,
        'medium' => _kAmberDim,
        'low'    => _kGreenDim,
        _        => null,
      };
      final rs = _style(fgHex: _kText, fontSize: 10, allBorders: true);
      _setCell(sheet, row, 0, i.ref ?? '',      style: rs);
      _setCell(sheet, row, 1, 'Issue',          style: rs);
      _setCell(sheet, row, 2, i.description,
          style: _style(fgHex: _kText, fontSize: 10, allBorders: true, wrap: true));
      _setCell(sheet, row, 3, i.priority,
          style: _style(bgHex: priorityBg, fgHex: _kText,
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
      final rs = _style(fgHex: _kText, fontSize: 10, allBorders: true);
      _setCell(sheet, row, 0, d.ref ?? '',       style: rs);
      _setCell(sheet, row, 1, 'Dependency',      style: rs);
      _setCell(sheet, row, 2, d.description,
          style: _style(fgHex: _kText, fontSize: 10, allBorders: true, wrap: true));
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
