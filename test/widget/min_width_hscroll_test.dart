import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/shared/widgets/min_width_hscroll.dart';

void main() {
  Widget host(double viewportWidth) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: viewportWidth,
              height: 200,
              child: MinWidthHScroll(
                minWidth: 500,
                // A Row that would overflow below 500px.
                child: Row(
                  children: [
                    const SizedBox(width: 480, child: Text('content')),
                    Container(width: 20, color: Colors.red),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('wide viewport: transparent pass-through, no scroller',
      (tester) async {
    await tester.pumpWidget(host(600));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow viewport: content gets minWidth and scrolls '
      'instead of overflowing', (tester) async {
    await tester.pumpWidget(host(300));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // No RenderFlex overflow exception.
    expect(tester.takeException(), isNull);
    final box = tester.renderObject<RenderBox>(find.byType(Row).first);
    expect(box.size.width, 500);
  });
}
