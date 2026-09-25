import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/planview_risk_sheet.dart';

Risk _risk(String ref, String description, {String? title}) => Risk(
      id: ref.toLowerCase(),
      projectId: 'p',
      ref: ref,
      title: title,
      description: description,
      likelihood: 'possible',
      impact: 'major',
      status: 'open',
      strategy: 'treat',
      steerco: false,
      source: 'manual',
      createdAt: DateTime(2026, 9, 4),
      updatedAt: DateTime(2026, 9, 9),
    );

void main() {
  group('parsePlanviewDate', () {
    test('register styles and dashes', () {
      expect(parsePlanviewDate('4 Sep 26'), '2026-09-04');
      expect(parsePlanviewDate('30 Nov 26'), '2026-11-30');
      expect(parsePlanviewDate('9 Sept 2026'), '2026-09-09');
      expect(parsePlanviewDate('2026-10-09'), '2026-10-09');
      expect(parsePlanviewDate('—'), isNull);
      expect(parsePlanviewDate(null), isNull);
      expect(parsePlanviewDate('soon'), isNull);
    });

    test('formats back the same way', () {
      expect(formatPlanviewDate('2026-09-04'), '4 Sep 26');
      expect(formatPlanviewDate(null), '—');
    });
  });

  group('PlanviewRiskRow.fromCells', () {
    test('parses a register row', () {
      final row = PlanviewRiskRow.fromCells([
        'R19', '▲ ESCALATE', 'AWS connections land late',
        'Non-prod and prod Transit Gateway both land in March.',
        'Bart Fine', 'Paul Murray', 'Possible', 'Major', 'Transfer',
        'Owned by AWS Tenancy Project.', 'Possible', 'Moderate',
        '4 Sep 26', '30 Sep 26', '9 Sep 26', '23 Sep 26',
        'STEERCO — Cross-project dependency.', 'Strategic Delivery',
      ])!;
      expect(row.ref, 'R19');
      expect(row.steerco, isTrue);
      expect(row.title, 'AWS connections land late');
      expect(row.owner, 'Bart Fine');
      expect(row.assignee, 'Paul Murray');
      expect(row.likelihood, 'possible');
      expect(row.consequence, 'major');
      expect(row.strategy, 'transfer');
      expect(row.likelihoodTarget, 'possible');
      expect(row.consequenceTarget, 'moderate');
      expect(row.raisedOn, '2026-09-04');
      expect(row.dueDate, '2026-09-30');
      expect(row.nextReview, '2026-09-23');
      expect(row.enterpriseRiskLink, 'Strategic Delivery');
    });

    test('programme rows are not steerco; dashes become null', () {
      final row = PlanviewRiskRow.fromCells([
        'R26', 'programme', 'Legacy complexity', 'desc', 'Bart Fine',
        'Paul Murray', 'Likely', 'Moderate', 'Tolerate', 'Accepted.',
        'Likely', 'Minor', '4 Sep 26', '—', '9 Sep 26', '23 Sep 26', '', '',
      ])!;
      expect(row.steerco, isFalse);
      expect(row.dueDate, isNull);
      expect(row.statusNote, isNull);
    });

    test('title, legend and blank rows are skipped', () {
      expect(PlanviewRiskRow.fromCells(['Planview risk register — …']), isNull);
      expect(PlanviewRiskRow.fromCells(['REF', 'SteerCo']), isNull);
      expect(PlanviewRiskRow.fromCells(['•', 'Current rating = …']), isNull);
      expect(PlanviewRiskRow.fromCells([null, null]), isNull);
    });
  });

  group('planPlanviewImport', () {
    final sheet = [
      PlanviewRiskRow.fromCells([
        'R19', '▲ ESCALATE', 'AWS connections land late',
        'Non-prod and prod Transit Gateway both land in March, compressing test and release.',
        'Bart Fine', 'Paul Murray', 'Possible', 'Major', 'Transfer', '', '', '',
        '4 Sep 26', '', '', '', '', '',
      ])!,
      PlanviewRiskRow.fromCells([
        'R21', 'programme', 'Stubs diverge from real endpoints',
        'Integrations built against stubs behave differently against real endpoints.',
        'Bart Fine', 'Anu Verma', 'Likely', 'Major', 'Treat', '', '', '',
        '7 Sep 26', '', '', '', '', '',
      ])!,
      PlanviewRiskRow.fromCells([
        'R29', 'programme', 'Deloitte squad idle on arrival',
        'Deloitte arrives before TAC-side prerequisites are ready.',
        'Bart Fine', 'Paul Murray', 'Possible', 'Moderate', 'Treat', '', '', '',
        '7 Sep 26', '', '', '', '', '',
      ])!,
    ];
    final existing = [
      _risk('R19',
          'AWS enterprise connection delivers late March, leaving less than 2 weeks for production deployment'),
      _risk('R21',
          'Internet connectivity setup (interim) could be delayed, blocking platform enablement and build work'),
      _risk('R3', 'Something closed long ago'),
    ];

    test('same ref, same risk → update; same ref, different risk → renumber; '
        'new ref → create', () {
      final plan = planPlanviewImport(sheet, existing);
      expect(plan.map((m) => m.kind), [
        PlanviewMatchKind.update,
        PlanviewMatchKind.renumber,
        PlanviewMatchKind.create,
      ]);
      expect(plan[0].existing!.ref, 'R19');
      expect(plan[1].existing!.ref, 'R21');
      // Next free number above both the sheet's and Keel's highest.
      expect(plan[1].newRefForExisting, 'R30');
      expect(plan[2].existing, isNull);
    });

    test('untouched Keel rows are not in the plan', () {
      final plan = planPlanviewImport(sheet, existing);
      expect(plan.any((m) => m.existing?.ref == 'R3'), isFalse);
    });
  });

  group('planviewCellsFor', () {
    test('cells line up with the headers', () {
      final cells = planviewCellsFor(_risk('R1', 'Body', title: 'Head'));
      expect(cells.length, kPlanviewRiskHeaders.length);
      expect(cells[0], 'R1');
      expect(cells[1], 'programme');
      expect(cells[2], 'Head');
      expect(cells[6], 'Possible');
      expect(cells[7], 'Major');
      expect(cells[8], 'Treat');
      expect(cells[12], '4 Sep 26'); // raised on = createdAt
      expect(cells[13], '—'); // no due date
    });
  });
}
