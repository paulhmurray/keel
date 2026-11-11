import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/llm/llm_client.dart';
import 'package:keel/core/raid/raid_conversion_service.dart';
import 'package:keel/features/raid/raid_duplicates_view.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:keel/providers/sync_provider.dart';
import 'package:provider/provider.dart';

class _FakeClient implements LLMClient {
  final String answer;
  int calls = 0;
  String? lastUser;
  _FakeClient(this.answer);
  @override
  Future<String> complete({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1000,
  }) async {
    calls++;
    lastUser = userMessage;
    return answer;
  }

  @override
  Stream<String> stream({required String systemPrompt, required String userMessage}) =>
      Stream.value(answer);
}

Future<AppDatabase> _seed() async {
  final db = AppDatabase.memory();
  await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'p', name: 'P'));
  await db.raidDao.upsertAssumption(const AssumptionsCompanion(
    id: Value('a1'), projectId: Value('p'), ref: Value('A1'),
    description: Value('We assume Salesforce sign the order form by 3 Oct.'),
  ));
  await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
    id: Value('d1'), projectId: Value('p'), ref: Value('D1'),
    dependencyType: Value('inbound'), counterparty: Value('Salesforce'),
    description: Value('Salesforce must deliver the signed order form by 3 Oct.'),
  ));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r1'), projectId: Value('p'), ref: Value('R1'),
    description: Value('If the vendor slips, SIT starts late.'),
  ));
  return db;
}

/// Pushes the view the way the RAID header does, on top of a home page.
Future<void> _open(
  WidgetTester tester,
  AppDatabase db,
  LLMClient client, {
  Size window = const Size(1300, 900),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = window;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
      ChangeNotifierProvider<SyncProvider>(create: (_) => SyncProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      RaidDuplicatesView(db: db, projectId: 'p', client: client),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

const _answer =
    '{"groups":[{"items":["A1","D1"],"register":"dependency","reason":"Both are the same Salesforce order-form promise.","merged":"Salesforce must deliver the signed order form by 3 Oct so that build can start; if late, [impact to confirm]."}]}';

void main() {
  testWidgets('the check runs on entry and lays the match out in full', (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    final client = _FakeClient(_answer);
    await _open(tester, db, client);

    expect(client.calls, 1, reason: 'the screen checks as soon as it opens');
    expect(client.lastUser, contains('[1] Risk R1'));
    expect(find.text('FIND DUPLICATES'), findsOneWidget);
    expect(find.text('MATCH 1 OF 1'), findsOneWidget);
    // The reason shows in the rail and in the detail pane.
    expect(find.text('Both are the same Salesforce order-form promise.'), findsNWidgets(2));
    // Both statements are shown whole, not clipped.
    expect(find.text('We assume Salesforce sign the order form by 3 Oct.'), findsOneWidget);
    expect(find.text('Salesforce must deliver the signed order form by 3 Oct.'), findsOneWidget);
    expect(find.text('Keep the survivor as'), findsOneWidget);
    // Default survivor is the member already in the suggested register.
    expect(find.text('Merge into Dependency D1'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Edit'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('not duplicates writes nothing and can be reconsidered', (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    await _open(tester, db, _FakeClient(_answer));

    await tester.tap(find.text('Not duplicates'));
    await tester.pumpAndSettle();
    expect(find.text('KEPT'), findsOneWidget);
    expect(find.text('Kept separate — nothing was changed.'), findsOneWidget);
    expect(find.text('Merge into Dependency D1'), findsNothing);
    expect((await db.raidDao.getAssumptionById('a1'))!.status, 'open');
    expect((await db.raidDao.getDependencyById('d1'))!.status, 'open');

    await tester.tap(find.text('Reconsider'));
    await tester.pumpAndSettle();
    expect(find.text('TO DECIDE'), findsOneWidget);
    expect(find.text('Merge into Dependency D1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('merging closes the duplicate, rewords the survivor and stays on screen',
      (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    await _open(tester, db, _FakeClient(_answer));

    await tester.tap(find.text('Merge into Dependency D1'));
    await tester.pumpAndSettle();

    expect(find.text('MERGED'), findsOneWidget);
    expect(find.text('Merged into Dependency D1. Closed: Assumption A1.'), findsOneWidget);
    // The rail still names the pair after the group shrinks to its survivor.
    expect(find.text('Assumption A1  +  Dependency D1'), findsOneWidget);
    expect(find.text('FIND DUPLICATES'), findsOneWidget, reason: 'the screen stays up');
    final d1 = (await db.raidDao.getDependencyById('d1'))!;
    expect(d1.description, startsWith('Salesforce must deliver the signed order form by 3 Oct so that'));
    expect(d1.sourceNote, contains('Merged in Assumption A1'));
    final a1 = (await db.raidDao.getAssumptionById('a1'))!;
    expect(a1.status, 'closed');
    expect(a1.sourceNote, contains('Merged into Dependency D1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a member converted from its form is merged under its new register',
      (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    await _open(tester, db, _FakeClient(_answer));

    // Edit opens the assumption's own form.
    await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);

    // Convert A1 to a risk behind the form's back (what the form's own
    // Convert menu does), then close the form: the screen re-reads.
    final newRef = await RaidConversionService(db)
        .convert(id: 'a1', from: RaidKind.assumption, to: RaidKind.risk);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The rail names the member by its new register; the card shows the
    // new ref and the old one is gone.
    expect(find.text('Risk $newRef  +  Dependency D1'), findsOneWidget);
    expect(find.text(newRef), findsOneWidget);
    expect(find.text('A1'), findsNothing);
    expect(find.text('Merge into Dependency D1'), findsOneWidget);

    await tester.tap(find.text('Merge into Dependency D1'));
    await tester.pumpAndSettle();

    // The merge found the member by its current kind and closed it.
    final moved = (await db.raidDao.getRiskById('a1'))!;
    expect(moved.status, 'closed');
    expect(moved.sourceNote, contains('Merged into Dependency D1'));
    expect((await db.raidDao.getDependencyById('d1'))!.sourceNote,
        contains('Merged in Risk $newRef'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a member closed from its form resolves the match', (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    await _open(tester, db, _FakeClient(_answer));

    await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
    await tester.pumpAndSettle();
    await db.raidDao.upsertAssumption(const AssumptionsCompanion(
      id: Value('a1'), projectId: Value('p'),
      description: Value('We assume Salesforce sign the order form by 3 Oct.'),
      status: Value('closed'),
    ));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('RESOLVED'), findsOneWidget);
    expect(find.text('Merge into Dependency D1'), findsNothing);
    expect(find.textContaining('Only one of these is still open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide match with long statements renders in a small window',
      (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'p', name: 'P'));
    final long = List.filled(30, 'the vendor build slips past the agreed date').join(' ');
    for (var i = 1; i <= 5; i++) {
      await db.raidDao.upsertRisk(RisksCompanion(
        id: Value('r$i'), projectId: const Value('p'), ref: Value('R$i'),
        title: Value('Vendor slip number $i'), owner: const Value('Paul'),
        mitigation: Value('Treatment: $long'),
        description: Value('If $long, SIT starts late.'),
      ));
    }
    const five =
        '{"groups":[{"items":[1,2,3,4,5],"register":"risk","reason":"Five ways of saying the vendor may slip.","merged":"If the vendor build slips, SIT starts late."}]}';
    await _open(tester, db, _FakeClient(five), window: const Size(1000, 700));

    expect(find.text('MATCH 1 OF 1'), findsOneWidget);
    expect(find.text('Vendor slip number 1'), findsOneWidget);
    expect(find.text('Merge into Risk R1'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow in a small window');
  });

  testWidgets('an answer with no JSON fails safely', (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    await _open(tester, db, _FakeClient('I could not find any.'));
    expect(find.text('The check could not be completed.'), findsOneWidget);
    expect(find.textContaining('No JSON object'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
