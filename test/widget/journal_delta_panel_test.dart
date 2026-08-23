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
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: JournalDeltaPanel(
        deltas: deltas,
        onConfirmAll: onConfirmAll ?? () {},
        onDismiss: () {},
      ),
    ),
  ));
  await tester.pump();
}

void main() {
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
}
