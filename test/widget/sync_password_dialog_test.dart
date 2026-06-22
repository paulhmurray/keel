import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/shared/widgets/sync_password_dialog.dart';

/// Pumps a button that opens [showSyncPasswordDialog] and returns a way
/// to read the resolved value once the dialog closes.
Future<void> _pumpHost(
  WidgetTester tester,
  void Function(String?) onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => onResult(await showSyncPasswordDialog(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('returns the entered password on Continue', (tester) async {
    String? result;
    var called = false;
    await _pumpHost(tester, (r) {
      result = r;
      called = true;
    });

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, 'hunter2');
  });

  testWidgets('returns null on Cancel', (tester) async {
    String? result = 'sentinel';
    await _pumpHost(tester, (r) => result = r);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ignored');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
