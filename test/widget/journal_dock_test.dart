import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/journal/journal_overlay.dart';
import 'package:keel/providers/settings_provider.dart';

const _projectId = 'p-test';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.into(db.projects).insert(ProjectsCompanion.insert(
          id: _projectId,
          name: 'Test Project',
        ));
  });

  tearDown(() => db.close());

  Future<void> pumpDock(WidgetTester tester,
      {required VoidCallback onClose, JournalEntry? entry, Key? key}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            const Expanded(child: SizedBox()),
            SizedBox(
              width: 420,
              child: JournalOverlay(
                key: key,
                projectId: _projectId,
                db: db,
                settings: const AppSettings(),
                existingEntry: entry,
                docked: true,
                onCloseDock: onClose,
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('docked journal renders inline and X closes via callback',
      (tester) async {
    var closed = false;
    await pumpDock(tester, onClose: () => closed = true);

    expect(find.textContaining('JOURNAL —'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets(
      'docked save/parse cycle returns to the running note instead of '
      'closing', (tester) async {
    var closed = false;
    await pumpDock(tester, onClose: () => closed = true);

    // Type a note and save with Ctrl+Enter (no LLM key → heuristic parse).
    await tester.enterText(
        find.byType(TextField).last, 'Discussed rollout with the team.');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Whatever the parser found (or none), complete the cycle.
    if (find.text('Cmd+Enter: Confirm All').evaluate().isNotEmpty) {
      await tester
          .tap(find.text('Esc — dismiss (unconfirmed items left pending)'));
      await tester.pumpAndSettle();
    }

    // Back on the editor, dock still open, entry persisted.
    expect(closed, isFalse);
    expect(find.textContaining('JOURNAL —'), findsOneWidget);
    expect(
        find.text('Discussed rollout with the team.'), findsOneWidget);
    final entries = await db.journalDao.getEntriesForProject(_projectId);
    expect(entries, hasLength(1));
    expect(entries.single.body, 'Discussed rollout with the team.');
  });

  testWidgets(
      'docked pane swaps to a different entry in place when the shell '
      'repoints it', (tester) async {
    JournalEntry makeEntry(String id, String body) => JournalEntry(
          id: id,
          projectId: _projectId,
          body: body,
          entryDate: '2026-08-11',
          parsed: true,
          isFavourite: false,
          createdAt: DateTime(2026, 8, 11),
          updatedAt: DateTime(2026, 8, 11),
        );

    // Same GlobalKey across pumps — mirrors the shell keeping one pane
    // and changing existingEntry.
    final key = GlobalKey<JournalOverlayState>();
    await pumpDock(tester,
        onClose: () {}, entry: makeEntry('e1', 'first note'), key: key);
    expect(find.text('first note'), findsOneWidget);

    await pumpDock(tester,
        onClose: () {}, entry: makeEntry('e2', 'second note'), key: key);
    expect(find.text('second note'), findsOneWidget);
    expect(find.text('first note'), findsNothing);

    // Unsaved-changes probe used by the shell's discard guard.
    expect(key.currentState!.hasUnsavedChanges, isFalse);
    await tester.enterText(find.byType(TextField).last, 'edited body');
    expect(key.currentState!.hasUnsavedChanges, isTrue);
  });

  group('save without parsing', () {
    Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+S records the entry unparsed; Parse later picks it up',
        (tester) async {
      await pumpDock(tester, onClose: () {});
      await tester.enterText(find.byType(TextField).last,
          'Action: Sam to send the vendor contract by Friday.');
      await ctrl(tester, LogicalKeyboardKey.keyS);

      // Saved, not parsed, no review shown.
      var entry =
          (await db.journalDao.getEntriesForProject(_projectId)).single;
      expect(entry.parsed, isFalse);
      expect(entry.lastParsedBody, isNull);
      expect(find.text('Cmd+Enter: Confirm All'), findsNothing);
      expect(find.text('Parse'), findsOneWidget);
      expect(find.text('Re-parse'), findsNothing);

      // Parse it now from the header.
      await tester.tap(find.text('Parse'));
      await tester.pumpAndSettle();
      if (find.text('Cmd+Enter: Confirm All').evaluate().isNotEmpty) {
        await ctrl(tester, LogicalKeyboardKey.enter);
      }
      entry = (await db.journalDao.getEntriesForProject(_projectId)).single;
      expect(entry.parsed, isTrue);
      expect(find.text('Re-parse'), findsOneWidget);
    });

    testWidgets(
        'new text saved without parsing on a parsed entry marks it '
        'unparsed but keeps the old baseline for an incremental parse',
        (tester) async {
      await db.journalDao.upsertEntry(JournalEntriesCompanion.insert(
        id: 'e1',
        projectId: _projectId,
        body: 'first note',
        entryDate: '2026-11-19',
        parsed: const Value(true),
        lastParsedBody: const Value('first note'),
        confirmedAt: Value(DateTime(2026, 11, 19)),
      ));
      final saved = await db.journalDao.getEntryById('e1');
      await pumpDock(tester, onClose: () {}, entry: saved);

      await tester.enterText(
          find.byType(TextField).last, 'first note\nsecond thought');
      await ctrl(tester, LogicalKeyboardKey.keyS);

      final entry = (await db.journalDao.getEntryById('e1'))!;
      expect(entry.body, 'first note\nsecond thought');
      expect(entry.parsed, isFalse);
      expect(entry.lastParsedBody, 'first note');
      expect(find.text('Parse'), findsOneWidget);
    });
  });
}
