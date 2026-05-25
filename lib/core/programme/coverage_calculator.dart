import '../database/database.dart';

class CoverageResult {
  final int filled;
  final int defined;
  final int applicable;
  final double percentage;
  final double definedPercentage;
  final List<String> missingRoles;

  const CoverageResult({
    required this.filled,
    required this.defined,
    required this.applicable,
    required this.percentage,
    required this.definedPercentage,
    required this.missingRoles,
  });

  bool get isFull => applicable > 0 && filled == applicable;
  bool get isEmpty => filled == 0;
}

class CoverageCalculator {
  static CoverageResult forStakeholders(List<StakeholderRole> roles) {
    final applicable = roles.where((r) => r.isApplicable).toList();
    final filled = applicable.where((r) => r.personId != null).toList();
    final defined = applicable.where(_isStakeholderEngaged).toList();
    final missing = applicable
        .where((r) => r.personId == null && r.isScaffold)
        .map((r) => r.roleName)
        .toList();
    final filledPct = applicable.isEmpty ? 0.0 : filled.length / applicable.length;
    final definedPct = applicable.isEmpty ? 0.0 : defined.length / applicable.length;
    return CoverageResult(
      filled: filled.length,
      defined: defined.length,
      applicable: applicable.length,
      percentage: filledPct,
      definedPercentage: definedPct,
      missingRoles: missing,
    );
  }

  static CoverageResult forTeam(List<TeamRole> roles) {
    final applicable = roles.where((r) => r.isApplicable).toList();
    final filled = applicable.where((r) => r.personId != null).toList();
    // Team rows have no engagement metadata, so a role counts as "defined"
    // when it's been assigned or is a user-added custom role.
    final defined = applicable
        .where((r) => r.personId != null || !r.isScaffold)
        .toList();
    final missing = applicable
        .where((r) => r.personId == null && r.isScaffold)
        .map((r) => r.roleName)
        .toList();
    final filledPct = applicable.isEmpty ? 0.0 : filled.length / applicable.length;
    final definedPct = applicable.isEmpty ? 0.0 : defined.length / applicable.length;
    return CoverageResult(
      filled: filled.length,
      defined: defined.length,
      applicable: applicable.length,
      percentage: filledPct,
      definedPercentage: definedPct,
      missingRoles: missing,
    );
  }

  // A stakeholder role counts as "defined" when the user has engaged with it
  // somehow — assigned a person, added it as a custom role, or filled in any
  // of the engagement metadata fields.
  static bool _isStakeholderEngaged(StakeholderRole r) {
    if (r.personId != null) return true;
    if (!r.isScaffold) return true;
    if (r.engagementStatus != null) return true;
    if (r.priority != null) return true;
    if (r.functionalArea != null) return true;
    if (r.integrationRelevance != null) return true;
    if (r.gapFlag) return true;
    return false;
  }
}
