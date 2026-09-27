import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/status/narrative_refs.dart';

void main() {
  final t0 = DateTime(2026, 9, 1);

  test('extracts codes once each, in order, without false hits', () {
    expect(
        extractRefs('DC14 gates R3; see DC14 again, AC7, and R&D spend. D2 too.'),
        ['DC14', 'R3', 'AC7', 'D2']);
    expect(extractRefs(null), isEmpty);
    expect(extractRefs('No codes here, just A4 paper'), ['A4']); // resolved later
  });

  test('resolves each code to plain words and drops unknowns', () {
    final items = resolveNarrativeRefs(
      'The build waits on DC14 and is exposed to R3 (see A4).',
      risks: [
        Risk(id: 'r', projectId: 'p', ref: 'R3', title: 'Vendor slips',
            description: 'If the vendor slips again, then SIT may start late, resulting in a four-week delay.',
            likelihood: 'likely', impact: 'major', status: 'open', source: 'manual',
            steerco: false, strategy: 'treat', owner: 'Sam', dueDate: '2026-10-03',
            createdAt: t0, updatedAt: t0),
      ],
      assumptions: const [],
      issues: const [],
      dependencies: const [],
      decisions: [
        Decision(id: 'd', projectId: 'p', ref: 'DC14',
            description: 'Where payments originate during transition',
            status: 'pending', decisionMaker: 'CFO', dueDate: '2026-10-03',
            source: 'manual', createdAt: t0, updatedAt: t0),
      ],
      actions: const [],
    );
    expect(items.map((i) => i.ref), ['DC14', 'R3']); // A4 unknown → dropped
    expect(items[0].kind, 'Decision');
    expect(items[0].headline, 'Where payments originate during transition');
    expect(items[0].detail, 'pending · decision maker CFO · needed by 2026-10-03');
    expect(items[1].kind, 'Risk');
    expect(items[1].headline, startsWith('Vendor slips. If the vendor slips again'));
    expect(items[1].detail, contains('owner Sam'));
    expect(items[1].detail, contains('treatment due 2026-10-03'));
  });

  test('a narrative with no codes resolves to nothing', () {
    expect(
        resolveNarrativeRefs('All quiet.',
            risks: const [], assumptions: const [], issues: const [],
            dependencies: const [], decisions: const [], actions: const []),
        isEmpty);
  });
}
