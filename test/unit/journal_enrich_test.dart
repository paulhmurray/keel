import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/journal/journal_due_date.dart';
import 'package:keel/core/journal/journal_enrich.dart';
import 'package:keel/core/journal/journal_owner_resolver.dart';
import 'package:keel/core/journal/journal_parser.dart';

const _people = [
  PersonRef('Anna Kowalski', 'Vendor'),
  PersonRef('Christine Moss', 'Client'),
  PersonRef('Christopher Lane', 'Vendor'),
  PersonRef('Ben Christensen', 'Client'),
  PersonRef('Hiroshi Takeda', 'Vendor'),
  PersonRef('Sam Patel', 'Client'),
  PersonRef('Sam Ortiz', 'Client'),
];

OwnerResolution? _r(String raw, {String hint = '', String myName = ''}) =>
    resolveOwner(raw, _people, hint: hint, myName: myName);

void main() {
  group('resolveOwner', () {
    test('first name → the one person with it', () {
      expect(_r('Anna')!.name, 'Anna Kowalski');
      expect(_r('@anna')!.name, 'Anna Kowalski');
    });

    test('full name, any case', () {
      expect(_r('sam patel')!.name, 'Sam Patel');
    });

    test('surname prefix when no first name fits', () {
      expect(_r('Take')!.name, 'Hiroshi Takeda');
    });

    test('first-name matches beat surname matches', () {
      // "Chris" prefixes Christensen's surname too, but two people have it
      // as a first name — those are the candidates.
      final r = _r('Chris')!;
      expect(r.kind, OwnerMatch.ambiguous);
      expect(r.candidates, ['Christine Moss', 'Christopher Lane']);
    });

    test('organisation in the title or a bracket breaks the tie', () {
      expect(
        _r('Chris', hint: 'Catch-up with Chris[Vendor]')!.name,
        'Christopher Lane',
      );
      expect(_r('Chris (Client)')!.name, 'Christine Moss');
    });

    test('first name plus initial', () {
      expect(_r('Sam O')!.name, 'Sam Ortiz');
      expect(_r('Sam')!.kind, OwnerMatch.ambiguous);
    });

    test('groups and organisations', () {
      expect(_r('Client and Vendor')!.kind, OwnerMatch.group);
      expect(_r('Anna and Hiroshi')!.kind, OwnerMatch.group);
      expect(_r('Anna, Sam')!.kind, OwnerMatch.group);
      expect(_r('Vendor')!.kind, OwnerMatch.group);
    });

    test('Me and my own name', () {
      expect(_r('Me', myName: 'Pat Doe')!.name, 'Pat Doe');
      expect(_r('Pat', myName: 'Pat Doe')!.name, 'Pat Doe');
    });

    test('unknown and empty', () {
      expect(_r('Zed')!.kind, OwnerMatch.unknown);
      expect(_r('  '), isNull);
    });
  });

  group('normaliseDueDate', () {
    final ref = DateTime(2026, 11, 23);
    String? n(String s, {int anchor = 1}) =>
        normaliseDueDate(s, ref: ref, fyAnchorMonth: anchor);

    test('month phrases', () {
      expect(n('January 2027 planning'), '2027-01-31');
      expect(n('end of January 2027'), '2027-01-31');
      expect(n('mid-December 2026'), '2026-12-15');
      expect(n('early Feb'), '2027-02-07');
      expect(n('December'), '2026-12-31');
      expect(n('15 March 2027'), '2027-03-15');
      expect(n('March 15th, 2027'), '2027-03-15');
    });

    test('years and quarters', () {
      expect(n('end of 2026 if possible'), '2026-12-31');
      expect(n('Q1 2027 planning'), '2027-03-31');
      expect(n('Q1 FY27', anchor: 7), '2026-09-30');
      expect(n('FY27 Q3', anchor: 7), '2027-03-31');
    });

    test('numeric dates, day first', () {
      expect(n('2027-01-15'), '2027-01-15');
      expect(n('15/1/27'), '2027-01-15');
      expect(n('31/2/27'), isNull);
    });

    test('relative phrases', () {
      expect(n('end of month'), '2026-11-30');
      expect(n('this week'), '2026-11-27');
      expect(n('next week'), '2026-12-04');
    });

    test('weekdays (ref is Monday 23 Nov 2026)', () {
      expect(n('Friday'), '2026-11-27');
      expect(n('by fri'), '2026-11-27');
      expect(n('Monday'), '2026-11-23');
      expect(n('next Friday'), '2026-12-04');
      expect(n('Sunday'), '2026-11-29');
    });

    test('no date in it', () {
      expect(n('ASAP'), isNull);
      expect(n('Charter drafting completion'), isNull);
      expect(n('completion of the backlog workshop'), isNull);
      expect(n('decision pending'), isNull);
      expect(n('monthly review'), isNull);
      expect(n('friendly reminder'), isNull);
    });
  });

  group('enrichDeltas + deltaWarnings', () {
    DetectedDelta action(String? owner, String? due) => DetectedDelta(
      id: 'a',
      type: DeltaType.action,
      title: 't',
      fields: {'description': 'd', 'owner': owner, 'dueDate': due},
    );

    test('resolves owner and due date, keeping the wording', () {
      final d = action('Anna', 'January 2027 planning');
      enrichDeltas([d], people: _people, entryDate: DateTime(2026, 11, 23));
      expect(d.editFields['owner'], 'Anna Kowalski');
      expect(d.editFields['dueDate'], '2027-01-31');
      expect(d.editFields[kDueAsWritten], 'January 2027 planning');
      expect(deltaWarnings(d, people: _people), isEmpty);
    });

    test('flags what it cannot complete', () {
      final d = action('Client and Vendor', 'ASAP');
      enrichDeltas([d], people: _people, entryDate: DateTime(2026, 11, 23));
      expect(d.editFields['owner'], 'Client and Vendor');
      expect(d.editFields['dueDate'], 'ASAP');
      final w = deltaWarnings(d, people: _people);
      expect(w, hasLength(2));
      expect(w[0], contains('is a group'));
      expect(w[1], contains("isn't a date"));
    });

    test('ambiguous and unknown owners are flagged', () {
      expect(deltaWarnings(action('Chris', '2027-01-01'), people: _people), [
        contains('could be Christine Moss or Christopher Lane'),
      ]);
      expect(deltaWarnings(action('Zed', '2027-01-01'), people: _people), [
        contains("isn't in People"),
      ]);
    });

    test('an action with no owner or due date says so', () {
      expect(deltaWarnings(action(null, null), people: _people), [
        'No owner',
        'No due date',
      ]);
    });

    test('decision-makers resolve too', () {
      final d = DetectedDelta(
        id: 'd',
        type: DeltaType.decision,
        title: 't',
        fields: {'description': 'd', 'decisionMaker': 'Hiroshi'},
      );
      enrichDeltas([d], people: _people, entryDate: DateTime(2026, 11, 23));
      expect(d.editFields['decisionMaker'], 'Hiroshi Takeda');
    });
  });

  test('risk lines carry an owner', () async {
    final d = await JournalParser().parse(
      'Risk: Vendor slips. Owner: Anna | Likelihood: High | Impact: Low',
    );
    expect(d.single.fields['owner'], 'Anna');
    expect(d.single.fields['likelihood'], 'high');
    expect(d.single.fields['description'], 'Vendor slips.');
  });
}
