import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/journal/journal_parser.dart';
import 'package:keel/core/llm/llm_client.dart';

/// Records what it was sent; replies with [reply] or throws [error].
class _FakeLlm implements LLMClient {
  _FakeLlm({this.reply = '{"items": []}', this.error});
  final String reply;
  final Object? error;
  final sent = <String>[];

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1000,
  }) async {
    sent.add(userMessage);
    if (error != null) throw error!;
    return reply;
  }

  @override
  Stream<String> stream({
    required String systemPrompt,
    required String userMessage,
  }) => const Stream.empty();
}

// Shaped like pasted meeting-assistant notes: plain labels, attributes
// trailing on the same line, blank lines between items.
const _plainNote = '''
Action: Alice — Draft the vendor onboarding checklist for end-to-end testing — by mid-March 2027.

Action: Ops and Vendor — Agree the support model — by ASAP.

Action: Confirm the hosting region

Decision: Releases go out fortnightly rather than monthly. Decision-maker:



Decision: We will use the shared test tenant. Decision-maker: Bob Smith (Ops)

Risk: The test tenant may not be ready in time, delaying integration. Likelihood: Medium | Impact: High



Risk: Licence costs could rise at renewal. Likelihood: High | Impact: Medium

Dependency: Integration testing depends on the vendor's sandbox. Owner: Vendor

Issue: Build server is out of disk. Owner: Ops
''';

void main() {
  group('labelled lines', () {
    test('plain labels with trailing attributes', () async {
      final d = await JournalParser().parse(_plainNote);
      List<DetectedDelta> of(DeltaType t) =>
          d.where((x) => x.type == t).toList();

      expect(of(DeltaType.action), hasLength(3));
      expect(of(DeltaType.decision), hasLength(2));
      expect(of(DeltaType.risk), hasLength(2));
      expect(of(DeltaType.dependency), hasLength(1));
      expect(of(DeltaType.issue), hasLength(1));

      final a = of(DeltaType.action);
      expect(a[0].fields['owner'], 'Alice');
      expect(
        a[0].fields['description'],
        'Draft the vendor onboarding checklist for end-to-end testing',
      );
      expect(a[0].fields['dueDate'], 'mid-March 2027');
      expect(a[1].fields['owner'], 'Ops and Vendor');
      expect(a[1].fields['dueDate'], 'ASAP');
      expect(a[2].fields['owner'], isNull);
      expect(a[2].fields['description'], 'Confirm the hosting region');

      final dec = of(DeltaType.decision);
      expect(
        dec[0].fields['description'],
        'Releases go out fortnightly rather than monthly.',
      );
      expect(dec[0].fields['decisionMaker'], isNull);
      expect(dec[1].fields['decisionMaker'], 'Bob Smith (Ops)');

      final r = of(DeltaType.risk);
      expect(r[0].fields['likelihood'], 'medium');
      expect(r[0].fields['impact'], 'high');
      expect(r[0].fields['description'], isNot(contains('Likelihood')));
      expect(r[1].fields['likelihood'], 'high');

      expect(of(DeltaType.dependency).single.fields['owner'], 'Vendor');
      expect(of(DeltaType.issue).single.fields['owner'], 'Ops');
    });

    test('ids are unique', () async {
      final d = await JournalParser().parse(_plainNote);
      expect(d.map((x) => x.id).toSet(), hasLength(d.length));
    });

    test('prose keyword rules do not double-read labelled lines', () async {
      // "may not" and "Risk" used to be picked up again as fragments.
      final d = await JournalParser().parse(_plainNote);
      expect(d, hasLength(9));
    });

    test('bold slash-command templates, attributes on the next line', () async {
      const body = '''
**Action:** @Carol — chase the SOW — by 2027-01-15
**Decision:** Go with option B
Decision-maker: Dana
**Risk:** Key person leaves

Likelihood: low | Impact: high
**Dependency:** Firewall change
Owner: Network team
''';
      final d = await JournalParser().parse(body);
      expect(d.map((x) => x.type), [
        DeltaType.action,
        DeltaType.decision,
        DeltaType.risk,
        DeltaType.dependency,
      ]);
      expect(d[0].fields['owner'], 'Carol');
      expect(d[0].fields['dueDate'], '2027-01-15');
      expect(d[1].fields['decisionMaker'], 'Dana');
      expect(d[2].fields['likelihood'], 'low');
      expect(d[2].fields['impact'], 'high');
      expect(d[3].fields['owner'], 'Network team');
    });

    test('Windows line endings', () async {
      final d = await JournalParser().parse(
        '**Decision:** Go with B\r\nDecision-maker: Dana\r\n'
        'Risk: Slippage. Likelihood: High | Impact: Low\r\n',
      );
      expect(d, hasLength(2));
      expect(d[0].fields['decisionMaker'], 'Dana');
      expect(d[1].fields['impact'], 'low');
    });

    test('unfilled template placeholders are skipped', () async {
      const body = '''
**Action:** ⟨name⟩ — ⟨task⟩ — by ⟨date⟩
**Decision:** ⟨description⟩
Decision-maker: ⟨maker⟩
''';
      expect(await JournalParser().parse(body), isEmpty);
    });

    test('remainder keeps the prose and drops labelled lines', () {
      final r = JournalParser.parseLabelled(
        'Intro line.\nAction: Eve — do it\nOwner: stray\nClosing line.',
      );
      expect(r.deltas, hasLength(1));
      expect(r.remainder, 'Intro line.\nClosing line.');
    });
  });

  group('AI path', () {
    test('only the prose goes to the AI; results are merged', () async {
      final llm = _FakeLlm(
        reply:
            '{"items":[{"type":"risk","title":"Budget pressure",'
            '"fields":{"description":"Budget pressure"}}]}',
      );
      final parser = JournalParser(llmClient: llm);
      final d = await parser.parse(
        'We talked about budget pressure.\n$_plainNote',
      );
      expect(llm.sent.single, isNot(contains('Action:')));
      expect(llm.sent.single, contains('budget pressure'));
      expect(d, hasLength(10));
      expect(d.last.title, 'Budget pressure');
      expect(d.map((x) => x.id).toSet(), hasLength(10));
      expect(parser.aiFallbackReason, isNull);
    });

    test('a fully labelled note never calls the AI', () async {
      final llm = _FakeLlm();
      final d = await JournalParser(llmClient: llm).parse(_plainNote);
      expect(llm.sent, isEmpty);
      expect(d, hasLength(9));
    });

    test('AI failure is reported and labelled lines survive', () async {
      final llm = _FakeLlm(error: Exception('No models found on the server'));
      final parser = JournalParser(llmClient: llm);
      final d = await parser.parse('Some prose.\n$_plainNote');
      expect(d, hasLength(9));
      expect(parser.aiFallbackReason, 'No models found on the server');
    });

    test('truncated AI JSON is reported as unreadable', () async {
      final parser = JournalParser(llmClient: _FakeLlm(reply: '{"items": [{'));
      await parser.parse('Some prose to send.');
      expect(parser.aiFallbackReason, contains('JSON'));
    });
  });
}
