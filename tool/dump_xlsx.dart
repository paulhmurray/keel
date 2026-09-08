// Throwaway: dump the sheets/cells of an xlsx so its structure can be
// inspected. Run: dart run tool/dump_xlsx.dart <path>
// ignore_for_file: avoid_print
import 'dart:io';
import 'package:excel/excel.dart';

void main(List<String> args) {
  final bytes = File(args.first).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  for (final entry in excel.tables.entries) {
    final sheet = entry.value;
    print('=== SHEET: ${entry.key} (${sheet.maxRows} rows x ${sheet.maxColumns} cols) ===');
    for (final (r, row) in sheet.rows.indexed) {
      if (r > 120) {
        print('... truncated ...');
        break;
      }
      final cells = <String>[];
      for (final (c, cell) in row.indexed) {
        final v = cell?.value?.toString() ?? '';
        if (v.isNotEmpty) cells.add('[$c]$v');
      }
      if (cells.isNotEmpty) print('r$r: ${cells.join(' | ')}');
    }
  }
}
