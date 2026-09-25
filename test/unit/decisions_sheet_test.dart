import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/decisions_sheet.dart';

Decision _d(String ref, String desc, {String status = 'decided', String? maker}) =>
    Decision(
      id: 'id-$ref',
      projectId: 'p',
      ref: ref,
      description: desc,
      status: status,
      decisionMaker: maker,
      source: 'journal',
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    );

void main() {
  group('parseNeededBy', () {
    test('month-year → last day of month; exact and ISO pass through', () {
      expect(parseNeededBy('Nov 26'), '2026-11-30');
      expect(parseNeededBy('Jun 27'), '2027-06-30');
      expect(parseNeededBy('18 Sep 26'), '2026-09-18');
      expect(parseNeededBy('2026-10-09'), '2026-10-09');
      expect(parseNeededBy('Kick-off (Oct 26)'), '2026-10-31');
      expect(parseNeededBy('At contract execution'), isNull);
      expect(parseNeededBy(null), isNull);
    });
  });

  group('SheetDecisionRow.fromCells', () {
    test('parses a DEC row and skips headers and actions', () {
      final r = SheetDecisionRow.fromCells([
        'DEC4', 'Target connectivity pattern approved by IT Security',
        'Petra Claessens', 'Nov 26', 'Open', 'No interim pattern.',
      ])!;
      expect(r.sheetRef, 'DEC4');
      expect(r.decisionMaker, 'Petra Claessens');
      expect(r.neededBy, '2026-11-30');
      expect(r.status, 'pending');
      expect(r.context, 'No interim pattern.');
      expect(SheetDecisionRow.fromCells(['#', 'DECISION']), isNull);
      expect(SheetDecisionRow.fromCells(['3.0', 'Brief Petra…']), isNull);
      expect(SheetDecisionRow.fromCells(['Open decisions']), isNull);
    });

    test('status words', () {
      expect(normaliseDecisionStatus('Open'), 'pending');
      expect(normaliseDecisionStatus('Decided'), 'decided');
      expect(normaliseDecisionStatus('Deferred'), 'deferred');
      expect(normaliseDecisionStatus(null), 'pending');
    });
  });

  group('planDecisionsImport', () {
    final existing = [
      _d('DC14', 'Where are payments coming from - one side Avanti and other '
          'side DCP. This would come from post discovery of DCP work.',
          maker: 'Joshua Ly'),
      _d('DC16', 'eHealth need to change from a push to a pull. If eHealth '
          "don't agree, we need an alternative solution."),
      _d('DC2', 'CEO brief for the Mulesoft integration platform procurement '
          'has been signed by Paul Brookless'),
    ];
    final rows = [
      SheetDecisionRow.fromCells([
        'DEC1', 'Where payments originate during transition — Avanti or Claims '
            'Platform (all payments route via Westpac)',
        'Joshua Ly', 'Nov 26', 'Open', 'Gates P3 Payments build.',
      ])!,
      SheetDecisionRow.fromCells([
        'DEC3', 'eHealth push-to-pull change agreed, or alternative solution adopted',
        'Anu Verma', 'Oct 26', 'Open', 'Gates P2.',
      ])!,
      SheetDecisionRow.fromCells([
        'DEC6', 'Governance naming — is "ARC" a real approval body, or should '
            'the plan read DRC only',
        'Paul Murray', '18 Sep 26', 'Open', 'Consistency.',
      ])!,
    ];

    test('reworded existing decisions update; genuinely new ones create', () {
      final plan = planDecisionsImport(rows, existing);
      expect(plan.map((m) => m.kind), [
        DecisionMatchKind.update,
        DecisionMatchKind.update,
        DecisionMatchKind.create,
      ]);
      expect(plan[0].existing!.ref, 'DC14');
      expect(plan[1].existing!.ref, 'DC16');
    });

    test('a Keel decision is matched at most once', () {
      final twice = [rows[0], rows[0]];
      final plan = planDecisionsImport(twice, existing);
      expect(plan.where((m) => m.kind == DecisionMatchKind.update), hasLength(1));
    });
  });

  group('applyDecisionsImport', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.memory();
      await db.into(db.projects).insert(
          ProjectsCompanion.insert(id: 'p', name: 'P'));
      await db.decisionsDao.upsertDecision(const DecisionsCompanion(
        id: Value('k16'),
        projectId: Value('p'),
        ref: Value('DC16'),
        description: Value('eHealth need to change from a push to a pull.'),
        status: Value('decided'),
        decidedAt: Value('2026-08-27'),
        rationale: Value('Keep this'),
        source: Value('journal'),
      ));
      await db.decisionsDao.upsertDecision(const DecisionsCompanion(
        id: Value('k18'),
        projectId: Value('p'),
        ref: Value('DC18'),
        description: Value('Deloitte accepted contract amendments'),
        status: Value('decided'),
      ));
    });
    tearDown(() => db.close());

    test('update reopens with the sheet fields and keeps rationale; create '
        'takes the next DC ref', () async {
      final rows = [
        SheetDecisionRow.fromCells([
          'DEC3', 'eHealth push-to-pull change agreed, or alternative solution adopted',
          'Anu Verma (with eHealth)', 'Oct 26', 'Open', 'Gates P2 External parties build.',
        ])!,
        SheetDecisionRow.fromCells([
          'DEC5', 'Managed services option post-Deloitte (Bronze / Silver / Gold)',
          'Bart Fine', 'Jun 27', 'Open', 'Three months before Deloitte exit.',
        ])!,
      ];
      final existing = await db.decisionsDao.getDecisionsForProject('p');
      final plan = planDecisionsImport(rows, existing);
      final result = await applyDecisionsImport(db,
          projectId: 'p', plan: plan, now: DateTime(2026, 9, 25));
      expect(result.updated, 1);
      expect(result.created, 1);

      final k16 = (await db.decisionsDao.getDecisionById('k16'))!;
      expect(k16.ref, 'DC16');
      expect(k16.description, contains('push-to-pull change agreed'));
      expect(k16.status, 'pending');
      expect(k16.decidedAt, isNull); // reopened
      expect(k16.decisionMaker, 'Anu Verma (with eHealth)');
      expect(k16.dueDate, '2026-10-31');
      expect(k16.impactStatement, 'Gates P2 External parties build.');
      expect(k16.rationale, 'Keep this');
      expect(k16.sourceNote, contains('DEC3'));

      final all = await db.decisionsDao.getDecisionsForProject('p');
      final created = all.singleWhere((d) => d.ref == 'DC19');
      expect(created.description, contains('Managed services'));
      expect(created.decisionMaker, 'Bart Fine');
      expect(created.dueDate, '2027-06-30');
      expect(created.source, 'document');
    });
  });
}
