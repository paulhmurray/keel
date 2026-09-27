import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/raid_conversion_service.dart' show RaidKind;
import 'package:keel/core/raid/raid_tidy.dart';

void main() {
  final t0 = DateTime(2026, 9, 1);
  Risk risk(String id, String d, {String status = 'open', String? src, String? owner = 'Paul'}) =>
      Risk(id: id, projectId: 'p', description: d, likelihood: 'possible',
          impact: 'moderate', status: status, source: 'manual', steerco: false,
          strategy: 'treat', owner: owner, sourceProjectId: src,
          createdAt: t0, updatedAt: t0);
  Issue issue(String id, String d, {String? due}) => Issue(
      id: id, projectId: 'p', description: d, priority: 'high', status: 'open',
      source: 'manual', escalationRequired: false, dueDate: due, owner: 'Paul',
      createdAt: t0, updatedAt: t0);

  const good = 'If Salesforce do not confirm the order form by 3 October, then '
      'the build may start without entitlements, resulting in a four-week '
      'delay to SIT.';

  test('needsWork keeps only structurally weak, open, native items', () {
    final out = collectTidyCandidates(
      risks: [
        risk('weak', 'Vendor build phase is running late and stretched.'),
        risk('good', good),
        risk('closed', 'Short and closed anyway here ok', status: 'closed'),
        risk('copy', 'Cascaded copy is not ours to tidy at all', src: 'other'),
      ],
      assumptions: const [],
      issues: [issue('i-weak', 'The vendor may miss the date which could delay us', due: null)],
      dependencies: const [],
      scope: TidyScope.needsWork,
    );
    expect(out.map((c) => c.id), ['weak', 'i-weak']);
    expect(out.first.kind, RaidKind.risk);
    expect(out.first.needsWork, isTrue);
    expect(out.first.context.map((e) => e.$1), containsAll(['Likelihood', 'Consequence', 'Owner']));
  });

  test('allOpen includes well-formed items but still never closed or copies', () {
    final out = collectTidyCandidates(
      risks: [risk('good', good), risk('closed', good, status: 'closed'), risk('copy', good, src: 'x')],
      assumptions: const [],
      issues: const [],
      dependencies: const [],
      scope: TidyScope.allOpen,
    );
    expect(out.map((c) => c.id), ['good']);
    expect(out.single.needsWork, isFalse);
  });

  test('each candidate builds the description prompt for its kind', () {
    final out = collectTidyCandidates(
      risks: [risk('r', 'Vendor build phase is running late and stretched.')],
      assumptions: const [],
      issues: [issue('i', 'The vendor may miss the date which could delay us')],
      dependencies: const [],
      scope: TidyScope.allOpen,
    );
    final rp = out.firstWhere((c) => c.kind == RaidKind.risk).prompt(null);
    expect(rp.user, contains('If [cause], then [event] may occur'));
    final ip = out.firstWhere((c) => c.kind == RaidKind.issue).prompt('CTX');
    expect(ip.user, contains('[What has happened] because [cause]'));
    expect(ip.system, startsWith('CTX'));
  });

  test('history note keeps the old wording and appends to an existing note', () {
    expect(
        tidyHistoryNote(
            existingSourceNote: null,
            previousDescription: ' Vendor late ',
            when: DateTime(2026, 9, 27)),
        'Reworded 2026-09-27. Was: "Vendor late"');
    expect(
        tidyHistoryNote(
            existingSourceNote: 'From SteerCo minutes',
            previousDescription: 'x',
            when: DateTime(2026, 9, 27)),
        'From SteerCo minutes\nReworded 2026-09-27. Was: "x"');
  });

  test('accepting a rewrite (partial upsert) keeps every other field', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'p', name: 'P'));
    await db.raidDao.upsertRisk(RisksCompanion(
      id: const Value('r1'),
      projectId: const Value('p'),
      ref: const Value('R7'),
      description: const Value('Vendor late'),
      likelihood: const Value('likely'),
      impact: const Value('major'),
      mitigation: const Value('Weekly checkpoints'),
      owner: const Value('Sam'),
      sourceNote: const Value('From SteerCo'),
      escalatedAt: Value(DateTime(2026, 9, 1)),
    ));
    final before = (await db.raidDao.getRiskById('r1'))!;
    // Exactly what the tidy dialog's Accept writes.
    await db.raidDao.upsertRisk(RisksCompanion(
      id: const Value('r1'),
      projectId: const Value('p'),
      description: const Value(good),
      sourceNote: Value(tidyHistoryNote(
          existingSourceNote: before.sourceNote,
          previousDescription: before.description,
          when: DateTime(2026, 9, 27))),
      updatedAt: Value(DateTime(2026, 9, 27)),
    ));
    final after = (await db.raidDao.getRiskById('r1'))!;
    expect(after.description, good);
    expect(after.sourceNote, 'From SteerCo\nReworded 2026-09-27. Was: "Vendor late"');
    expect(after.ref, 'R7');
    expect(after.likelihood, 'likely');
    expect(after.impact, 'major');
    expect(after.mitigation, 'Weekly checkpoints');
    expect(after.owner, 'Sam');
    expect(after.escalatedAt, DateTime(2026, 9, 1));
  });
}
