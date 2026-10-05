import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/llm/llm_client.dart';
import 'package:keel/features/timeline/gantt/replan_dialog.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// The re-plan dialog: scope summary, baseline-first checkbox, one card
/// per move, Accept writes the row with its history note.
///
/// The seeded plan is anchored in the past so "today" is always after
/// the slipped activity regardless of when the test runs.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(
      ProjectsCompanion.insert(id: 'p1', name: 'P'),
    );
    await db.programmeGanttDao.upsertHeader(
      const ProgrammeHeadersCompanion(
        id: Value('h'),
        projectId: Value('p1'),
        month0Date: Value('2020-01-01'),
      ),
    );
    await db.programmeGanttDao.upsertWorkPackage(
      const TimelineWorkPackagesCompanion(
        id: Value('wp'),
        projectId: Value('p1'),
        name: Value('WP'),
        sortOrder: Value(0),
      ),
    );
    // Slipped: Feb–Apr 2020, not started.
    await db.programmeGanttDao.upsertActivity(
      const TimelineActivitiesCompanion(
        id: Value('a'),
        workPackageId: Value('wp'),
        projectId: Value('p1'),
        name: Value('Build adapter'),
        startMonth: Value(1),
        endMonth: Value(3),
        sortOrder: Value(0),
      ),
    );
    // Far future, gated by a: must not appear.
    await db.programmeGanttDao.upsertActivity(
      const TimelineActivitiesCompanion(
        id: Value('b'),
        workPackageId: Value('wp'),
        projectId: Value('p1'),
        name: Value('Far future'),
        startMonth: Value(900),
        endMonth: Value(901),
        sortOrder: Value(1),
      ),
    );
    await db.programmeGanttDao.upsertDependency(
      const TimelineDependenciesCompanion(
        id: Value('d1'),
        projectId: Value('p1'),
        fromActivityId: Value('a'),
        toActivityId: Value('b'),
        dependencyType: Value('finish_to_start'),
      ),
    );
  });
  tearDown(() => db.close());

  /// Hosts a button that opens the dialog, then opens it.
  Future<void> open(WidgetTester tester, {LLMClient? client}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) =>
                        ReplanDialog(db: db, projectId: 'p1', client: client),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'scope shows the count, review shows the move, accept writes it',
    (tester) async {
      await open(tester);

      expect(find.text('1 activity has slipped past today.'), findsOneWidget);
      expect(find.textContaining('pushed by them'), findsNothing);
      expect(
        find.text('Set a baseline first so the Gantt shows what moved'),
        findsOneWidget,
      );

      await tester.tap(find.text('Review the move'));
      await tester.pumpAndSettle();
      expect(find.text('Build adapter'), findsOneWidget);
      expect(find.text('CURRENT'), findsOneWidget);
      expect(find.text('PROPOSED'), findsOneWidget);
      expect(find.text('Feb–Apr 2020'), findsOneWidget);
      expect(
        find.textContaining('Start was Feb 2020, before this month'),
        findsOneWidget,
      );

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 move applied.'), findsOneWidget);

      final a = (await db.programmeGanttDao.getActivityById('a'))!;
      expect(a.startMonth, greaterThan(3), reason: 'moved to this month');
      expect(
        a.endMonth,
        a.startMonth! + 2,
        reason: 'three-month duration kept',
      );
      expect(a.notes, contains('Re-planned'));
      expect(a.notes, contains('was Feb–Apr 2020'));
      expect(a.isBaseline, isTrue, reason: 'baseline set first by default');
      expect(a.baselineStart, 1);
      expect(a.baselineEnd, 3);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the proposed span can be edited and the edit is what gets written',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Review the move'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit the proposed dates'));
      await tester.pumpAndSettle();
      expect(find.text('PROPOSED · EDITING'), findsOneWidget);

      // Push the end out by two months via the End dropdown.
      final m0 = DateTime.parse('2020-01-01');
      final now = DateTime.now();
      final thisMonth = (now.year - m0.year) * 12 + now.month - m0.month;
      final newEnd = thisMonth + 4; // engine proposes thisMonth..thisMonth+2
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<int>, 'End'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_label(newEnd, m0)).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use these dates'));
      await tester.pumpAndSettle();
      expect(find.text('PROPOSED · SET BY YOU'), findsOneWidget);
      expect(find.textContaining('Set by you on review'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      final a = (await db.programmeGanttDao.getActivityById('a'))!;
      expect(a.startMonth, thisMonth);
      expect(a.endMonth, newEnd);
      expect(a.notes, contains('Set by you on review'));
    },
  );

  testWidgets('skip writes nothing and the dialog reports it', (tester) async {
    await open(tester);
    await tester.tap(
      find.text('Set a baseline first so the Gantt shows what moved'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review the move'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 1 move applied, 1 skipped.'), findsOneWidget);
    final a = (await db.programmeGanttDao.getActivityById('a'))!;
    expect(a.startMonth, 1);
    expect(a.isBaseline, isFalse, reason: 'checkbox was cleared');
  });

  testWidgets('nothing slipped says so and cannot proceed', (tester) async {
    await db.programmeGanttDao.setActivityStatus('a', 'green');
    await open(tester);
    expect(find.textContaining('Nothing has slipped'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Review 0 moves'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('with AI: the view is shown, the extension is applied on accept, '
      'ticked sub-tasks are created and the rationale lands in the note', (
    tester,
  ) async {
    await open(tester, client: _FakeClient());
    // Ollama is the default provider, so the AI button is offered.
    await tester.tap(find.text('Ask AI, then review'));
    await tester.pumpAndSettle();

    expect(find.text('AI VIEW'), findsOneWidget);
    expect(
      find.textContaining('The vendor workshop widened scope'),
      findsOneWidget,
    );
    expect(find.text('+1 MONTH SUGGESTED'), findsOneWidget);
    expect(find.textContaining('Watch: Vendor contract'), findsOneWidget);
    final toggle = tester.widget<CheckboxListTile>(
      find.widgetWithText(
        CheckboxListTile,
        'Add 1 month to the end. Anything this gates moves with it.',
      ),
    );
    expect(toggle.value, isTrue, reason: 'medium confidence defaults on');

    await tester.tap(find.text('Suggest sub-tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Accept + 3 tasks'), findsOneWidget);
    // Drop one task (the list sits below the fold of the scrolling card).
    await tester.ensureVisible(find.text('Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Accept + 2 tasks'), findsOneWidget);

    await tester.tap(find.text('Accept + 2 tasks'));
    await tester.pumpAndSettle();
    expect(find.text('2 sub-tasks added.'), findsOneWidget);

    final a = (await db.programmeGanttDao.getActivityById('a'))!;
    expect(
      a.endMonth,
      a.startMonth! + 3,
      reason: 'three-month duration plus the accepted one-month extension',
    );
    expect(a.notes, contains('Extended from'));
    expect(
      a.notes,
      contains(
        'AI view (medium confidence): The vendor workshop widened scope.',
      ),
    );
    expect(a.notes, contains('Watch: Vendor contract; SIT entry.'));
    final tasks = await db.programmeGanttDao.getTasksForActivity('a');
    expect(tasks.map((t) => t.name), ['Design', 'Build']);
    expect(tasks.first.startMonth, a.startMonth);
    expect(
      tasks.last.endMonth,
      a.endMonth,
      reason: 'slices cover the extended window',
    );
  });
}

/// Answers the duration question with a one-month extension and the
/// breakdown question with three tasks.
class _FakeClient implements LLMClient {
  @override
  Future<String> complete({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1000,
  }) async {
    if (userMessage.contains('"tasks"')) {
      return '{"tasks": [{"name": "Design", "weight": 1}, '
          '{"name": "Build", "weight": 3}, {"name": "Test", "weight": 2}]}';
    }
    return '{"extra_months": 1, "confidence": "medium", '
        '"rationale": "The vendor workshop widened scope.", '
        '"watch": ["Vendor contract", "SIT entry"]}';
  }

  @override
  Stream<String> stream({
    required String systemPrompt,
    required String userMessage,
  }) => Stream.value('');
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String _label(int month, DateTime m0) {
  final d = DateTime(m0.year, m0.month + month, 1);
  return '${_months[d.month - 1]} ${d.year}';
}
