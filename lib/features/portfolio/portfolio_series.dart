import '../../core/portfolio/portfolio_rules.dart';
import '../../core/portfolio/programme_pulse.dart';

/// One programme as the portfolio sees it: its latest pulse plus the weekly
/// history behind it, and whether it can be opened on this machine.
class ProgrammeSeries {
  final String programmeId;
  final List<ProgrammePulse> history; // oldest first, latest last
  final bool isLocal;
  const ProgrammeSeries({
    required this.programmeId,
    required this.history,
    required this.isLocal,
  });

  ProgrammePulse get latest => history.last;
  String get name =>
      latest.programmeName.isEmpty ? programmeId : latest.programmeName;
}

/// Worst health first, then name — the order a PMO reads a page in.
List<ProgrammeSeries> sortSeries(List<ProgrammeSeries> all, {DateTime? now}) {
  final out = [...all];
  out.sort((a, b) {
    final s = ragSeverity(PortfolioRules.overall(b.latest, now: now))
        .compareTo(ragSeverity(PortfolioRules.overall(a.latest, now: now)));
    if (s != 0) return s;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}
