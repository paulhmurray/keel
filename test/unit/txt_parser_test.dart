import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/inbox/parsers/txt_parser.dart';

void main() {
  late TxtParser parser;

  setUp(() => parser = TxtParser());

  group('TxtParser — empty / blank input', () {
    test('returns empty list for empty string', () {
      expect(parser.parse(''), isEmpty);
    });

    test('ignores blank lines', () {
      expect(parser.parse('\n\n\n'), isEmpty);
    });
  });

  group('TxtParser — keyword-prefixed lines', () {
    test('TODO: prefix → todo type', () {
      final items = parser.parse('TODO: Follow up with steering committee');
      expect(items.length, 1);
      expect(items.first.parsedType, 'todo');
      expect(items.first.rawText, 'Follow up with steering committee');
    });

    test('ACTION: prefix → action type', () {
      final items = parser.parse('ACTION: Send the risk report');
      expect(items.first.parsedType, 'action');
    });

    test('RISK: prefix → risk type', () {
      final items = parser.parse('RISK: Vendor delivery slipping');
      expect(items.first.parsedType, 'risk');
      expect(items.first.parsedData['likelihood'], 'medium');
      expect(items.first.parsedData['impact'], 'medium');
    });

    test('DECISION: prefix → decision type', () {
      final items = parser.parse('DECISION: Approve new architecture');
      expect(items.first.parsedType, 'decision');
      expect(items.first.parsedData['status'], 'pending');
    });

    test('keywords are case-insensitive', () {
      final items = parser.parse('risk: Something bad might happen');
      expect(items.first.parsedType, 'risk');
    });
  });

  group('TxtParser — checkboxes', () {
    test('open checkbox [ ] → todo', () {
      final items = parser.parse('[ ] Buy milk');
      expect(items.length, 1);
      expect(items.first.parsedType, 'todo');
      expect(items.first.rawText, 'Buy milk');
    });

    test('open checkbox with dash prefix → todo', () {
      final items = parser.parse('- [ ] Send report');
      expect(items.first.parsedType, 'todo');
    });

    test('completed checkbox [x] → skipped', () {
      final items = parser.parse('[x] Already done');
      expect(items, isEmpty);
    });

    test('completed checkbox with dash prefix → skipped', () {
      final items = parser.parse('- [x] Done task');
      expect(items, isEmpty);
    });
  });

  group('TxtParser — plain text → note', () {
    test('unrecognised line becomes a note', () {
      final items = parser.parse('Met with the client today');
      expect(items.first.parsedType, 'note');
      expect(items.first.rawText, 'Met with the client today');
    });
  });

  group('TxtParser — person detection', () {
    test('detects @name mention', () {
      final items = parser.parse('ACTION: Review specs @alice');
      expect(items.first.suggestedPersonName, 'alice');
    });

    test('detects Owner: Name pattern', () {
      final items = parser.parse('ACTION: Deploy service Owner: Bob Smith');
      expect(items.first.suggestedPersonName, 'Bob Smith');
    });

    test('Owner: takes precedence over @name', () {
      // Owner: regex captures to end-of-line, so the full value includes @dave.
      // The important thing is Owner: is used, not the @name match.
      final items = parser.parse('ACTION: Deploy Owner: Charlie @dave');
      expect(items.first.suggestedPersonName, startsWith('Charlie'));
    });

    test('no person gives null', () {
      final items = parser.parse('TODO: Plain task');
      expect(items.first.suggestedPersonName, isNull);
    });
  });

  group('TxtParser — multiple lines', () {
    test('parses multiple lines independently', () {
      const input = '''
TODO: First task
RISK: A risk here
Met with stakeholders
[x] Already done
[ ] Open checkbox
''';
      final items = parser.parse(input);
      expect(items.length, 4); // completed checkbox skipped
      expect(items[0].parsedType, 'todo');
      expect(items[1].parsedType, 'risk');
      expect(items[2].parsedType, 'note');
      expect(items[3].parsedType, 'todo');
    });
  });

  group('TxtParser — sourceLabel', () {
    test('sourceLabel is included in parsedData when provided', () {
      final items = parser.parse('A note', sourceLabel: 'meeting.txt');
      expect(items.first.parsedData['source_label'], 'meeting.txt');
    });

    test('no sourceLabel key when not provided', () {
      final items = parser.parse('A note');
      expect(items.first.parsedData.containsKey('source_label'), isFalse);
    });
  });
}
