import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/journal/journal_slash_menu.dart';

/// The / command menu holds more commands than fit; moving the highlight
/// with the keyboard must keep it on screen, and the list must scroll.
void main() {
  Future<void> pumpMenu(WidgetTester tester, int selected,
      {double height = 400}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            top: 0,
            left: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: height,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: JournalSlashMenu(
                    query: '',
                    selectedIndex: selected,
                    onSelect: (_) {},
                    onDismiss: () {},
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  bool visible(WidgetTester tester, String command) {
    final row = tester.getRect(find.text(command));
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    return row.top >= viewport.top - 0.5 && row.bottom <= viewport.bottom + 0.5;
  }

  testWidgets('stepping down to the last command scrolls it into view, and '
      'wrapping to the first scrolls back up', (tester) async {
    final last = kSlashCommands.length - 1;
    await pumpMenu(tester, 0);
    expect(visible(tester, kSlashCommands[last].command), isFalse,
        reason: 'the menu must be shorter than the list for this test');

    for (var i = 1; i <= last; i++) {
      await pumpMenu(tester, i);
      expect(visible(tester, kSlashCommands[i].command), isTrue,
          reason: kSlashCommands[i].command);
    }
    await pumpMenu(tester, 0); // wrap-around
    expect(visible(tester, kSlashCommands[0].command), isTrue);
  });

  testWidgets('a short editor shrinks the menu rather than cutting it off',
      (tester) async {
    await pumpMenu(tester, 0, height: 150);
    final menu = tester.getRect(find.byType(JournalSlashMenu));
    expect(menu.height, lessThanOrEqualTo(150));
    await pumpMenu(tester, kSlashCommands.length - 1, height: 150);
    expect(visible(tester, kSlashCommands.last.command), isTrue);
  });

  testWidgets('the list scrolls with a drag (mouse wheel / trackpad)',
      (tester) async {
    await pumpMenu(tester, 0);
    final pos = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    await tester.drag(find.text(kSlashCommands[2].command), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(pos.pixels, greaterThan(0));
  });
}
