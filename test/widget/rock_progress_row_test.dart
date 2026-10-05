import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/helm/helm_week_view.dart';

/// The shared rock readout: a square per allocated slot, filled as
/// blocks get done, the label struck through once the day's allocation
/// is met. Week cards and the day panel both render this.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: child))),
      );

  testWidgets('draws one square per slot and the count', (tester) async {
    await pump(tester,
        const RockProgressRow(label: 'Build adapter', slots: 3, done: 1));
    // Three slot squares plus nothing else sized 9×9.
    final squares = tester.widgetList<Container>(find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 9));
    expect(squares.length, 3);
    expect(find.text('1/3'), findsOneWidget);
    final label = tester.widget<Text>(find.text('Build adapter'));
    expect(label.style?.decoration, isNull);
  });

  testWidgets('a met rock is struck through', (tester) async {
    await pump(tester,
        const RockProgressRow(label: 'Status pack', slots: 2, done: 2));
    final label = tester.widget<Text>(find.text('Status pack'));
    expect(label.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('trailing widget sits after the count', (tester) async {
    await pump(
        tester,
        const RockProgressRow(
            label: 'x', slots: 1, done: 0, trailing: Text('Place')));
    expect(find.text('Place'), findsOneWidget);
  });
}
