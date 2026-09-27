import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/raid/raid_conversion_service.dart' show RaidKind;
import 'package:keel/core/raid/raid_statements.dart';

void main() {
  List<String> hints(RaidKind k, String d,
          {String? owner = 'Paul', String? due, String? party,
          String? validatedBy, String? impact, String? title}) =>
      raidQualityHints(k,
              description: d,
              owner: owner,
              dueDate: due,
              counterparty: party,
              validatedBy: validatedBy,
              impactStatement: impact,
              title: title)
          .map((h) => h.text)
          .toList();

  group('risk', () {
    test('the house pattern is well-formed', () {
      expect(
          hints(RaidKind.risk,
              'If Salesforce do not confirm the licence-only order form by '
              '3 October, then the MuleSoft build may start without '
              'entitlements, resulting in a four-week delay to SIT.'),
          isEmpty);
    });
    test('a bare "Risk of delays" is too short; a slightly longer one gets '
        'the opener and structure hints', () {
      expect(hints(RaidKind.risk, 'Risk of delays to vendor build'),
          [contains('Too short')]);
      final h = hints(RaidKind.risk, 'Risk of delays to the vendor build phase');
      expect(h.any((t) => t.contains('Drop "Risk of…"')), isTrue);
      expect(h.any((t) => t.contains('Name the cause')), isTrue);
    });
    test('missing cause, event and impact are each named', () {
      final h = hints(RaidKind.risk,
          'The vendor build phase is running late and the team is stretched.');
      expect(h.any((t) => t.contains('Name the cause')), isTrue);
      expect(h.any((t) => t.contains('uncertain event')), isTrue);
      expect(h.any((t) => t.contains('what it hits')), isTrue);
    });
    test('"Risk of…" opener and vague nouns are polish hints', () {
      final all = raidQualityHints(RaidKind.risk,
          description: 'Risk of issues with resources if the vendor slips, '
              'then testing may be delayed',
          owner: 'Paul');
      expect(all.where((h) => h.severity == 1).map((h) => h.text),
          anyElement(contains('Drop "Risk of…"')));
      expect(all.map((h) => h.text), anyElement(contains('Vague')));
    });
    test('no owner is a polish hint; empty description says nothing', () {
      expect(hints(RaidKind.risk, 'If x fails, then y may occur, resulting in z delay to the plan', owner: null),
          [contains('No owner')]);
      expect(hints(RaidKind.risk, '   '), isEmpty);
    });
  });

  group('issue', () {
    test('risk language in an issue is called out', () {
      final h = hints(RaidKind.issue,
          'The vendor may miss the API delivery date which could delay testing',
          due: '2026-10-01');
      expect(h.any((t) => t.contains('reads like a risk')), isTrue);
    });
    test('present tense with cause, impact and a date is well-formed', () {
      expect(
          hints(RaidKind.issue,
              'The API contract has not been signed because legal is '
              'reviewing the liability clause. It is blocking the '
              'integration build, so sign-off is needed by 3 October.',
              due: '2026-10-03'),
          isEmpty);
    });
    test('impact can live in the impact statement field', () {
      final h = hints(RaidKind.issue,
          'The contract has not been signed because legal is reviewing it.',
          due: '2026-10-03', impact: 'Blocks the build');
      expect(h, isEmpty);
    });
  });

  group('assumption', () {
    test('basis, consequence and validation are each required', () {
      final h = hints(RaidKind.assumption,
          'The Tenzing environment will be available for the whole of Q4.');
      expect(h.any((t) => t.contains('why you believe')), isTrue);
      expect(h.any((t) => t.contains('breaks if')), isTrue);
      expect(h.any((t) => t.contains('validated')), isTrue);
    });
    test('the pattern passes; a validatedBy field satisfies validation', () {
      expect(
          hints(RaidKind.assumption,
              'We are assuming the Tenzing environment is available all of '
              'Q4 because the vendor roadmap says so. If this proves false, '
              'SIT slips a month. Validated by the vendor PM by 10 October.'),
          isEmpty);
      expect(
          hints(RaidKind.assumption,
              'We are assuming the environment is available because the '
              'roadmap says so; if not, SIT slips a month.',
              validatedBy: 'Vendor PM'),
          isEmpty);
    });
  });

  group('dependency', () {
    test('needs a counterparty, a date and an impact', () {
      final h = hints(RaidKind.dependency,
          'Signed API contract covering the integration layer and sandbox access.');
      expect(h.any((t) => t.contains('counterparty')), isTrue);
      expect(h.any((t) => t.contains('needed-by date')), isTrue);
      expect(h.any((t) => t.contains('gates')), isTrue);
    });
    test('fields satisfy what the text leaves out', () {
      expect(
          hints(RaidKind.dependency,
              'Signed API contract for the integration layer so that the '
              'build can start.',
              party: 'Salesforce', due: '2026-10-03'),
          isEmpty);
    });
  });

  test('every kind but decision has a pattern and a why', () {
    for (final k in RaidKind.values.where((k) => k != RaidKind.decision)) {
      expect(kRaidStatementPatterns[k], isNotNull);
      expect(kRaidStatementWhy[k], isNotNull);
    }
  });
}
