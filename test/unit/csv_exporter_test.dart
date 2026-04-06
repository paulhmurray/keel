import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/export/csv_exporter.dart';

void main() {
  group('CsvExporter.quoteCsvCell', () {
    test('plain string is unchanged', () {
      expect(CsvExporter.quoteCsvCell('hello'), 'hello');
    });

    test('empty string is not quoted', () {
      expect(CsvExporter.quoteCsvCell(''), '');
    });

    test('field with comma is wrapped in quotes', () {
      expect(CsvExporter.quoteCsvCell('a,b'), '"a,b"');
    });

    test('field with double-quote escapes it and wraps', () {
      expect(CsvExporter.quoteCsvCell('say "hi"'), '"say ""hi"""');
    });

    test('field with only double-quote is escaped', () {
      expect(CsvExporter.quoteCsvCell('"'), '""""');
    });

    test('field with newline is wrapped', () {
      expect(CsvExporter.quoteCsvCell('line1\nline2'), '"line1\nline2"');
    });

    test('field with carriage return is wrapped', () {
      expect(CsvExporter.quoteCsvCell('a\rb'), '"a\rb"');
    });

    test('field with no special chars is not quoted', () {
      expect(CsvExporter.quoteCsvCell('open'), 'open');
      expect(CsvExporter.quoteCsvCell('2025-03-28'), '2025-03-28');
    });

    test('field with comma and double-quote is fully escaped', () {
      expect(CsvExporter.quoteCsvCell('he said, "hello"'), '"he said, ""hello"""');
    });
  });

  group('CsvExporter.buildCsv', () {
    test('empty list produces empty string', () {
      expect(CsvExporter.buildCsv([]), '');
    });

    test('single cell, no quoting', () {
      expect(CsvExporter.buildCsv([['value']]), 'value');
    });

    test('header + data row are CRLF separated', () {
      final csv = CsvExporter.buildCsv([
        ['name', 'status'],
        ['Risk 1', 'open'],
      ]);
      expect(csv, 'name,status\r\nRisk 1,open');
    });

    test('cells with commas are quoted', () {
      final csv = CsvExporter.buildCsv([
        ['desc'],
        ['a, b'],
      ]);
      final lines = csv.split('\r\n');
      expect(lines[1], '"a, b"');
    });

    test('multiple rows produce correct line count', () {
      final csv = CsvExporter.buildCsv([
        ['h1', 'h2'],
        ['r1c1', 'r1c2'],
        ['r2c1', 'r2c2'],
      ]);
      final lines = csv.split('\r\n');
      expect(lines.length, 3);
      expect(lines[0], 'h1,h2');
      expect(lines[1], 'r1c1,r1c2');
      expect(lines[2], 'r2c1,r2c2');
    });

    test('header-only row (no data) produces one line', () {
      final csv = CsvExporter.buildCsv([
        ['ref', 'description', 'status'],
      ]);
      expect(csv.split('\r\n').length, 1);
      expect(csv, 'ref,description,status');
    });

    test('null-equivalent empty fields produce correct CSV', () {
      final csv = CsvExporter.buildCsv([
        ['ref', 'owner'],
        ['RS01', ''],
      ]);
      expect(csv.split('\r\n')[1], 'RS01,');
    });
  });
}
