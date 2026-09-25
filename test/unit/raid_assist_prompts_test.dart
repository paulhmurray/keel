import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/llm/raid_assist_prompts.dart';

void main() {
  group('riskAssistPrompt', () {
    test('mitigation prompt carries the risk fields and asks for bullets',
        () {
      final p = riskAssistPrompt(
        field: RiskAssistField.mitigation,
        description: 'Vendor may miss the API delivery',
        likelihood: 'high',
        impact: 'medium',
        likelihoodRationale: 'They slipped twice already',
        impactRationale: 'Blocks integration testing',
        owner: 'Sam',
      );
      expect(p.user, contains('Vendor may miss the API delivery'));
      expect(p.user, contains('Likelihood rating: high'));
      expect(p.user, contains('Impact rating: medium'));
      expect(p.user, contains('They slipped twice already'));
      expect(p.user, contains('Blocks integration testing'));
      expect(p.user, contains('Owner: Sam'));
      expect(p.user, contains('3-5 short bullet points'));
      expect(p.user, contains('early warning'));
    });

    test('the field being drafted is not echoed back as "existing"', () {
      final p = riskAssistPrompt(
        field: RiskAssistField.likelihoodRationale,
        description: 'd',
        likelihood: 'low',
        impact: 'low',
        likelihoodRationale: 'OLD LIKELIHOOD TEXT',
        impactRationale: 'old impact text',
      );
      expect(p.user, isNot(contains('OLD LIKELIHOOD TEXT')));
      expect(p.user, contains('old impact text'));
      expect(p.user, contains('Why this likelihood?'));
      expect(p.user, contains('low likelihood'));
    });

    test('impact rationale names the rating being justified', () {
      final p = riskAssistPrompt(
        field: RiskAssistField.impactRationale,
        description: 'd',
        likelihood: 'low',
        impact: 'high',
      );
      expect(p.user, contains('rated high'));
    });

    test('empty optional fields are omitted rather than printed blank', () {
      final p = riskAssistPrompt(
        field: RiskAssistField.mitigation,
        description: 'd',
        likelihood: 'low',
        impact: 'low',
        owner: '   ',
        mitigation: '',
      );
      expect(p.user, isNot(contains('Owner:')));
      expect(p.user, isNot(contains('Mitigation (existing)')));
    });

    test('system prompt is the persona alone without project context', () {
      final p = riskAssistPrompt(
        field: RiskAssistField.mitigation,
        description: 'd',
        likelihood: 'low',
        impact: 'low',
      );
      expect(p.system, contains('Never invent facts'));
      expect(p.system, isNot(contains('---')));
    });

    test('project context is prepended to the persona when supplied', () {
      final p = riskAssistPrompt(
        field: RiskAssistField.mitigation,
        description: 'd',
        likelihood: 'low',
        impact: 'low',
        projectContext: '## Current Project\nName: Apollo',
      );
      expect(p.system, startsWith('## Current Project'));
      expect(p.system, contains('Name: Apollo'));
      expect(p.system, contains('Never invent facts'));
    });
  });

  group('issueAssistPrompt', () {
    test('impact statement prompt includes title, description and urgency',
        () {
      final p = issueAssistPrompt(
        field: IssueAssistField.impactStatement,
        title: 'Test env down',
        description: 'UAT environment has been unavailable for 3 days',
        priority: 'critical',
        status: 'open',
        dueDate: '2026-10-01',
        resolution: 'Rebuild from snapshot',
      );
      expect(p.user, contains('Title: Test env down'));
      expect(p.user, contains('UAT environment'));
      expect(p.user, contains('Priority: critical'));
      expect(p.user, contains('Due: 2026-10-01'));
      expect(p.user, contains('Resolution (existing): Rebuild from snapshot'));
      expect(p.user, contains('impact statement'));
    });

    test('resolution prompt asks for steps and a done signal', () {
      final p = issueAssistPrompt(
        field: IssueAssistField.resolution,
        description: 'd',
        priority: 'low',
        status: 'open',
        resolution: 'SHOULD NOT APPEAR',
      );
      expect(p.user, isNot(contains('SHOULD NOT APPEAR')));
      expect(p.user, contains('how we will know it is resolved'));
    });
  });

  group('dependencyAssistPrompt', () {
    test('rationale prompt includes direction, counterparty and plan link',
        () {
      final p = dependencyAssistPrompt(
        field: DependencyAssistField.rationale,
        description: 'Signed data-sharing agreement',
        dependencyType: 'inbound',
        counterparty: 'Legal',
        dueDate: '2026-11-01',
        linkedActivity: '[WP2] Data migration',
        impactStatement: 'Migration slips a month',
      );
      expect(p.user, contains('Direction: inbound'));
      expect(p.user, contains('Counterparty (who we depend on): Legal'));
      expect(p.user, contains('Plan activity it gates: [WP2] Data migration'));
      expect(p.user, contains('Impact (existing): Migration slips a month'));
      expect(p.user, contains('Why this is a dependency'));
    });

    test('impact prompt omits the existing impact and asks about slippage',
        () {
      final p = dependencyAssistPrompt(
        field: DependencyAssistField.impactStatement,
        description: 'd',
        dependencyType: 'outbound',
        impactStatement: 'OLD IMPACT',
      );
      expect(p.user, isNot(contains('OLD IMPACT')));
      expect(p.user, contains('slips or never lands'));
    });
  });

  group('decisionAssistPrompt', () {
    test('options prompt carries the decision, maker, dates and plan link',
        () {
      final p = decisionAssistPrompt(
        field: DecisionAssistField.optionsConsidered,
        description: 'Which payments gateway?',
        status: 'pending',
        decisionMaker: 'CFO',
        dueDate: '2026-10-01',
        linkedActivity: '[WP3] Checkout build',
        rationale: 'Existing rationale',
        impactStatement: 'Checkout blocked',
      );
      expect(p.user, contains('Decision required: Which payments gateway?'));
      expect(p.user, contains('Decision maker: CFO'));
      expect(p.user, contains('Needed by: 2026-10-01'));
      expect(p.user, contains('Plan activity waiting on it: [WP3] Checkout build'));
      expect(p.user, contains('Rationale (existing): Existing rationale'));
      expect(p.user, contains('do nothing / defer'));
    });

    test('each field omits its own existing text', () {
      final r = decisionAssistPrompt(
        field: DecisionAssistField.rationale,
        description: 'd',
        status: 'pending',
        rationale: 'OLD RATIONALE',
        optionsConsidered: 'old options',
      );
      expect(r.user, isNot(contains('OLD RATIONALE')));
      expect(r.user, contains('old options'));

      final i = decisionAssistPrompt(
        field: DecisionAssistField.impactStatement,
        description: 'd',
        status: 'pending',
        impactStatement: 'OLD IMPACT',
      );
      expect(i.user, isNot(contains('OLD IMPACT')));
      expect(i.user, contains('leaving this undecided'));
    });
  });
}
