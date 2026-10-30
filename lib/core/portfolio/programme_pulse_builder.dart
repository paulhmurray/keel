/// Gathers the rows [computeProgrammePulse] needs from the database.
///
/// Kept apart from the pure computation so the maths stays testable with
/// hand-built rows, and apart from the cascade service so the same pulse
/// can be previewed on the programme's own overview later.
library;

import '../database/database.dart';
import '../finance/programme_rollup.dart';
import 'programme_pulse.dart';

Future<ProgrammePulseInputs?> buildProgrammePulseInputs(
  AppDatabase db,
  String programmeId,
) async {
  final programme = await db.projectDao.getProjectById(programmeId);
  if (programme == null) return null;

  final links =
      await db.programmeLinksDao.getProjectLinksForProgramme(programmeId);
  final linkedProjects = <Project>[];
  for (final l in links) {
    final pid = l.partnerLocalId;
    if (pid == null) continue;
    final p = await db.projectDao.getProjectById(pid);
    if (p != null) linkedProjects.add(p);
  }

  final fin = db.financeDao;
  final budgets = await fin.getCascadedBudgets(programmeId);
  final finance = budgets.isEmpty
      ? null
      : computeProgrammeFinance(
          categories: await fin.getCascadedCategories(programmeId),
          budgets: budgets,
          budgetLines: await fin.getCascadedBudgetLines(programmeId),
          snapshots: await fin.getCascadedSnapshots(programmeId),
          forecastLines: await fin.getCascadedForecastLines(programmeId),
          actuals: await fin.getCascadedActuals(programmeId),
          merges: await fin.getMerges(programmeId),
        );

  return ProgrammePulseInputs(
    programme: programme,
    workPackages: await db.programmeGanttDao.getWorkPackages(programmeId),
    activities: await db.programmeGanttDao.getActivitiesForProject(programmeId),
    reports: await db.reportsDao.getReportsForProject(programmeId),
    risks: await db.raidDao.getRisksForProject(programmeId),
    issues: await db.raidDao.getIssuesForProject(programmeId),
    dependencies: await db.raidDao.getDependenciesForProject(programmeId),
    decisions: await db.decisionsDao.getDecisionsForProject(programmeId),
    actions: await db.actionsDao.getActionsForProject(programmeId),
    teamRoles: await db.teamRoleDao.getForProject(programmeId),
    persons: await db.peopleDao.getPersonsForProject(programmeId),
    projectLinks: links,
    linkedProjects: linkedProjects,
    finance: finance,
  );
}
