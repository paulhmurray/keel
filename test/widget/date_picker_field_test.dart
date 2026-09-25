import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/shared/widgets/date_picker_field.dart';

/// A parent that rewrites the date from outside (the Plan dialog does
/// this when the month dropdown moves a dated activity). The field must
/// follow the new value without making the Form rebuild mid-build.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? iso = '2026-10-21';
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Form(
          child: Column(children: [
            DatePickerField(
              label: 'Exact date',
              isoValue: iso,
              onChanged: (v) => setState(() => iso = v),
            ),
            ElevatedButton(
              onPressed: () => setState(() => iso = '2026-08-21'),
              child: const Text('move to august'),
            ),
          ]),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('external date change updates the field without a build-phase '
      'setState on the Form', (tester) async {
    await tester.pumpWidget(const _Host());
    expect(find.text('21-10-2026'), findsOneWidget);

    await tester.tap(find.text('move to august'));
    await tester.pump(); // rebuild with the new value
    await tester.pump(); // post-frame controller write lands
    expect(tester.takeException(), isNull);
    expect(find.text('21-08-2026'), findsOneWidget);
  });
}
