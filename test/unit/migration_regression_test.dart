import 'dart:io';

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
}
