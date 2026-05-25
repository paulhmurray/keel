import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/import/json_importer.dart';

Future<void> _project(AppDatabase db, String id) async {
  await db.projectDao.upsertProject(ProjectsCompanion.insert(
    id: id,
    name: 'Test',
  ));
}

Future<void> _series(
  AppDatabase db, {
  required String projectId,
  required String id,
  required String name,
  String? cadenceHint,
}) async {
  await db.journalSeriesDao.upsert(JournalSeriesDefsCompanion.insert(
    id: id,
    projectId: projectId,
    name: name,
    cadenceHint: Value(cadenceHint),
  ));
}

Future<void> _entry(
  AppDatabase db, {
  required String projectId,
  required String id,
  required String body,
  required String entryDate,
  bool isFavourite = false,
  String? seriesId,
}) async {
  await db.journalDao.upsertEntry(JournalEntriesCompanion.insert(
    id: id,
    projectId: projectId,
    body: body,
    entryDate: entryDate,
    isFavourite: Value(isFavourite),
    seriesId: Value(seriesId),
  ));
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() async => db.close());

  group('journal star + series — DB layer', () {
    test('toggleFavourite flips and persists the flag', () async {
      const pid = 'p1';
      await _project(db, pid);
      await _entry(db,
          projectId: pid, id: 'e1', body: 'note', entryDate: '2026-05-14');

      await db.journalDao.toggleFavourite('e1', true);
      var entry = await db.journalDao.getEntryById('e1');
      expect(entry!.isFavourite, isTrue);

      await db.journalDao.toggleFavourite('e1', false);
      entry = await db.journalDao.getEntryById('e1');
      expect(entry!.isFavourite, isFalse);
    });

    test('watchFavouritesForProject returns only starred entries', () async {
      const pid = 'p2';
      await _project(db, pid);
      await _entry(db,
          projectId: pid,
          id: 'a',
          body: 'note',
          entryDate: '2026-05-14',
          isFavourite: true);
      await _entry(db,
          projectId: pid,
          id: 'b',
          body: 'note',
          entryDate: '2026-05-13',
          isFavourite: false);
      await _entry(db,
          projectId: pid,
          id: 'c',
          body: 'note',
          entryDate: '2026-05-12',
          isFavourite: true);

      final favs =
          await db.journalDao.watchFavouritesForProject(pid).first;
      expect(favs.map((e) => e.id).toSet(), {'a', 'c'});
    });

    test('getEntriesForSeries returns entries newest-date first', () async {
      const pid = 'p3';
      await _project(db, pid);
      await _series(db, projectId: pid, id: 's1', name: 'Daily Standup');
      await _entry(db,
          projectId: pid,
          id: 'old',
          body: 'note',
          entryDate: '2026-05-01',
          seriesId: 's1');
      await _entry(db,
          projectId: pid,
          id: 'new',
          body: 'note',
          entryDate: '2026-05-14',
          seriesId: 's1');
      await _entry(db,
          projectId: pid,
          id: 'unrelated',
          body: 'note',
          entryDate: '2026-05-10');

      final inSeries = await db.journalDao.getEntriesForSeries('s1');
      expect(inSeries.map((e) => e.id).toList(), ['new', 'old']);
    });

    test('deleteSeries clears seriesId from entries but keeps them',
        () async {
      const pid = 'p4';
      await _project(db, pid);
      await _series(db, projectId: pid, id: 's1', name: 'Weekly PMO');
      await _entry(db,
          projectId: pid,
          id: 'e1',
          body: 'note',
          entryDate: '2026-05-14',
          seriesId: 's1');

      await db.journalSeriesDao.deleteSeries('s1');
      // Series gone.
      expect(await db.journalSeriesDao.getById('s1'), isNull);
      // Entry kept, but seriesId nulled.
      final entry = await db.journalDao.getEntryById('e1');
      expect(entry, isNotNull);
      expect(entry!.seriesId, isNull);
    });
  });

  group('journal export/import round-trip', () {
    test('pre-25 export (no series, no isFavourite) imports gracefully',
        () async {
      final data = {
        'keel_version': '1.0',
        'exported_at': DateTime(2025, 1, 1).toIso8601String(),
        'project': {
          'id': 'legacy',
          'name': 'Legacy',
          'description': null,
          'start_date': null,
          'status': 'active',
          'created_at': DateTime(2025, 1, 1).toIso8601String(),
          'updated_at': DateTime(2025, 1, 1).toIso8601String(),
        },
        'journal': {
          'entries': [
            {
              'id': 'old-entry',
              'title': null,
              'body': 'old note',
              'entry_date': '2025-06-01',
              'meeting_context': null,
              'parsed': true,
              'confirmed_at': null,
              'created_at': '2025-06-01T00:00:00.000',
              'updated_at': '2025-06-01T00:00:00.000',
              // No is_favourite, no series_id, no series array.
            },
          ],
          'links': [],
        },
      };
      final result =
          await JsonImporter.importFromString(jsonEncode(data), db);
      expect(result.journalEntries, 1);
      final entry = await db.journalDao.getEntryById('old-entry');
      expect(entry!.isFavourite, isFalse);
      expect(entry.seriesId, isNull);
    });

    test('schema-25 export round-trips series + favourites', () async {
      final data = {
        'keel_version': '1.0',
        'schema_version': 25,
        'exported_at': DateTime(2026, 5, 14).toIso8601String(),
        'project': {
          'id': 'new',
          'name': 'New',
          'description': null,
          'start_date': null,
          'status': 'active',
          'created_at': DateTime(2026, 1, 1).toIso8601String(),
          'updated_at': DateTime(2026, 5, 14).toIso8601String(),
        },
        'journal': {
          'series': [
            {
              'id': 's-daily',
              'name': 'Daily Standup',
              'description': 'PMO daily',
              'cadence_hint': 'daily',
              'color': '#3B82F6',
              'sort_order': 0,
              'created_at': '2026-01-01T00:00:00.000',
              'updated_at': '2026-05-14T00:00:00.000',
            },
          ],
          'entries': [
            {
              'id': 'fav-entry',
              'title': 'Standup notes',
              'body': 'note',
              'entry_date': '2026-05-14',
              'meeting_context': null,
              'parsed': true,
              'confirmed_at': null,
              'is_favourite': true,
              'series_id': 's-daily',
              'created_at': '2026-05-14T00:00:00.000',
              'updated_at': '2026-05-14T00:00:00.000',
            },
          ],
          'links': [],
        },
      };
      await JsonImporter.importFromString(jsonEncode(data), db);
      final series = await db.journalSeriesDao.getById('s-daily');
      expect(series, isNotNull);
      expect(series!.name, 'Daily Standup');
      expect(series.cadenceHint, 'daily');
      final entry = await db.journalDao.getEntryById('fav-entry');
      expect(entry!.isFavourite, isTrue);
      expect(entry.seriesId, 's-daily');
    });
  });
}
