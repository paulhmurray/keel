import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/inbox/inbox_item_draft.dart';

void main() {
  group('InboxItemDraft — construction', () {
    test('stores all fields', () {
      const draft = InboxItemDraft(
        rawText: 'Check the risk register',
        parsedType: 'risk',
        parsedData: {'description': 'Check the risk register', 'status': 'open'},
        suggestedPersonName: 'Alice',
      );
      expect(draft.rawText, 'Check the risk register');
      expect(draft.parsedType, 'risk');
      expect(draft.parsedData['status'], 'open');
      expect(draft.suggestedPersonName, 'Alice');
    });

    test('parsedData defaults to empty map', () {
      const draft = InboxItemDraft(rawText: 'note', parsedType: 'note');
      expect(draft.parsedData, isEmpty);
    });

    test('suggestedPersonName defaults to null', () {
      const draft = InboxItemDraft(rawText: 'note', parsedType: 'note');
      expect(draft.suggestedPersonName, isNull);
    });
  });

  group('InboxItemDraft — toJsonString', () {
    test('serialises parsedData to JSON', () {
      const draft = InboxItemDraft(
        rawText: 'risk',
        parsedType: 'risk',
        parsedData: {'description': 'A risk', 'likelihood': 'high'},
      );
      final json = jsonDecode(draft.toJsonString()) as Map<String, dynamic>;
      expect(json['description'], 'A risk');
      expect(json['likelihood'], 'high');
    });

    test('empty parsedData serialises to {}', () {
      const draft = InboxItemDraft(rawText: 'x', parsedType: 'note');
      expect(draft.toJsonString(), '{}');
    });
  });

  group('InboxItemDraft — copyWith', () {
    test('copyWith overrides specified fields', () {
      const original = InboxItemDraft(
        rawText: 'original text',
        parsedType: 'note',
        suggestedPersonName: 'Bob',
      );
      final copy = original.copyWith(parsedType: 'risk', suggestedPersonName: 'Carol');
      expect(copy.rawText, 'original text'); // unchanged
      expect(copy.parsedType, 'risk');        // changed
      expect(copy.suggestedPersonName, 'Carol'); // changed
    });

    test('copyWith with no args is equivalent', () {
      const original = InboxItemDraft(
        rawText: 'text',
        parsedType: 'action',
        suggestedPersonName: 'Dave',
      );
      final copy = original.copyWith();
      expect(copy.rawText, original.rawText);
      expect(copy.parsedType, original.parsedType);
      expect(copy.suggestedPersonName, original.suggestedPersonName);
    });
  });

  group('InboxItemDraft — toString', () {
    test('includes type and person', () {
      const draft = InboxItemDraft(
        rawText: 'short text',
        parsedType: 'action',
        suggestedPersonName: 'Eve',
      );
      expect(draft.toString(), contains('action'));
      expect(draft.toString(), contains('Eve'));
    });

    test('truncates rawText at 60 chars in toString', () {
      final longText = 'A' * 80;
      final draft = InboxItemDraft(rawText: longText, parsedType: 'note');
      expect(draft.toString(), isNot(contains('A' * 70)));
    });
  });
}
