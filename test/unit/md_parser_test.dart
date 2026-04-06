import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/inbox/parsers/md_parser.dart';

void main() {
  late MdParser parser;

  setUp(() => parser = MdParser());

  group('MdParser — empty input', () {
    test('returns empty list for empty string', () {
      expect(parser.parse(''), isEmpty);
    });
  });

  group('MdParser — checkboxes', () {
    test('open checkbox - [ ] → todo', () {
      final items = parser.parse('- [ ] Write the design doc');
      expect(items.length, 1);
      expect(items.first.parsedType, 'todo');
      expect(items.first.rawText, 'Write the design doc');
    });

    test('completed checkbox - [x] → skipped', () {
      final items = parser.parse('- [x] Already shipped');
      expect(items, isEmpty);
    });

    test('case-insensitive completed checkbox', () {
      final items = parser.parse('- [X] Done');
      expect(items, isEmpty);
    });
  });

  group('MdParser — bold keyword patterns', () {
    test('**RISK:** → risk', () {
      final items = parser.parse('**RISK:** Integration may fail under load');
      expect(items.first.parsedType, 'risk');
      expect(items.first.rawText, 'Integration may fail under load');
    });

    test('**DECISION:** → decision', () {
      final items = parser.parse('**DECISION:** Use PostgreSQL for the backend');
      expect(items.first.parsedType, 'decision');
      expect(items.first.parsedData['status'], 'pending');
    });

    test('**ACTION:** → action', () {
      final items = parser.parse('**ACTION:** Review contract by Friday');
      expect(items.first.parsedType, 'action');
    });

    test('**TODO:** → action (maps to action type)', () {
      final items = parser.parse('**TODO:** Send weekly update');
      expect(items.first.parsedType, 'action');
    });

    test('bold keyword case-insensitive', () {
      final items = parser.parse('**risk:** Something could go wrong');
      expect(items.first.parsedType, 'risk');
    });
  });

  group('MdParser — blockquote keyword patterns', () {
    test('> RISK: → risk', () {
      final items = parser.parse('> RISK: Dependency on third-party API');
      expect(items.first.parsedType, 'risk');
    });

    test('> DECISION: → decision', () {
      final items = parser.parse('> DECISION: Proceed with vendor X');
      expect(items.first.parsedType, 'decision');
    });

    test('> ACTION: → action', () {
      final items = parser.parse('> ACTION: Update the runbook');
      expect(items.first.parsedType, 'action');
    });
  });

  group('MdParser — headings → context', () {
    test('# Heading → context', () {
      final items = parser.parse('# Project overview');
      expect(items.first.parsedType, 'context');
      expect(items.first.rawText, 'Project overview');
    });

    test('## Subheading → context', () {
      final items = parser.parse('## Key milestones');
      expect(items.first.parsedType, 'context');
    });
  });

  group('MdParser — list items', () {
    test('plain list item → note', () {
      final items = parser.parse('- Met with the client');
      expect(items.first.parsedType, 'note');
      expect(items.first.rawText, 'Met with the client');
    });

    test('inline keyword in list item', () {
      final items = parser.parse('- RISK: Budget overrun likely');
      expect(items.first.parsedType, 'risk');
      expect(items.first.rawText, 'Budget overrun likely');
    });
  });

  group('MdParser — person detection', () {
    test('@name in checkbox text', () {
      final items = parser.parse('- [ ] Send report @alice');
      expect(items.first.suggestedPersonName, 'alice');
    });

    test('Owner: pattern in bold keyword line', () {
      final items = parser.parse('**ACTION:** Deploy service Owner: Bob');
      expect(items.first.suggestedPersonName, 'Bob');
    });

    test('no person → null', () {
      final items = parser.parse('- [ ] Just a plain task');
      expect(items.first.suggestedPersonName, isNull);
    });
  });

  group('MdParser — mixed content', () {
    test('parses realistic meeting notes', () {
      const input = '''
# Sprint review notes

## Decisions taken
**DECISION:** Move release to next quarter

## Open actions
- [ ] Update the roadmap @sarah
- [x] Already closed task
- RISK: New vendor is unproven

Plain observation here
''';
      final items = parser.parse(input);
      final types = items.map((i) => i.parsedType).toList();
      expect(types.contains('context'), isTrue);
      expect(types.contains('decision'), isTrue);
      expect(types.contains('todo'), isTrue);
      expect(types.contains('risk'), isTrue);
      // completed checkbox excluded
      expect(items.where((i) => i.rawText == 'Already closed task'), isEmpty);
    });
  });
}
