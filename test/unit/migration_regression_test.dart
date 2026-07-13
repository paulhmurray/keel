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
  });
}
