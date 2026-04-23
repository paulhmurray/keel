import '../database/database.dart';

class CoverageResult {
  final int filled;
  final int applicable;
  final double percentage;
  final List<String> missingRoles;

  const CoverageResult({
    required this.filled,
    required this.applicable,
    required this.percentage,
    required this.missingRoles,
  });

  bool get isFull => applicable > 0 && filled == applicable;
  bool get isEmpty => filled == 0;
}

class CoverageCalculator {
  static CoverageResult forStakeholders(List<StakeholderRole> roles) {
    final scaffold = roles.where((r) => r.isScaffold).toList();
    final applicable = scaffold.where((r) => r.isApplicable).toList();
    final filled = applicable.where((r) => r.personId != null).toList();
    final missing = applicable
        .where((r) => r.personId == null)
        .map((r) => r.roleName)
        .toList();
    final pct = applicable.isEmpty ? 0.0 : filled.length / applicable.length;
    return CoverageResult(
      filled: filled.length,
      applicable: applicable.length,
      percentage: pct,
      missingRoles: missing,
    );
  }

  static CoverageResult forTeam(List<TeamRole> roles) {
    final scaffold = roles.where((r) => r.isScaffold).toList();
    final applicable = scaffold.where((r) => r.isApplicable).toList();
    final filled = applicable.where((r) => r.personId != null).toList();
    final missing = applicable
        .where((r) => r.personId == null)
        .map((r) => r.roleName)
        .toList();
    final pct = applicable.isEmpty ? 0.0 : filled.length / applicable.length;
    return CoverageResult(
      filled: filled.length,
      applicable: applicable.length,
      percentage: pct,
      missingRoles: missing,
    );
  }
}
