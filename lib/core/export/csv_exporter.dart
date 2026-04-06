import 'package:archive/archive.dart';
import '../database/database.dart';
import '../platform/web_download.dart';

class CsvExporter {
  /// Export all 4 RAID tables as a ZIP of CSVs
  static Future<String> exportRaidZip({
    required String projectId,
    required AppDatabase db,
    required String projectName,
  }) async {
    final risks = await db.raidDao.getRisksForProject(projectId);
    final assumptions = await db.raidDao.getAssumptionsForProject(projectId);
    final issues = await db.raidDao.getIssuesForProject(projectId);
    final deps = await db.raidDao.getDependenciesForProject(projectId);

    final archive = Archive();
    _addCsv(archive, 'risks.csv', _risksCsv(risks));
    _addCsv(archive, 'assumptions.csv', _assumptionsCsv(assumptions));
    _addCsv(archive, 'issues.csv', _issuesCsv(issues));
    _addCsv(archive, 'dependencies.csv', _dependenciesCsv(deps));

    final zipBytes = ZipEncoder().encode(archive)!;
    final slug =
        projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final filename = 'raid_${slug}_$date.zip';
    return saveAndOpen(filename, zipBytes,
        mimeType: 'application/zip');
  }

  static Future<String> exportDecisions({
    required String projectId,
    required AppDatabase db,
    required String projectName,
  }) async {
    final decisions = await db.decisionsDao.getDecisionsForProject(projectId);
    return _writeCsvFile(_decisionsCsv(decisions), 'decisions', projectName);
  }

  static Future<String> exportActions({
    required String projectId,
    required AppDatabase db,
    required String projectName,
  }) async {
    final actions = await db.actionsDao.getActionsForProject(projectId);
    return _writeCsvFile(_actionsCsv(actions), 'actions', projectName);
  }

  static Future<String> exportPeople({
    required String projectId,
    required AppDatabase db,
    required String projectName,
  }) async {
    final persons = await db.peopleDao.getPersonsForProject(projectId);
    return _writeCsvFile(_peopleCsv(persons), 'people', projectName);
  }

  // --- CSV builders ---

  static String _risksCsv(List<Risk> items) {
    final rows = [
      [
        'ref',
        'description',
        'likelihood',
        'impact',
        'owner',
        'status',
        'mitigation',
        'source',
        'source_note'
      ],
      ...items.map((r) => [
            r.ref ?? '',
            r.description,
            r.likelihood,
            r.impact,
            r.owner ?? '',
            r.status,
            r.mitigation ?? '',
            r.source,
            r.sourceNote ?? '',
          ]),
    ];
    return buildCsv(rows);
  }

  static String _assumptionsCsv(List<Assumption> items) {
    final rows = [
      ['ref', 'description', 'owner', 'status', 'source', 'source_note'],
      ...items.map((a) => [
            a.ref ?? '',
            a.description,
            a.owner ?? '',
            a.status,
            a.source,
            a.sourceNote ?? '',
          ]),
    ];
    return buildCsv(rows);
  }

  static String _issuesCsv(List<Issue> items) {
    final rows = [
      [
        'ref',
        'description',
        'priority',
        'owner',
        'due_date',
        'status',
        'resolution',
        'source'
      ],
      ...items.map((i) => [
            i.ref ?? '',
            i.description,
            i.priority,
            i.owner ?? '',
            i.dueDate ?? '',
            i.status,
            i.resolution ?? '',
            i.source,
          ]),
    ];
    return buildCsv(rows);
  }

  static String _dependenciesCsv(List<ProgramDependency> items) {
    final rows = [
      ['ref', 'description', 'type', 'owner', 'due_date', 'status', 'source'],
      ...items.map((d) => [
            d.ref ?? '',
            d.description,
            d.dependencyType,
            d.owner ?? '',
            d.dueDate ?? '',
            d.status,
            d.source,
          ]),
    ];
    return buildCsv(rows);
  }

  static String _decisionsCsv(List<Decision> items) {
    final rows = [
      [
        'ref',
        'description',
        'status',
        'decision_maker',
        'due_date',
        'outcome',
        'rationale',
        'source'
      ],
      ...items.map((d) => [
            d.ref ?? '',
            d.description,
            d.status,
            d.decisionMaker ?? '',
            d.dueDate ?? '',
            d.outcome ?? '',
            d.rationale ?? '',
            d.source,
          ]),
    ];
    return buildCsv(rows);
  }

  static String _actionsCsv(List<ProjectAction> items) {
    final rows = [
      [
        'ref',
        'description',
        'owner',
        'due_date',
        'status',
        'priority',
        'source'
      ],
      ...items.map((a) => [
            a.ref ?? '',
            a.description,
            a.owner ?? '',
            a.dueDate ?? '',
            a.status,
            a.priority,
            a.source,
          ]),
    ];
    return buildCsv(rows);
  }

  static String _peopleCsv(List<Person> items) {
    final rows = [
      ['name', 'role', 'organisation', 'email', 'phone', 'type'],
      ...items.map((p) => [
            p.name,
            p.role ?? '',
            p.organisation ?? '',
            p.email ?? '',
            p.phone ?? '',
            p.personType,
          ]),
    ];
    return buildCsv(rows);
  }

  // --- Helpers ---

  static String buildCsv(List<List<String>> rows) {
    return rows.map((row) => row.map(quoteCsvCell).join(',')).join('\r\n');
  }

  static String quoteCsvCell(String s) {
    if (s.contains(',') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static Future<String> _writeCsvFile(
      String csv, String name, String projectName) async {
    final slug =
        projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final filename = '${name}_${slug}_$date.csv';
    return saveTextAndOpen(filename, csv);
  }

  static void _addCsv(Archive archive, String name, String csv) {
    final bytes = csv.codeUnits;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
}
