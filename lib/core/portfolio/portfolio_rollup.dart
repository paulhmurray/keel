/// Cross-programme aggregation over decoded pulses: finance totals, the
/// portfolio's top risks, person load across programmes, completeness.
///
/// Pure functions over [ProgrammePulse] lists so the overview, the tests
/// and the future web viewer share one definition of every number.
library;

import 'dart:convert';

import '../database/database.dart';
import 'programme_pulse.dart';

/// Decodes a pulse row; a corrupt payload yields an empty pulse rather
/// than throwing, so one bad row never blanks the page.
ProgrammePulse decodePulse(PortfolioPulse row) {
  try {
    return ProgrammePulse.fromJson(
        (jsonDecode(row.payload) as Map).cast<String, dynamic>());
  } catch (_) {
    return ProgrammePulse.fromJson({
      'programme_id': row.sourceProgrammeId,
      'programme_name': row.sourceProgrammeName,
      'week_of': row.weekOf,
    });
  }
}

/// Weekly history per programme, oldest first. Keyed by programme id.
Map<String, List<ProgrammePulse>> historyByProgramme(List<PortfolioPulse> rows) {
  final out = <String, List<ProgrammePulse>>{};
  for (final r in rows) {
    out.putIfAbsent(r.sourceProgrammeId, () => []).add(decodePulse(r));
  }
  for (final list in out.values) {
    list.sort((a, b) => a.weekOf.compareTo(b.weekOf));
  }
  return out;
}

class PortfolioFinanceTotals {
  final String currency;
  final int budgetMinor;
  final int forecastMinor;
  final int actualsMinor;
  final int? varianceBp;
  final int breachingProjects;
  final int programmesIncluded;
  /// Programmes whose pulse carries finance in a different currency —
  /// shown, never silently summed.
  final List<String> excludedProgrammes;

  const PortfolioFinanceTotals({
    required this.currency,
    required this.budgetMinor,
    required this.forecastMinor,
    required this.actualsMinor,
    required this.varianceBp,
    required this.breachingProjects,
    required this.programmesIncluded,
    required this.excludedProgrammes,
  });
}

/// Sums finance over the programmes sharing the most common currency.
/// Null when no programme carries finance at all.
PortfolioFinanceTotals? rollupPortfolioFinance(Iterable<ProgrammePulse> pulses) {
  final withFinance = pulses.where((p) => p.finance != null).toList();
  if (withFinance.isEmpty) return null;
  final counts = <String, int>{};
  for (final p in withFinance) {
    final c = p.finance!.currency ?? '?';
    counts[c] = (counts[c] ?? 0) + 1;
  }
  final currency = counts.entries
      .reduce((a, b) => b.value > a.value ? b : a)
      .key;
  var budget = 0, forecast = 0, actuals = 0, breaching = 0, included = 0;
  final excluded = <String>[];
  for (final p in withFinance) {
    final f = p.finance!;
    if ((f.currency ?? '?') != currency) {
      excluded.add(p.programmeName);
      continue;
    }
    included++;
    budget += f.budgetMinor;
    forecast += f.forecastMinor;
    actuals += f.actualsMinor;
    breaching += f.breachingProjects;
  }
  return PortfolioFinanceTotals(
    currency: currency,
    budgetMinor: budget,
    forecastMinor: forecast,
    actualsMinor: actuals,
    varianceBp: budget == 0 ? null : basisPoints(forecast - budget, budget),
    breachingProjects: breaching,
    programmesIncluded: included,
    excludedProgrammes: excluded,
  );
}

/// (delta / base) in basis points, rounded half away from zero, integer
/// maths only.
int basisPoints(int delta, int base) {
  final scaled = delta * 10000;
  final q = scaled.abs() ~/ base.abs();
  final r = scaled.abs() % base.abs();
  final rounded = (r * 2 >= base.abs()) ? q + 1 : q;
  return (scaled < 0) != (base < 0) ? -rounded : rounded;
}

class PortfolioRisk {
  final PulseTopRisk risk;
  final String programmeId;
  final String programmeName;
  const PortfolioRisk(this.risk, this.programmeId, this.programmeName);
}

/// The portfolio's top risks: every programme's top list merged, ranked by
/// score, escalated first on ties, then programme name for stability.
List<PortfolioRisk> portfolioTopRisks(Iterable<ProgrammePulse> pulses, {int limit = 8}) {
  final all = <PortfolioRisk>[
    for (final p in pulses)
      for (final r in p.raid.topRisks) PortfolioRisk(r, p.programmeId, p.programmeName),
  ];
  all.sort((a, b) {
    final s = b.risk.score.compareTo(a.risk.score);
    if (s != 0) return s;
    if (a.risk.escalated != b.risk.escalated) return a.risk.escalated ? -1 : 1;
    final n = a.programmeName.compareTo(b.programmeName);
    if (n != 0) return n;
    return a.risk.title.compareTo(b.risk.title);
  });
  return all.take(limit).toList();
}

class PortfolioLoad {
  final String name;
  final int projects;
  final int programmes;
  const PortfolioLoad({required this.name, required this.projects, required this.programmes});
}

/// Person load across programmes: each pulse's top-loaded list merged by
/// normalised name, projects summed, programmes counted.
List<PortfolioLoad> portfolioLoad(Iterable<ProgrammePulse> pulses, {int limit = 8}) {
  final projects = <String, int>{};
  final programmes = <String, int>{};
  final display = <String, String>{};
  for (final p in pulses) {
    for (final person in p.flow.topLoaded) {
      final key = person.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      display.putIfAbsent(key, () => person.name.trim());
      projects[key] = (projects[key] ?? 0) + person.projects;
      programmes[key] = (programmes[key] ?? 0) + 1;
    }
  }
  final out = [
    for (final k in projects.keys)
      PortfolioLoad(name: display[k]!, projects: projects[k]!, programmes: programmes[k]!),
  ]..sort((a, b) {
      final c = b.projects.compareTo(a.projects);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  return out.take(limit).toList();
}

int averageCompleteness(Iterable<ProgrammePulse> pulses) {
  final list = pulses.toList();
  if (list.isEmpty) return 0;
  return (list.fold<int>(0, (n, p) => n + p.completeness.score) / list.length).round();
}
