import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/actions/action_form.dart';
import 'package:keel/features/decisions/decision_form.dart';
import 'package:keel/features/journal/journal_source_link.dart';
import 'package:keel/features/raid/assumption_form.dart';
import 'package:keel/features/raid/dependency_form.dart';
import 'package:keel/features/raid/issue_form.dart';
import 'package:keel/features/raid/risk_form.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:keel/shared/widgets/ai_assist_button.dart';
import 'package:keel/shared/widgets/detail_dialog.dart';
import 'package:provider/provider.dart';

/// Smoke tests for the wide two-column item dialogs shared by Actions
/// and RAID. They pump each dialog in view and edit mode at a wide
/// (two-column) and narrow (single-column) window, so a layout overflow
/// or a null crash in any of them fails here rather than on first open.
const _pid = 'p1';

Future<void> _seed(AppDatabase db) async {
  await db.projectDao
      .insertProject(ProjectsCompanion.insert(id: _pid, name: 'P1'));

  // Plan: one WP, one dated activity, header anchor.
  await db.programmeGanttDao.upsertWorkPackage(const TimelineWorkPackagesCompanion(
    id: Value('wp1'),
    projectId: Value(_pid),
    name: Value('Integration'),
    shortCode: Value('INT'),
    sortOrder: Value(0),
  ));
  await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
    id: Value('act1'),
    workPackageId: Value('wp1'),
    projectId: Value(_pid),
    name: Value('Build the API adapter'),
    startMonth: Value(2),
    endMonth: Value(4),
    startDate: Value('2026-11-02'),
    endDate: Value('2027-01-15'),
    sortOrder: Value(0),
  ));
  await db.programmeGanttDao.upsertHeader(const ProgrammeHeadersCompanion(
    id: Value('hdr'),
    projectId: Value(_pid),
    month0Date: Value('2026-09-01'),
  ));

  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r1'),
    projectId: Value(_pid),
    ref: Value('R1'),
    description: Value('The vendor may miss the API delivery date, which '
        'would stall integration testing for the whole programme and '
        'push the go-live decision into the next quarter.'),
    likelihood: Value('high'),
    impact: Value('high'),
    likelihoodRationale: Value('They have slipped twice already.'),
    impactRationale: Value('Integration is on the critical path.'),
    mitigation: Value('- Weekly vendor checkpoint\n- Stub the API'),
    owner: Value('Sam'),
  ));
  await db.raidDao.upsertIssue(const IssuesCompanion(
    id: Value('i1'),
    projectId: Value(_pid),
    ref: Value('I1'),
    title: Value('UAT environment down'),
    description: Value('The UAT environment has been unavailable for three days.'),
    impactStatement: Value('Test cycle 2 cannot start.'),
    escalationRequired: Value(true),
    priority: Value('critical'),
    dueDate: Value('2026-10-01'),
  ));
  await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
    id: Value('d1'),
    projectId: Value(_pid),
    ref: Value('D1'),
    description: Value('Vendor delivers the signed API contract'),
    dependencyType: Value('inbound'),
    counterparty: Value('Acme Vendor'),
    rationale: Value('The adapter cannot be built against an unsigned spec.'),
    impactStatement: Value('Adapter build slips week-for-week.'),
    planActivityId: Value('act1'),
    dueDate: Value('2026-10-15'),
    owner: Value('Sam'),
  ));
  await db.raidDao.upsertAssumption(const AssumptionsCompanion(
    id: Value('a1'),
    projectId: Value(_pid),
    ref: Value('A1'),
    description: Value('The vendor sandbox mirrors production behaviour.'),
  ));

  await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
    id: 'parent',
    projectId: _pid,
    description: 'Prepare the steering pack',
    ref: const Value('AC1'),
    isParent: const Value(true),
    planActivityId: const Value('act1'),
  ));
  await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
    id: 'c1',
    projectId: _pid,
    description: 'Draft the narrative',
    ref: const Value('AC2'),
    parentActionId: const Value('parent'),
    status: const Value('closed'),
  ));
  await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
    id: 'c2',
    projectId: _pid,
    description: 'Collect the numbers',
    ref: const Value('AC3'),
    parentActionId: const Value('parent'),
    dueDate: const Value('2026-10-03'),
  ));
  await db.decisionsDao.upsertDecision(const DecisionsCompanion(
    id: Value('dc1'),
    projectId: Value(_pid),
    ref: Value('DC1'),
    description: Value('Which payments gateway do we integrate first?'),
    status: Value('pending'),
    decisionMaker: Value('CFO'),
    dueDate: Value('2026-10-20'),
    optionsConsidered: Value('- Stripe: fastest\n- Adyen: cheaper at scale'),
    impactStatement: Value('Adapter build cannot start until chosen.'),
    rationale: Value('Speed to market beats unit cost this quarter.'),
    planActivityId: Value('act1'),
    source: Value('journal'),
  ));

  // A journal entry the risk and the decision were extracted from.
  await db.journalDao.upsertEntry(const JournalEntriesCompanion(
    id: Value('je1'),
    projectId: Value(_pid),
    title: Value('Vendor sync'),
    body: Value('Weekly vendor sync with Acme.\n\n'
        'Acme said the API delivery date may slip again, which would '
        'stall integration testing and push go-live.\n\n'
        'We still need to pick the payments gateway before the adapter '
        'build can start.'),
    entryDate: Value('2026-09-14'),
    parsed: Value(true),
  ));
  await db.journalDao.insertLink(const JournalEntryLinksCompanion(
    id: Value('jl1'),
    entryId: Value('je1'),
    itemType: Value('risk'),
    itemId: Value('r1'),
  ));
  await db.journalDao.insertLink(const JournalEntryLinksCompanion(
    id: Value('jl2'),
    entryId: Value('je1'),
    itemType: Value('decision'),
    itemId: Value('dc1'),
  ));

  await db.actionCommentsDao.upsertComment(const ActionCommentsCompanion(
    id: Value('cm1'),
    actionId: Value('parent'),
    content: Value('Finance numbers land Thursday.'),
    authorName: Value('Paul'),
  ));
}

/// Opens [dialog] from a host page and settles the async loads.
Future<void> _open(
  WidgetTester tester,
  AppDatabase db,
  Widget dialog, {
  required Size size,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  // Semantics on: the desktop app runs with accessibility enabled and
  // the framework asserts on dirty semantics parent data there.
  _semantics ??= tester.ensureSemantics();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    showDialog(context: context, builder: (_) => dialog),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Dialog route + the forms' async DB loads + stream first frame.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

SemanticsHandle? _semantics;

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  _semantics?.dispose();
  _semantics = null;
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

/// Fails with the full FlutterError text (which names the offending
/// widget and its creator chain) rather than a bare "expected null".
void _expectNoException(WidgetTester tester) {
  final e = tester.takeException();
  if (e != null) {
    fail('Unexpected exception during dialog build:\n$e');
  }
}

const _wide = Size(1600, 1000);
const _narrow = Size(1000, 800);

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await _seed(db);
  });

  tearDown(() async => db.close());

  group('frame', () {
    testWidgets('two columns at ≥1280, one column below', (tester) async {
      final risk = (await db.raidDao.getRiskById('r1'))!;
      await _open(tester, db,
          RiskFormDialog(projectId: _pid, db: db, risk: risk, startInViewMode: true),
          size: _wide);
      expect(find.byType(DetailDialog), findsOneWidget);
      // Mitigation lives in the right column; at this width it renders
      // beside the description rather than below it.
      final desc = tester.getTopLeft(find.text('DESCRIPTION'));
      final mit = tester.getTopLeft(find.text('RISK OWNER'));
      expect(mit.dx, greaterThan(desc.dx + 300));
      expect((mit.dy - desc.dy).abs(), lessThan(40));
      await _close(tester);

      await _open(tester, db,
          RiskFormDialog(projectId: _pid, db: db, risk: risk, startInViewMode: true),
          size: _narrow);
      final desc2 = tester.getTopLeft(find.text('DESCRIPTION'));
      final mit2 = tester.getTopLeft(find.text('RISK OWNER'));
      expect((mit2.dx - desc2.dx).abs(), lessThan(4));
      expect(mit2.dy, greaterThan(desc2.dy));
      await _close(tester);
    });
  });

  group('risk', () {
    testWidgets('view shows the whole description and both rationales',
        (tester) async {
      final risk = (await db.raidDao.getRiskById('r1'))!;
      for (final size in [_wide, _narrow]) {
        await _open(tester, db,
            RiskFormDialog(projectId: _pid, db: db, risk: risk, startInViewMode: true),
            size: size);
        expect(find.textContaining('push the go-live decision'), findsOneWidget);
        expect(find.text('WHY THIS LIKELIHOOD'), findsOneWidget);
        expect(find.text('WHY THIS CONSEQUENCE'), findsOneWidget);
        expect(find.textContaining('Weekly vendor checkpoint'), findsOneWidget);
        // Seeded as legacy high/high → likely/major, score 16.
        expect(find.text('Likely / Major · 16'), findsOneWidget);
        _expectNoException(tester);
        await _close(tester);
      }
    });

    testWidgets('edit offers AI labels but hides the button without a key',
        (tester) async {
      final risk = (await db.raidDao.getRiskById('r1'))!;
      await _open(tester, db, RiskFormDialog(projectId: _pid, db: db, risk: risk),
          size: _wide);
      expect(find.text('WHY THIS LIKELIHOOD?'), findsOneWidget);
      expect(find.text('WHY THIS CONSEQUENCE?'), findsOneWidget);
      expect(find.text('TREATMENT PLAN'), findsOneWidget);
      expect(find.text('Escalate this risk'), findsOneWidget);
      expect(find.text('Reviewed today (+14 days)'), findsOneWidget);
      expect(find.byType(AiAssistButton), findsNWidgets(4));
      expect(find.text('AI draft'), findsNothing);
      expect(find.text('RELATED ITEMS'), findsOneWidget);
      expect(find.text('Convert'), findsOneWidget);
      _expectNoException(tester);
      await _close(tester);
    });

    testWidgets('create mode renders without a row', (tester) async {
      await _open(tester, db, RiskFormDialog(projectId: _pid, db: db),
          size: _narrow);
      expect(find.text('New Risk'), findsOneWidget);
      expect(find.text('RELATED ITEMS'), findsNothing);
      _expectNoException(tester);
      await _close(tester);
    });
  });

  group('issue', () {
    testWidgets('view and edit at both widths', (tester) async {
      final issue = (await db.raidDao.getIssueById('i1'))!;
      for (final size in [_wide, _narrow]) {
        await _open(tester, db,
            IssueFormDialog(projectId: _pid, db: db, issue: issue, startInViewMode: true),
            size: size);
        expect(find.text('UAT environment down'), findsOneWidget);
        expect(find.text('ESCALATION REQUIRED'), findsOneWidget);
        expect(find.text('IMPACT IF UNRESOLVED'), findsOneWidget);
        expect(find.text('CRITICAL'), findsOneWidget);
        _expectNoException(tester);
        await _close(tester);

        await _open(tester, db, IssueFormDialog(projectId: _pid, db: db, issue: issue),
            size: size);
        expect(find.text('IMPACT STATEMENT'), findsOneWidget);
        expect(find.text('RESOLUTION'), findsOneWidget);
        expect(find.byType(AiAssistButton), findsNWidgets(3));
        _expectNoException(tester);
        await _close(tester);
      }
    });
  });

  group('dependency', () {
    testWidgets('view shows why / impact / counterparty and the slack chip',
        (tester) async {
      final dep = (await db.raidDao.getDependencyById('d1'))!;
      for (final size in [_wide, _narrow]) {
        await _open(tester, db,
            DependencyFormDialog(projectId: _pid, db: db, dependency: dep, startInViewMode: true),
            size: size);
        expect(find.text('WHY THIS IS A DEPENDENCY'), findsOneWidget);
        expect(find.text('IMPACT IF IT SLIPS'), findsOneWidget);
        expect(find.text('Acme Vendor'), findsOneWidget);
        expect(find.text('GATES PLAN ACTIVITY'), findsOneWidget);
        expect(find.text('[INT] Build the API adapter'), findsOneWidget);
        // 15 Oct needed-by vs 2 Nov start = 18 days of slack.
        expect(find.text('18 days slack before the activity starts'),
            findsOneWidget);
        _expectNoException(tester);
        await _close(tester);
      }
    });

    testWidgets('edit shows the plan picker, slack and show-on-plan toggle',
        (tester) async {
      final dep = (await db.raidDao.getDependencyById('d1'))!;
      await _open(tester, db,
          DependencyFormDialog(projectId: _pid, db: db, dependency: dep),
          size: _wide);
      expect(find.text('Plan activity that needs it'), findsOneWidget);
      expect(find.text('18 days slack before the activity starts'),
          findsOneWidget);
      expect(find.textContaining('Show on the plan'), findsOneWidget);
      expect(find.byType(AiAssistButton), findsNWidgets(3));
      _expectNoException(tester);
      await _close(tester);
    });

    testWidgets('unlinked dependency explains what the plan link adds',
        (tester) async {
      await _open(tester, db, DependencyFormDialog(projectId: _pid, db: db),
          size: _narrow);
      expect(find.textContaining('Not linked to a plan activity'), findsOneWidget);
      expect(find.textContaining('Show on the plan'), findsNothing);
      _expectNoException(tester);
      await _close(tester);
    });
  });

  group('assumption', () {
    testWidgets('view and edit render in the shared frame', (tester) async {
      final a = (await db.raidDao.getAssumptionById('a1'))!;
      await _open(tester, db,
          AssumptionFormDialog(projectId: _pid, db: db, assumption: a, startInViewMode: true),
          size: _wide);
      expect(find.byType(DetailDialog), findsOneWidget);
      expect(find.textContaining('sandbox mirrors'), findsOneWidget);
      _expectNoException(tester);
      await _close(tester);

      await _open(tester, db, AssumptionFormDialog(projectId: _pid, db: db, assumption: a),
          size: _narrow);
      expect(find.text('Edit Assumption'), findsOneWidget);
      expect(find.text('RELATED ITEMS'), findsOneWidget);
      _expectNoException(tester);
      await _close(tester);
    });
  });

  group('action', () {
    testWidgets('view lists sub-tasks with progress and the comment thread',
        (tester) async {
      final a = (await db.actionsDao.getActionById('parent'))!;
      for (final size in [_wide, _narrow]) {
        await _open(tester, db,
            ActionFormDialog(projectId: _pid, db: db, action: a, startInViewMode: true),
            size: size);
        expect(find.text('SUB-TASKS · 1 OF 2 DONE'), findsOneWidget);
        expect(find.text('Draft the narrative'), findsOneWidget);
        expect(find.text('Collect the numbers'), findsOneWidget);
        expect(find.text('COMMENTS'), findsOneWidget);
        expect(find.text('Finance numbers land Thursday.'), findsOneWidget);
        expect(find.text('[INT] Build the API adapter'), findsOneWidget);
        _expectNoException(tester);
        await _close(tester);
      }
    });

    testWidgets('edit keeps comments visible and quick-adds a sub-task',
        (tester) async {
      final a = (await db.actionsDao.getActionById('parent'))!;
      await _open(tester, db, ActionFormDialog(projectId: _pid, db: db, action: a),
          size: _wide);
      expect(find.text('Edit Action'), findsOneWidget);
      expect(find.text('COMMENTS'), findsOneWidget);
      expect(find.text('Finance numbers land Thursday.'), findsOneWidget);
      expect(find.text('SUB-TASKS · 1 OF 2 DONE'), findsOneWidget);

      final field = find.widgetWithText(
          TextField, 'Add sub-task — Enter to save, keep typing for more');
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Book the room');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Book the room'), findsOneWidget);
      expect(find.text('SUB-TASKS · 1 OF 3 DONE'), findsOneWidget);
      final all = await db.actionsDao.getActionsForProject(_pid);
      final added = all.singleWhere((x) => x.description == 'Book the room');
      expect(added.parentActionId, 'parent');
      expect(added.planActivityId, 'act1');
      _expectNoException(tester);
      await _close(tester);
    });

    testWidgets('a sub-task cannot grow children of its own', (tester) async {
      await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
        id: 'grandchild',
        projectId: _pid,
        description: 'Leaf',
        parentActionId: const Value('c2'),
      ));
      final leaf = (await db.actionsDao.getActionById('grandchild'))!;
      await _open(tester, db, ActionFormDialog(projectId: _pid, db: db, action: leaf),
          size: _wide);
      expect(find.textContaining('Sub-tasks can’t contain actions'),
          findsWidgets);
      expect(find.widgetWithText(TextField,
          'Add sub-task — Enter to save, keep typing for more'), findsNothing);
      _expectNoException(tester);
      await _close(tester);
    });

    testWidgets('create mode queues sub-tasks until the action saves',
        (tester) async {
      await _open(tester, db, ActionFormDialog(projectId: _pid, db: db),
          size: _wide);
      expect(find.text('New Action'), findsOneWidget);
      expect(find.text('COMMENTS'), findsNothing);
      final field = find.widgetWithText(
          TextField, 'Add sub-task — created with the action');
      await tester.enterText(field, 'First step');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('First step'), findsOneWidget);
      expect(await db.actionsDao.getActionsForProject(_pid), hasLength(3));

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description *'), 'Run the retro');
      await tester.tap(find.text('Create'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final all = await db.actionsDao.getActionsForProject(_pid);
      final parent = all.singleWhere((x) => x.description == 'Run the retro');
      final child = all.singleWhere((x) => x.description == 'First step');
      expect(parent.isParent, isTrue);
      expect(child.parentActionId, parent.id);
      _expectNoException(tester);
      await _close(tester);
    });
  });

  group('decision', () {
    testWidgets('view shows options, impact, plan link and slack', (tester) async {
      final d = (await db.decisionsDao.getDecisionById('dc1'))!;
      for (final size in [_wide, _narrow]) {
        await _open(tester, db,
            DecisionFormDialog(projectId: _pid, db: db, decision: d, startInViewMode: true),
            size: size);
        expect(find.text('OPTIONS CONSIDERED'), findsOneWidget);
        expect(find.text('IMPACT OF LEAVING IT OPEN'), findsOneWidget);
        expect(find.text('PLAN ACTIVITY WAITING ON THIS'), findsOneWidget);
        expect(find.text('[INT] Build the API adapter'), findsOneWidget);
        // 20 Oct needed-by vs 2 Nov start = 13 days → tight.
        expect(find.text('13 days slack before the activity starts'),
            findsOneWidget);
        expect(find.text('FROM JOURNAL'), findsOneWidget);
        _expectNoException(tester);
        await _close(tester);
      }
    });

    testWidgets('edit offers three AI fields, the plan picker and journal chip',
        (tester) async {
      final d = (await db.decisionsDao.getDecisionById('dc1'))!;
      await _open(tester, db, DecisionFormDialog(projectId: _pid, db: db, decision: d),
          size: _wide);
      expect(find.text('Edit Decision'), findsOneWidget);
      expect(find.byType(AiAssistButton), findsNWidgets(3));
      expect(find.text('Plan activity waiting on this decision'), findsOneWidget);
      expect(find.textContaining('Show on the plan'), findsOneWidget);
      expect(find.text('FROM JOURNAL'), findsOneWidget);
      expect(find.text('RELATED ITEMS'), findsOneWidget);
      _expectNoException(tester);
      await _close(tester);
    });

    testWidgets('a made decision shows decided-on instead of a slack threat',
        (tester) async {
      await db.decisionsDao.upsertDecision(const DecisionsCompanion(
        id: Value('dc-made'),
        projectId: Value(_pid),
        ref: Value('DC2'),
        description: Value('Gateway chosen: Stripe'),
        status: Value('decided'),
        decidedAt: Value('2026-09-18'),
        dueDate: Value('2026-12-01'), // after the activity starts
        planActivityId: Value('act1'),
      ));
      final d = (await db.decisionsDao.getDecisionById('dc-made'))!;
      await _open(tester, db,
          DecisionFormDialog(projectId: _pid, db: db, decision: d, startInViewMode: true),
          size: _wide);
      expect(find.textContaining('AFTER the activity'), findsNothing);
      expect(find.textContaining('no longer holding up'), findsOneWidget);
      expect(find.textContaining('18'), findsWidgets);
      _expectNoException(tester);
      await _close(tester);
    });

    testWidgets('create mode renders at narrow width', (tester) async {
      await _open(tester, db, DecisionFormDialog(projectId: _pid, db: db),
          size: _narrow);
      expect(find.text('New Decision'), findsOneWidget);
      expect(find.text('FROM JOURNAL'), findsNothing);
      _expectNoException(tester);
      await _close(tester);
    });
  });

  group('journal source', () {
    testWidgets('chip appears on a journal-sourced item and opens the entry '
        'with the matching passage highlighted', (tester) async {
      final risk = (await db.raidDao.getRiskById('r1'))!;
      await _open(tester, db,
          RiskFormDialog(projectId: _pid, db: db, risk: risk, startInViewMode: true),
          size: _wide);
      expect(find.text('FROM JOURNAL'), findsOneWidget);
      final chip = find.textContaining('Vendor sync');
      expect(chip, findsOneWidget);

      await tester.tap(chip);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(JournalEntryPeekDialog), findsOneWidget);
      // The body is rendered as rich text (person/glossary links).
      expect(find.textContaining('may slip again', findRichText: true),
          findsOneWidget);
      expect(find.text('Open in Journal'), findsOneWidget);
      // The vendor-slip paragraph is the highlighted one, not the gateway one.
      final highlight = find.byKey(const Key('journal-peek-highlight'));
      expect(highlight, findsOneWidget);
      expect(
          find.descendant(
              of: highlight,
              matching: find.textContaining('API delivery date',
                  findRichText: true)),
          findsOneWidget);
      expect(
          find.descendant(
              of: highlight,
              matching:
                  find.textContaining('payments gateway', findRichText: true)),
          findsNothing);
      _expectNoException(tester);
      await _close(tester);
    });

    testWidgets('no chip on a manually created item', (tester) async {
      final issue = (await db.raidDao.getIssueById('i1'))!;
      await _open(tester, db,
          IssueFormDialog(projectId: _pid, db: db, issue: issue, startInViewMode: true),
          size: _wide);
      expect(find.text('FROM JOURNAL'), findsNothing);
      _expectNoException(tester);
      await _close(tester);
    });
  });

  group('closure', () {
    testWidgets('a closed risk shows closed-on and the closure note',
        (tester) async {
      await db.raidDao.upsertRisk(const RisksCompanion(
        id: Value('r-closed'),
        projectId: Value(_pid),
        ref: Value('R9'),
        description: Value('Data centre move slips'),
        status: Value('accepted'),
        closedAt: Value('2026-09-05'),
        closureNote: Value('Move completed early; risk retired.'),
      ));
      final r = (await db.raidDao.getRiskById('r-closed'))!;
      await _open(tester, db,
          RiskFormDialog(projectId: _pid, db: db, risk: r, startInViewMode: true),
          size: _wide);
      expect(find.text('ACCEPTED ON'), findsOneWidget);
      expect(find.text('WHY ACCEPTED'), findsOneWidget);
      expect(find.textContaining('risk retired'), findsOneWidget);
      _expectNoException(tester);
      await _close(tester);

      // Edit mode offers the closure note field only while terminal.
      await _open(tester, db, RiskFormDialog(projectId: _pid, db: db, risk: r),
          size: _wide);
      expect(find.widgetWithText(TextFormField, 'Why accepted'), findsOneWidget);
      _expectNoException(tester);
      await _close(tester);
    });

    testWidgets('an open risk has no closure fields', (tester) async {
      final r = (await db.raidDao.getRiskById('r1'))!;
      await _open(tester, db, RiskFormDialog(projectId: _pid, db: db, risk: r),
          size: _wide);
      expect(find.widgetWithText(TextFormField, 'Why closed'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Why accepted'), findsNothing);
      _expectNoException(tester);
      await _close(tester);
    });

    testWidgets('a closed dependency reports the arrow is off, not slack',
        (tester) async {
      await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
        id: Value('d-closed'),
        projectId: Value(_pid),
        ref: Value('D3'),
        description: Value('Old contract'),
        status: Value('closed'),
        closedAt: Value('2026-09-05'),
        dueDate: Value('2026-12-01'),
        planActivityId: Value('act1'),
      ));
      final d = (await db.raidDao.getDependencyById('d-closed'))!;
      await _open(tester, db,
          DependencyFormDialog(projectId: _pid, db: db, dependency: d, startInViewMode: true),
          size: _wide);
      expect(find.textContaining('AFTER the activity'), findsNothing);
      expect(find.textContaining('no longer holding up'), findsOneWidget);
      expect(find.text('CLOSED ON'), findsOneWidget);
      _expectNoException(tester);
      await _close(tester);
    });
  });
}
