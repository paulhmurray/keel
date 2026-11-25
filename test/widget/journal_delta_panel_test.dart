import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/journal/journal_parser.dart';
import 'package:keel/features/journal/journal_delta_panel.dart';

DetectedDelta _delta(String id, {String title = 'Link doc to ticket'}) {
  return DetectedDelta(
    id: id,
    type: DeltaType.action,
    title: title,
    fields: {'owner': null, 'dueDate': null},
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  List<DetectedDelta> deltas, {
  VoidCallback? onConfirmAll,
  String? notice,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: JournalDeltaPanel(
        deltas: deltas,
        onConfirmAll: onConfirmAll ?? () {},
        onDismiss: () {},
        notice: notice,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('an AI-fallback notice is shown, and absent by default',
      (tester) async {
    await _pumpPanel(tester, [_delta('d1')]);
    expect(find.byIcon(Icons.info_outline), findsNothing);

    await _pumpPanel(tester, [_delta('d1')],
        notice: 'AI parse failed: no models');
    expect(find.text('AI parse failed: no models'), findsOneWidget);
  });

  testWidgets(
      'typing letters (incl. y/n/e) into an edit field does not confirm '
      'or ignore the item', (tester) async {
    final deltas = [_delta('d1')];
    await _pumpPanel(tester, deltas);

    // Enter edit mode via the Edit button.
    await tester.tap(find.text('E  Edit'));
    await tester.pump();
    expect(find.text('EDITING'), findsOneWidget);

    // Type an owner name containing y, n and e — the letters that double
    // as panel shortcuts. This used to confirm the item mid-edit.
    final ownerField = find.widgetWithText(TextField, '').last;
    await tester.enterText(ownerField, 'Paul');
    for (final key in [
      LogicalKeyboardKey.keyY,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyE,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    expect(deltas.first.confirmed, isFalse);
    expect(deltas.first.ignored, isFalse);
    expect(find.text('EDITING'), findsOneWidget);
  });

  testWidgets('saving an edit stores the fields and confirms the item',
      (tester) async {
    final deltas = [_delta('d1')];
    await _pumpPanel(tester, deltas);

    await tester.tap(find.text('E  Edit'));
    await tester.pump();

    // Owner is the second text field (description is first).
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'Paul Murray');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(deltas.first.confirmed, isTrue);
    expect(deltas.first.editFields['owner'], 'Paul Murray');
  });

  testWidgets('confirmed and ignored items can be reopened and re-edited',
      (tester) async {
    final deltas = [_delta('d1'), _delta('d2', title: 'Second item')];
    await _pumpPanel(tester, deltas);

    // Confirm the first item, ignore the second.
    await tester.tap(find.text('Y  Confirm'));
    await tester.pump();
    await tester.tap(find.text('N  Ignore'));
    await tester.pump();
    expect(deltas[0].confirmed, isTrue);
    expect(deltas[1].ignored, isTrue);
    expect(find.text('↩  Reopen'), findsNWidgets(2));

    // Reopen the confirmed one — it becomes pending and active again.
    await tester.tap(find.text('↩  Reopen').first);
    await tester.pump();
    expect(deltas[0].confirmed, isFalse);
    expect(deltas[0].ignored, isFalse);
    expect(find.text('Y  Confirm'), findsOneWidget);

    // And it can be edited again — repeatedly.
    await tester.tap(find.text('E  Edit'));
    await tester.pump();
    expect(find.text('EDITING'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'Dana');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(deltas[0].confirmed, isTrue);
    expect(deltas[0].editFields['owner'], 'Dana');

    // Second round trip: reopen → edit shows the previous edit's value.
    await tester.tap(find.text('↩  Reopen').first);
    await tester.pump();
    await tester.tap(find.text('E  Edit'));
    await tester.pump();
    final ownerField = tester
        .widgetList<TextField>(find.byType(TextField))
        .elementAt(1);
    expect(ownerField.controller!.text, 'Dana');
  });

  testWidgets('edited description replaces the parser title on the card',
      (tester) async {
    final deltas = [_delta('d1')];
    await _pumpPanel(tester, deltas);

    await tester.tap(find.text('E  Edit'));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField).first, 'Attach design doc to JIRA-123');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Attach design doc to JIRA-123'), findsOneWidget);
    expect(find.text('Link doc to ticket'), findsNothing);
  });

  group('auto-scroll', () {
    Future<ScrollPosition> pumpShort(
        WidgetTester tester, List<DetectedDelta> deltas) async {
      tester.view.physicalSize = const Size(800, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpPanel(tester, deltas);
      return tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
    }

    bool fullyVisible(WidgetTester tester, String title) {
      final item = tester.getRect(find.text(title));
      final pane =
          tester.getRect(find.byType(SingleChildScrollView).first);
      return item.top >= pane.top - 0.5 && item.bottom <= pane.bottom + 0.5;
    }

    testWidgets(
        'actioning items with Y/N keeps the next pending change in view',
        (tester) async {
      final deltas = [
        for (var i = 0; i < 10; i++) _delta('d$i', title: 'Change $i'),
      ];
      final pos = await pumpShort(tester, deltas);
      expect(pos.maxScrollExtent, greaterThan(0),
          reason: 'needs more changes than fit');

      for (var i = 0; i < 9; i++) {
        await tester.sendKeyEvent(
            i.isEven ? LogicalKeyboardKey.keyY : LogicalKeyboardKey.keyN);
        await tester.pumpAndSettle();
        expect(fullyVisible(tester, 'Change ${i + 1}'), isTrue,
            reason: 'after actioning Change $i');
      }
      expect(pos.pixels, greaterThan(0));
    });

    testWidgets('Tab and Shift+Tab scroll to the item they land on',
        (tester) async {
      final deltas = [
        for (var i = 0; i < 10; i++) _delta('d$i', title: 'Change $i'),
      ];
      final pos = await pumpShort(tester, deltas);
      for (var i = 0; i < 9; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(fullyVisible(tester, 'Change 9'), isTrue);
      final bottom = pos.pixels;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      for (var i = 0; i < 9; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(fullyVisible(tester, 'Change 0'), isTrue);
      expect(pos.pixels, lessThan(bottom));
    });
  });

  group('revealOffset', () {
    test('already visible: no scroll', () {
      expect(revealOffset(current: 100, alignTop: 150, alignBottom: 50),
          isNull);
    });
    test('below the fold: bring its bottom up', () {
      expect(revealOffset(current: 0, alignTop: 400, alignBottom: 120), 120);
    });
    test('above: show its top', () {
      expect(revealOffset(current: 500, alignTop: 300, alignBottom: 0), 300);
    });
    test('taller than the pane: show its top, not its bottom', () {
      expect(revealOffset(current: 0, alignTop: 400, alignBottom: 600), 400);
    });
  });
}
