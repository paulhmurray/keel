import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/inbox/parsers/org_parser.dart';

void main() {
  late OrgParser parser;

  setUp(() => parser = OrgParser());

  group('OrgParser — empty input', () {
    test('returns empty list for empty string', () {
      expect(parser.parse(''), isEmpty);
    });

    test('ignores blank lines', () {
      expect(parser.parse('\n\n\n'), isEmpty);
    });
  });

  group('OrgParser — TODO headings', () {
    test('* TODO heading → todo type', () {
      final items = parser.parse('* TODO Write the ADR');
      expect(items.length, 1);
      expect(items.first.parsedType, 'todo');
      expect(items.first.rawText, 'Write the ADR');
    });

    test('* DONE heading → skipped', () {
      final items = parser.parse('* DONE Old completed task');
      expect(items, isEmpty);
    });

    test('* CANCELLED heading → skipped', () {
      final items = parser.parse('* CANCELLED Dropped scope');
      expect(items, isEmpty);
    });

    test('* NEXT heading → todo', () {
      final items = parser.parse('* NEXT Prepare slides');
      expect(items.first.parsedType, 'todo');
    });

    test('* WAITING heading → todo', () {
      final items = parser.parse('* WAITING Response from vendor');
      expect(items.first.parsedType, 'todo');
    });
  });

  group('OrgParser — RISK / DECISION / ACTION headings', () {
    test('* RISK heading → risk', () {
      final items = parser.parse('* RISK Vendor may miss deadline');
      expect(items.first.parsedType, 'risk');
      expect(items.first.parsedData['likelihood'], 'medium');
      expect(items.first.parsedData['impact'], 'medium');
    });

    test('* DECISION heading → decision', () {
      final items = parser.parse('* DECISION Adopt Kubernetes');
      expect(items.first.parsedType, 'decision');
      expect(items.first.parsedData['status'], 'pending');
    });

    test('* ACTION heading → action', () {
      final items = parser.parse('* ACTION Send status update');
      expect(items.first.parsedType, 'action');
    });

    test('heading title containing RISK keyword → risk', () {
      final items = parser.parse('* Programme risk review');
      expect(items.first.parsedType, 'risk');
    });

    test('heading title containing DECISION keyword → decision', () {
      final items = parser.parse('* Pending decision on architecture');
      expect(items.first.parsedType, 'decision');
    });
  });

  group('OrgParser — sub-headings → context', () {
    test('** sub-heading → context', () {
      final items = parser.parse('** Background information');
      expect(items.first.parsedType, 'context');
    });

    test('*** deeper heading → context', () {
      final items = parser.parse('*** Technical detail');
      expect(items.first.parsedType, 'context');
    });
  });

  group('OrgParser — SCHEDULED / DEADLINE extraction', () {
    test('DEADLINE date appears in parsedData', () {
      const input = '''
* TODO Finish report
DEADLINE: <2025-06-30>
''';
      final items = parser.parse(input);
      expect(items.first.parsedData['due_date'], '2025-06-30');
    });

    test('SCHEDULED date used when no DEADLINE', () {
      const input = '''
* TODO Planning session
SCHEDULED: <2025-07-01>
''';
      final items = parser.parse(input);
      expect(items.first.parsedData['due_date'], '2025-07-01');
    });

    test('DEADLINE takes precedence over SCHEDULED', () {
      const input = '''
* TODO Do something
SCHEDULED: <2025-07-01>
DEADLINE: <2025-06-15>
''';
      final items = parser.parse(input);
      expect(items.first.parsedData['due_date'], '2025-06-15');
    });
  });

  group('OrgParser — PROPERTIES block', () {
    test(':OWNER: is extracted as suggestedPersonName', () {
      const input = '''
* TODO Prepare budget
:PROPERTIES:
:OWNER: Alice Johnson
:END:
''';
      final items = parser.parse(input);
      expect(items.first.suggestedPersonName, 'Alice Johnson');
    });

    test(':ASSIGNEE: is also recognised', () {
      const input = '''
* TODO Deploy fix
:PROPERTIES:
:ASSIGNEE: Bob
:END:
''';
      final items = parser.parse(input);
      expect(items.first.suggestedPersonName, 'Bob');
    });
  });

  group('OrgParser — @name detection', () {
    test('@name in TODO heading title', () {
      final items = parser.parse('* TODO Review with @carol');
      expect(items.first.suggestedPersonName, 'carol');
    });
  });

  group('OrgParser — plain list items and paragraphs', () {
    test('- list item → note', () {
      final items = parser.parse('- Important observation about the client');
      expect(items.first.parsedType, 'note');
    });

    test('plain paragraph text → note', () {
      final items = parser.parse('Meeting went well overall');
      expect(items.first.parsedType, 'note');
    });

    test('metadata lines are skipped', () {
      const input = '''
#+TITLE: My notes
SCHEDULED: <2025-01-01>
:PROPERTIES:
:END:
''';
      expect(parser.parse(input), isEmpty);
    });
  });

  group('OrgParser — mixed real-world content', () {
    test('parses a realistic org file', () {
      const input = '''
#+TITLE: Week 12 notes

* Programme risk review
:PROPERTIES:
:OWNER: Sarah
:END:

* TODO Send status report to sponsor
DEADLINE: <2025-03-28>

* DONE Completed last week

** Background context

- Spoke with the client about timeline
''';
      final items = parser.parse(input);
      final types = items.map((i) => i.parsedType).toList();

      expect(types.contains('risk'), isTrue);
      expect(types.contains('todo'), isTrue);
      expect(types.contains('context'), isTrue);
      expect(types.contains('note'), isTrue);
      // DONE is skipped
      expect(items.where((i) => i.rawText == 'Completed last week'), isEmpty);

      final todo = items.firstWhere((i) => i.parsedType == 'todo');
      expect(todo.parsedData['due_date'], '2025-03-28');

      final risk = items.firstWhere((i) => i.parsedType == 'risk');
      expect(risk.suggestedPersonName, 'Sarah');
    });
  });
}
