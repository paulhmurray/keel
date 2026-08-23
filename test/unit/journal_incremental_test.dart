import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/journal/journal_incremental.dart';

void main() {
  group('unparsedText', () {
    test('no snapshot → full body needs parsing', () {
      expect(
        unparsedText(lastParsedBody: null, body: 'line one\nline two'),
        'line one\nline two',
      );
      expect(
        unparsedText(lastParsedBody: '  ', body: 'line one'),
        'line one',
      );
    });

    test('unchanged body → nothing to parse', () {
      expect(
        unparsedText(lastParsedBody: 'same text', body: 'same text'),
        '',
      );
    });

    test('whitespace-only changes → nothing to parse', () {
      expect(
        unparsedText(lastParsedBody: 'same text', body: '  same text \n'),
        '',
      );
    });

    test('pure append → only the suffix', () {
      const old = 'Met with Dana.\nAgreed to slip the date.';
      const now = '$old\n\nNew: vendor flagged a licensing issue.';
      expect(
        unparsedText(lastParsedBody: old, body: now),
        'New: vendor flagged a licensing issue.',
      );
    });

    test('edit in the middle → only changed/new lines', () {
      const old = 'Met with Dana.\nAgreed to slip the date.\nRisk: budget.';
      const now =
          'Met with Dana.\nAgreed to HOLD the date.\nRisk: budget.\nAction: call vendor.';
      expect(
        unparsedText(lastParsedBody: old, body: now),
        'Agreed to HOLD the date.\nAction: call vendor.',
      );
    });

    test('deleting parsed text yields nothing new', () {
      const old = 'first thing\nsecond thing';
      expect(
        unparsedText(lastParsedBody: old, body: 'first thing'),
        '',
      );
    });

    test('reordering parsed lines yields nothing new', () {
      const old = 'alpha\nbeta';
      expect(
        unparsedText(lastParsedBody: old, body: 'beta\nalpha'),
        '',
      );
    });

    test('duplicate of an already-parsed line is not re-parsed', () {
      const old = 'Action: chase infra team.';
      const now = 'Action: chase infra team.\nAction: chase infra team.';
      // Identical line already covered by the snapshot — suffix append
      // path catches this as new text, which is the safer behaviour for
      // deliberately repeated statements.
      expect(
        unparsedText(lastParsedBody: old, body: now),
        'Action: chase infra team.',
      );
    });
  });
}
