import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/programme/coverage_calculator.dart';

StakeholderRole _sh({
  required String id,
  String roleType = 'accountable',
  String? personId,
  bool isScaffold = true,
  bool isApplicable = true,
  String? engagementStatus,
  String? priority,
  String? functionalArea,
  String? integrationRelevance,
  bool gapFlag = false,
}) {
  final now = DateTime(2026, 1, 1);
  return StakeholderRole(
    id: id,
    projectId: 'p1',
    roleName: id,
    roleType: roleType,
    personId: personId,
    isScaffold: isScaffold,
    isApplicable: isApplicable,
    sortOrder: 0,
    engagementStatus: engagementStatus,
    priority: priority,
    functionalArea: functionalArea,
    integrationRelevance: integrationRelevance,
    gapFlag: gapFlag,
    createdAt: now,
    updatedAt: now,
  );
}

TeamRole _tm({
  required String id,
  String teamGroup = 'programme_leadership',
  String? personId,
  bool isScaffold = true,
  bool isApplicable = true,
}) {
  final now = DateTime(2026, 1, 1);
  return TeamRole(
    id: id,
    projectId: 'p1',
    roleName: id,
    teamGroup: teamGroup,
    personId: personId,
    isScaffold: isScaffold,
    isApplicable: isApplicable,
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('CoverageCalculator.forStakeholders', () {
    test('empty list yields all-zero result', () {
      final r = CoverageCalculator.forStakeholders([]);
      expect(r.applicable, 0);
      expect(r.filled, 0);
      expect(r.defined, 0);
      expect(r.percentage, 0.0);
      expect(r.definedPercentage, 0.0);
    });

    test('N/A roles excluded from denominator', () {
      final r = CoverageCalculator.forStakeholders([
        _sh(id: 'a', personId: 'p1'),
        _sh(id: 'b', isApplicable: false),
      ]);
      expect(r.applicable, 1);
      expect(r.filled, 1);
      expect(r.percentage, 1.0);
    });

    test('custom (non-scaffold) role contributes to applicable & filled', () {
      // Regression: previously isScaffold filter blocked custom roles from
      // affecting coverage. Adding a custom and assigning a person must now
      // move both the applicable count and the filled count.
      final r = CoverageCalculator.forStakeholders([
        _sh(id: 'a'),                          // scaffold, unassigned
        _sh(id: 'b', isScaffold: false, personId: 'p1'), // custom, assigned
      ]);
      expect(r.applicable, 2);
      expect(r.filled, 1);
      expect(r.percentage, 0.5);
    });

    test('definedCount includes custom roles even without person', () {
      final r = CoverageCalculator.forStakeholders([
        _sh(id: 'a'),                          // scaffold untouched → not defined
        _sh(id: 'b', isScaffold: false),       // custom, unassigned → defined
      ]);
      expect(r.applicable, 2);
      expect(r.filled, 0);
      expect(r.defined, 1);
      expect(r.definedPercentage, 0.5);
    });

    test('definedCount includes engaged scaffolds', () {
      final r = CoverageCalculator.forStakeholders([
        _sh(id: 'a', engagementStatus: 'engaged'),
        _sh(id: 'b', priority: 'critical'),
        _sh(id: 'c', functionalArea: 'Risk'),
        _sh(id: 'd', integrationRelevance: 'High'),
        _sh(id: 'e', gapFlag: true),
        _sh(id: 'f'), // untouched
      ]);
      expect(r.defined, 5);
      expect(r.filled, 0);
    });

    test('filled implies defined', () {
      final r = CoverageCalculator.forStakeholders([
        _sh(id: 'a', personId: 'p1'),
      ]);
      expect(r.filled, 1);
      expect(r.defined, 1);
    });

    test('missingRoles lists unassigned scaffold roles only', () {
      final r = CoverageCalculator.forStakeholders([
        _sh(id: 'sponsor'),
        _sh(id: 'owner', personId: 'p1'),
        _sh(id: 'custom', isScaffold: false),
      ]);
      expect(r.missingRoles, ['sponsor']);
    });
  });

  group('CoverageCalculator.forTeam', () {
    test('empty list yields all-zero result', () {
      final r = CoverageCalculator.forTeam([]);
      expect(r.applicable, 0);
      expect(r.filled, 0);
      expect(r.defined, 0);
    });

    test('custom role counts as defined and toward applicable', () {
      final r = CoverageCalculator.forTeam([
        _tm(id: 'pm'),                          // scaffold, unassigned
        _tm(id: 'extra', isScaffold: false),    // custom, unassigned
      ]);
      expect(r.applicable, 2);
      expect(r.filled, 0);
      expect(r.defined, 1);
      expect(r.definedPercentage, 0.5);
    });

    test('assigning a person to scaffold role moves filled and defined', () {
      final r = CoverageCalculator.forTeam([
        _tm(id: 'pm', personId: 'p1'),
        _tm(id: 'ba'),
      ]);
      expect(r.applicable, 2);
      expect(r.filled, 1);
      expect(r.defined, 1);
      expect(r.percentage, 0.5);
    });

    test('N/A roles excluded from all counts', () {
      final r = CoverageCalculator.forTeam([
        _tm(id: 'pm', personId: 'p1'),
        _tm(id: 'old', isApplicable: false, personId: 'p2'),
      ]);
      expect(r.applicable, 1);
      expect(r.filled, 1);
    });
  });
}
