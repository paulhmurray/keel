import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Regression for the 1.2.0 upgrade crash:
/// `duplicate column name: start_date` while running
/// `ALTER TABLE canvas_cards ADD COLUMN start_date`.
///
/// Cause: the v27 migration does `createTable(canvasCards)`, which Drift
/// builds from the CURRENT schema (already containing start_date/end_date/
/// effort_days/tags); the v28+ steps then try to add those same columns →
/// "duplicate column" → the whole upgrade aborts. The fix makes the
/// migration DDL idempotent. This test opens a DB stamped at an old
/// user_version and asserts the upgrade to the current schema completes.
void main() {
  test('upgrade from a pre-canvas schema (v26) completes without crashing',
      () async {
    final dir = await Directory.systemTemp.createTemp('keel_mig_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/old.db';

    // Hand-seed an "old" DB: a projects table (so the migration's
    // ensureColumn(projects, kind/…) has something to alter) stamped at
    // schema v26 — before the canvas tables existed. Everything the
    // migration adds after v26 (canvas create + the duplicate addColumns)
    // is exactly what used to crash.
    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        start_date TEXT,
        status TEXT NOT NULL DEFAULT 'active'
      );
    ''');
    raw.execute('PRAGMA user_version = 26;');
    raw.dispose();

    // Opening through AppDatabase triggers onUpgrade(26 → current).
    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);

    // Any query forces the migration to run. Before the fix this threw
    // "duplicate column name: start_date"; now it must succeed and the
    // canvas tables must exist.
    final cards = await db.canvasCardsDao.getCardsForProject('nope');
    expect(cards, isEmpty);
    final templates =
        await db.canvasTemplatesDao.getTemplatesForProject('nope');
    expect(templates, isEmpty);

    // And a v46 column (proves the chain ran all the way through) is usable.
    final links = await db.programmeLinksDao.getLinksForEntity('nope');
    expect(links, isEmpty);

    // v47/v48 finance tables exist and are queryable.
    final budgets = await db.financeDao.getBudgets('nope');
    expect(budgets, isEmpty);
    expect(await db.financeDao.getSnapshots('nope'), isEmpty);
    expect(await db.financeDao.getActuals('nope'), isEmpty);

    // v51 raid item links table exists and is queryable.
    expect(await db.raidDao.getLinksForProject('nope'), isEmpty);

  });

  test('upgrade from v46 creates the finance tables and is re-runnable',
      () async {
    final dir = await Directory.systemTemp.createTemp('keel_mig_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v46.db';

    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        start_date TEXT,
        status TEXT NOT NULL DEFAULT 'active'
      );
    ''');
    raw.execute("INSERT INTO projects (id, name) VALUES ('p1', 'Existing');");
    raw.execute('PRAGMA user_version = 46;');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(File(path)));

    // The finance tables from the v47 step are live and writable.
    await db.financeDao.seedDefaultCategories('p1');
    expect((await db.financeDao.getCategories('p1')).length, 5);
    expect((await db.financeDao.getAuditLog('p1')).length, 5);
    await db.close();

    // Re-open after knocking user_version back to 46 — simulates a
    // half-applied upgrade being retried. The idempotent DDL must
    // swallow "table already exists" and the data must survive.
    final raw2 = sqlite3.open(path);
    raw2.execute('PRAGMA user_version = 46;');
    raw2.dispose();
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);
    expect((await db2.financeDao.getCategories('p1')).length, 5);
  });

  test('upgrade from v48 adds is_parent and backfills actions with children',
      () async {
    final dir = await Directory.systemTemp.createTemp('keel_mig_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v48.db';

    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        start_date TEXT,
        status TEXT NOT NULL DEFAULT 'active'
      );
    ''');
    // project_actions at its v48 shape — no is_parent column yet.
    raw.execute('''
      CREATE TABLE project_actions (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL,
        ref TEXT,
        description TEXT NOT NULL,
        owner TEXT,
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        priority TEXT NOT NULL DEFAULT 'medium',
        source TEXT NOT NULL DEFAULT 'manual',
        source_note TEXT,
        outcome TEXT,
        category_id TEXT,
        recurrence_group_id TEXT,
        linked_action_id TEXT,
        plan_activity_id TEXT,
        parent_action_id TEXT,
        escalated_at INTEGER,
        source_project_id TEXT,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute("INSERT INTO projects (id, name) VALUES ('p1', 'Existing');");
    raw.execute("INSERT INTO project_actions (id, project_id, description) "
        "VALUES ('parent', 'p1', 'group head');");
    raw.execute(
        "INSERT INTO project_actions (id, project_id, description, "
        "parent_action_id) VALUES ('child', 'p1', 'child task', 'parent');");
    raw.execute("INSERT INTO project_actions (id, project_id, description) "
        "VALUES ('solo', 'p1', 'standalone');");
    raw.execute('PRAGMA user_version = 48;');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);

    final actions = await db.actionsDao.getActionsForProject('p1');
    final byId = {for (final a in actions) a.id: a};
    expect(byId['parent']!.isParent, isTrue,
        reason: 'action with children must be backfilled as parent');
    expect(byId['child']!.isParent, isFalse);
    expect(byId['solo']!.isParent, isFalse);
  });

  test('upgrade from v58 adds the dependency why/impact/counterparty/plan '
      'columns and keeps existing rows', () async {
    final dir = await Directory.systemTemp.createTemp('keel_mig_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v58.db';

    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        start_date TEXT,
        status TEXT NOT NULL DEFAULT 'active'
      );
    ''');
    // program_dependencies as it stood before v59.
    raw.execute('''
      CREATE TABLE program_dependencies (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL,
        ref TEXT,
        description TEXT NOT NULL,
        dependency_type TEXT NOT NULL DEFAULT 'inbound',
        owner TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        due_date TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        source_note TEXT,
        escalated_at INTEGER,
        source_project_id TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    raw.execute("INSERT INTO projects (id, name) VALUES ('p1', 'Existing');");
    raw.execute(
        "INSERT INTO program_dependencies (id, project_id, ref, description) "
        "VALUES ('d-old', 'p1', 'D1', 'Legacy dependency');");
    raw.execute('PRAGMA user_version = 58;');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);

    // Pre-existing row reads back with the new columns null.
    final old = (await db.raidDao.getDependencyById('d-old'))!;
    expect(old.description, 'Legacy dependency');
    expect(old.counterparty, isNull);
    expect(old.rationale, isNull);
    expect(old.impactStatement, isNull);
    expect(old.planActivityId, isNull);

    // And the new columns are writable.
    await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
      id: Value('d-new'),
      projectId: Value('p1'),
      description: Value('Signed contract'),
      counterparty: Value('Legal'),
      rationale: Value('Can\'t onboard the vendor without it'),
      impactStatement: Value('Build slips a month'),
      planActivityId: Value('act-1'),
    ));
    final dep = (await db.raidDao.getDependencyById('d-new'))!;
    expect(dep.counterparty, 'Legal');
    expect(dep.rationale, 'Can\'t onboard the vendor without it');
    expect(dep.impactStatement, 'Build slips a month');
    expect(dep.planActivityId, 'act-1');
  });

  test('upgrade from v59 adds the decision options/impact/plan/decided '
      'columns and keeps existing rows', () async {
    final dir = await Directory.systemTemp.createTemp('keel_mig_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v59.db';

    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        start_date TEXT,
        status TEXT NOT NULL DEFAULT 'active'
      );
    ''');
    // decisions as it stood before v60.
    raw.execute('''
      CREATE TABLE decisions (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL,
        ref TEXT,
        description TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        decision_maker TEXT,
        due_date TEXT,
        rationale TEXT,
        outcome TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        source_note TEXT,
        escalated_at INTEGER,
        source_project_id TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    raw.execute("INSERT INTO projects (id, name) VALUES ('p1', 'Existing');");
    raw.execute(
        "INSERT INTO decisions (id, project_id, ref, description, status) "
        "VALUES ('dc-old', 'p1', 'DC1', 'Legacy decision', 'decided');");
    raw.execute('PRAGMA user_version = 59;');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);

    final old = (await db.decisionsDao.getDecisionById('dc-old'))!;
    expect(old.description, 'Legacy decision');
    expect(old.status, 'decided');
    expect(old.optionsConsidered, isNull);
    expect(old.impactStatement, isNull);
    expect(old.planActivityId, isNull);
    expect(old.decidedAt, isNull);

    await db.decisionsDao.upsertDecision(const DecisionsCompanion(
      id: Value('dc-new'),
      projectId: Value('p1'),
      description: Value('Gateway'),
      optionsConsidered: Value('- A\n- B'),
      impactStatement: Value('Checkout blocked'),
      planActivityId: Value('act-1'),
      decidedAt: Value('2026-09-21'),
    ));
    final d = (await db.decisionsDao.getDecisionById('dc-new'))!;
    expect(d.optionsConsidered, '- A\n- B');
    expect(d.impactStatement, 'Checkout blocked');
    expect(d.planActivityId, 'act-1');
    expect(d.decidedAt, '2026-09-21');
  });

  test('upgrade from v60 adds closed_at / closure_note and keeps rows',
      () async {
    final dir = await Directory.systemTemp.createTemp('keel_mig_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v60.db';

    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        start_date TEXT,
        status TEXT NOT NULL DEFAULT 'active'
      );
    ''');
    raw.execute('''
      CREATE TABLE risks (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL,
        ref TEXT,
        description TEXT NOT NULL,
        likelihood TEXT NOT NULL DEFAULT 'medium',
        impact TEXT NOT NULL DEFAULT 'medium',
        likelihood_rationale TEXT,
        impact_rationale TEXT,
        mitigation TEXT,
        owner TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        source TEXT NOT NULL DEFAULT 'manual',
        source_note TEXT,
        escalated_at INTEGER,
        source_project_id TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    raw.execute("INSERT INTO projects (id, name) VALUES ('p1', 'Existing');");
    raw.execute(
        "INSERT INTO risks (id, project_id, ref, description, status) "
        "VALUES ('r-old', 'p1', 'R1', 'Legacy closed risk', 'closed');");
    raw.execute('PRAGMA user_version = 60;');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);

    final old = (await db.raidDao.getRiskById('r-old'))!;
    expect(old.status, 'closed');
    expect(old.closedAt, isNull);
    expect(old.closureNote, isNull);

    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r-new'),
      projectId: Value('p1'),
      description: Value('Closed with a note'),
      status: Value('accepted'),
      closedAt: Value('2026-09-22'),
      closureNote: Value('Cheaper to live with'),
    ));
    final r = (await db.raidDao.getRiskById('r-new'))!;
    expect(r.closedAt, '2026-09-22');
    expect(r.closureNote, 'Cheaper to live with');

  });

  test('upgrade from v61 adds the Planview risk columns and maps the old '
      '3-level ratings onto the 5-level scale', () async {
    final dir = await Directory.systemTemp.createTemp('keel_mig_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v61.db';

    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        start_date TEXT,
        status TEXT NOT NULL DEFAULT 'active'
      );
    ''');
    raw.execute('''
      CREATE TABLE risks (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL,
        ref TEXT,
        description TEXT NOT NULL,
        likelihood TEXT NOT NULL DEFAULT 'medium',
        impact TEXT NOT NULL DEFAULT 'medium',
        likelihood_rationale TEXT,
        impact_rationale TEXT,
        mitigation TEXT,
        owner TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        closed_at TEXT,
        closure_note TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        source_note TEXT,
        escalated_at INTEGER,
        source_project_id TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    raw.execute("INSERT INTO projects (id, name) VALUES ('p1', 'Existing');");
    raw.execute(
        "INSERT INTO risks (id, project_id, ref, description, likelihood, impact) VALUES "
        "('r-hh', 'p1', 'R1', 'high high', 'high', 'high'), "
        "('r-lm', 'p1', 'R2', 'low medium', 'low', 'medium'), "
        "('r-new', 'p1', 'R3', 'already new', 'possible', 'severe');");
    raw.execute('PRAGMA user_version = 61;');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);

    final hh = (await db.raidDao.getRiskById('r-hh'))!;
    expect(hh.likelihood, 'likely');
    expect(hh.impact, 'major');
    final lm = (await db.raidDao.getRiskById('r-lm'))!;
    expect(lm.likelihood, 'unlikely');
    expect(lm.impact, 'moderate');
    // Already on the new scale: untouched.
    final nw = (await db.raidDao.getRiskById('r-new'))!;
    expect(nw.likelihood, 'possible');
    expect(nw.impact, 'severe');
    // New columns default sensibly and are writable.
    expect(hh.strategy, 'treat');
    expect(hh.steerco, isFalse);
    expect(hh.title, isNull);
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r-pv'),
      projectId: Value('p1'),
      description: Value('pv'),
      title: Value('Planview shaped'),
      steerco: Value(true),
      strategy: Value('transfer'),
      likelihoodTarget: Value('unlikely'),
      impactTarget: Value('moderate'),
      assignee: Value('Paul Murray'),
      enterpriseRiskLink: Value('Strategic Delivery'),
      dueDate: Value('2026-09-30'),
      lastReviewedAt: Value('2026-09-09'),
      nextReviewAt: Value('2026-09-23'),
      statusNote: Value('Open.'),
    ));
    final pv = (await db.raidDao.getRiskById('r-pv'))!;
    expect(pv.title, 'Planview shaped');
    expect(pv.steerco, isTrue);
    expect(pv.strategy, 'transfer');
    expect(pv.nextReviewAt, '2026-09-23');
  });

  test('upgrade from v63 adds share_level (full for same-machine links) and '
      'the plan-detail cascade markers', () async {
    final dir = await Directory.systemTemp.createTemp('keel_mig_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v63.db';

    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE projects (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        start_date TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        kind TEXT NOT NULL DEFAULT 'project',
        parent_programme_id TEXT
      );
    ''');
    raw.execute('''
      CREATE TABLE programme_links (
        id TEXT NOT NULL PRIMARY KEY,
        owner_entity_id TEXT NOT NULL,
        owner_kind TEXT NOT NULL,
        partner_kind TEXT NOT NULL,
        partner_name TEXT,
        partner_local_id TEXT,
        code TEXT NOT NULL,
        link_secret TEXT,
        status TEXT NOT NULL DEFAULT 'pending_remote',
        generated_here INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    raw.execute('''
      CREATE TABLE timeline_work_packages (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL,
        name TEXT NOT NULL,
        colour_theme TEXT NOT NULL DEFAULT 'wp1',
        sort_order INTEGER NOT NULL DEFAULT 0,
        rag_status TEXT NOT NULL DEFAULT 'not_started',
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    raw.execute('''
      CREATE TABLE timeline_activities (
        id TEXT NOT NULL PRIMARY KEY,
        work_package_id TEXT NOT NULL,
        project_id TEXT NOT NULL,
        name TEXT NOT NULL,
        activity_type TEXT NOT NULL DEFAULT 'activity',
        status TEXT NOT NULL DEFAULT 'not_started',
        is_critical INTEGER NOT NULL DEFAULT 0,
        is_baseline INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    raw.execute('''
      CREATE TABLE timeline_dependencies (
        id TEXT NOT NULL PRIMARY KEY,
        project_id TEXT NOT NULL,
        from_activity_id TEXT NOT NULL,
        to_activity_id TEXT NOT NULL,
        dependency_type TEXT NOT NULL DEFAULT 'finish_to_start',
        notes TEXT,
        external_label TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    raw.execute("INSERT INTO projects (id, name, kind) VALUES "
        "('prog', 'Prog', 'programme'), ('proj', 'Proj', 'project');");
    raw.execute("INSERT INTO programme_links "
        "(id, owner_entity_id, owner_kind, partner_kind, partner_local_id, code, status) VALUES "
        "('l-local', 'proj', 'project', 'programme', 'prog', 'KL-AAAA-AAAA-AAAA', 'active'), "
        "('l-remote', 'proj', 'project', 'programme', NULL, 'KL-BBBB-BBBB-BBBB', 'active');");
    raw.execute("INSERT INTO timeline_work_packages (id, project_id, name) VALUES ('wp', 'proj', 'WP');");
    raw.execute("INSERT INTO timeline_activities (id, work_package_id, project_id, name) "
        "VALUES ('a1', 'wp', 'proj', 'Existing activity');");
    raw.execute('PRAGMA user_version = 63;');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);

    final links = await db.programmeLinksDao.getLinksForEntity('proj');
    final byId = {for (final l in links) l.id: l};
    expect(byId['l-local']!.shareLevel, 'full');
    expect(byId['l-remote']!.shareLevel, 'escalated');

    final a1 = (await db.programmeGanttDao.getActivityById('a1'))!;
    expect(a1.sourceProjectId, isNull);
    await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion.insert(
      id: 'cascade:activity:proj:a1',
      workPackageId: 'cascade:proj:wp',
      projectId: 'prog',
      name: 'copy',
      sourceProjectId: const Value('proj'),
    ));
    final copy = (await db.programmeGanttDao
        .getActivityById('cascade:activity:proj:a1'))!;
    expect(copy.sourceProjectId, 'proj');
    await db.programmeGanttDao.upsertDependency(TimelineDependenciesCompanion.insert(
      id: 'dep',
      projectId: 'prog',
      fromActivityId: 'x',
      toActivityId: 'cascade:activity:proj:a1',
      sourceProjectId: const Value('proj'),
    ));
    expect((await db.programmeGanttDao.getDependencies('prog')).single.sourceProjectId,
        'proj');
  });
}
