import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';

/// Format a date offset in days relative to today as the ISO
/// YYYY-MM-DD string the DAOs compare against. Centralises the
/// fiddly month/day padding so each test reads as a date offset.
String _isoOffset(int days) {
  final d = DateTime.now().add(Duration(days: days));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(
        ProjectsCompanion.insert(id: 'prog', name: 'Programme'));
    await db.projectDao.insertProject(
        ProjectsCompanion.insert(id: 'proj-a', name: 'Project A'));
  });

  tearDown(() async => db.close());

  group('Actions — getOverdueCascadedActionsForProgramme', () {
    test(
        'returns cascaded actions on the programme whose due date is '
        'in the past and status is not closed', () async {
      // Cascaded + overdue + open → should appear.
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-overdue',
        projectId: 'prog',
        description: 'Slipped',
        dueDate: Value(_isoOffset(-3)),
        status: const Value('open'),
        sourceProjectId: const Value('proj-a'),
      ));
      // Cascaded + future due → should NOT appear.
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-future',
        projectId: 'prog',
        description: 'Not yet',
        dueDate: Value(_isoOffset(5)),
        sourceProjectId: const Value('proj-a'),
      ));
      // Cascaded + overdue + closed → should NOT appear.
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-done',
        projectId: 'prog',
        description: 'Finished',
        dueDate: Value(_isoOffset(-2)),
        status: const Value('closed'),
        sourceProjectId: const Value('proj-a'),
      ));
      // Native (not cascaded) overdue → should NOT appear; this view is
      // for items cascaded from linked projects only.
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-native',
        projectId: 'prog',
        description: 'My own',
        dueDate: Value(_isoOffset(-1)),
      ));
      // Cascaded + overdue but on a DIFFERENT programme → should NOT.
      await db.projectDao.insertProject(ProjectsCompanion.insert(
        id: 'prog-other', name: 'Other Prog', kind: const Value('programme')));
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-other-prog',
        projectId: 'prog-other',
        description: 'Different prog',
        dueDate: Value(_isoOffset(-1)),
        sourceProjectId: const Value('proj-a'),
      ));

      final out = await db.actionsDao
          .getOverdueCascadedActionsForProgramme('prog');
      expect(out.map((a) => a.id), ['a-overdue']);
    });

    test('returns rows sorted by due date ASC (most overdue first)',
        () async {
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-2',
        projectId: 'prog',
        description: '2 days ago',
        dueDate: Value(_isoOffset(-2)),
        sourceProjectId: const Value('proj-a'),
      ));
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-5',
        projectId: 'prog',
        description: '5 days ago',
        dueDate: Value(_isoOffset(-5)),
        sourceProjectId: const Value('proj-a'),
      ));
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-1',
        projectId: 'prog',
        description: '1 day ago',
        dueDate: Value(_isoOffset(-1)),
        sourceProjectId: const Value('proj-a'),
      ));
      final out = await db.actionsDao
          .getOverdueCascadedActionsForProgramme('prog');
      expect(out.map((a) => a.id), ['a-5', 'a-2', 'a-1']);
    });

    test('rows due today are NOT overdue (strict less-than)', () async {
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-today',
        projectId: 'prog',
        description: 'Today',
        dueDate: Value(_isoOffset(0)),
        sourceProjectId: const Value('proj-a'),
      ));
      final out = await db.actionsDao
          .getOverdueCascadedActionsForProgramme('prog');
      expect(out, isEmpty);
    });
  });

  group('Decisions — getOverdueCascadedDecisionsForProgramme', () {
    test(
        'returns only pending decisions with a past due date — '
        'approved/rejected/deferred are excluded', () async {
      // Pending + overdue → in.
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-overdue',
        projectId: 'prog',
        description: 'Needs deciding',
        dueDate: Value(_isoOffset(-4)),
        status: const Value('pending'),
        sourceProjectId: const Value('proj-a'),
      ));
      // Approved + overdue → out (a decision has been made).
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-approved',
        projectId: 'prog',
        description: 'Already approved',
        dueDate: Value(_isoOffset(-2)),
        status: const Value('approved'),
        sourceProjectId: const Value('proj-a'),
      ));
      // Deferred + overdue → out (an explicit deferral is a decision).
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-deferred',
        projectId: 'prog',
        description: 'Deferred',
        dueDate: Value(_isoOffset(-3)),
        status: const Value('deferred'),
        sourceProjectId: const Value('proj-a'),
      ));
      // Pending + cascaded but FUTURE due → out.
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-future',
        projectId: 'prog',
        description: 'Plenty of time',
        dueDate: Value(_isoOffset(7)),
        status: const Value('pending'),
        sourceProjectId: const Value('proj-a'),
      ));
      // Native pending + overdue → out (cascaded-only view).
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-native',
        projectId: 'prog',
        description: 'Programme own',
        dueDate: Value(_isoOffset(-1)),
        status: const Value('pending'),
      ));

      final out = await db.decisionsDao
          .getOverdueCascadedDecisionsForProgramme('prog');
      expect(out.map((d) => d.id), ['d-overdue']);
    });

    test(
        'rows with null due dates are excluded (we don\'t flag '
        'undated decisions as overdue)', () async {
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-no-date',
        projectId: 'prog',
        description: 'Floating',
        status: const Value('pending'),
        sourceProjectId: const Value('proj-a'),
      ));
      expect(
        await db.decisionsDao
            .getOverdueCascadedDecisionsForProgramme('prog'),
        isEmpty,
      );
    });
  });
}
