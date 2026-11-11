import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/helm/helm_lens.dart';
import 'package:keel/features/helm/helm_lens_chip.dart';

Project _p(String id, String name, String kind) {
  final t = DateTime(2026, 1, 1);
  return Project(
    id: id,
    name: name,
    status: 'active',
    kind: kind,
    createdAt: t,
    updatedAt: t,
  );
}

final _projects = [
  _p('tac', 'TAC Integration', 'project'),
  _p('horizon', 'Horizon Programme', 'programme'),
  _p('pmo', 'Enterprise PMO', 'portfolio'),
  _p('dt', 'Digital Toolkit', 'programme'),
];

Future<void> _pumpOpen(WidgetTester tester, HelmLens lens,
    void Function(HelmLens?) onPicked) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async => onPicked(await showDialog<HelmLens>(
              context: context,
              builder: (_) => HelmLensDialog(projects: _projects, lens: lens),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists portfolios, then programmes, then projects by name', (tester) async {
    await _pumpOpen(tester, HelmLens.all, (_) {});
    expect(find.text('What Helm plans around'), findsOneWidget);
    final names = ['Enterprise PMO', 'Digital Toolkit', 'Horizon Programme', 'TAC Integration'];
    final ys = names.map((n) => tester.getTopLeft(find.text(n)).dy).toList();
    expect(ys, [...ys]..sort(), reason: 'kind order, then alphabetical');
    // "All projects" is on, so the checkboxes are disabled.
    final tile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'TAC Integration'));
    expect(tile.enabled, isFalse);
  });

  testWidgets('narrowing to one project returns an active lens', (tester) async {
    HelmLens? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showDialog<HelmLens>(
                context: context,
                builder: (_) => HelmLensDialog(projects: _projects, lens: HelmLens.all),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Pick at least one project, or Helm shows all of them.'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'TAC Integration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(picked, const HelmLens(projectIds: {'tac'}, on: true));
    expect(helmLensLabel(picked!, {for (final p in _projects) p.id: p.name}),
        'TAC Integration');
  });

  testWidgets('switching back to all keeps the picks but turns the lens off', (tester) async {
    HelmLens? picked;
    const start = HelmLens(projectIds: {'tac', 'dt'}, on: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showDialog<HelmLens>(
                context: context,
                builder: (_) => HelmLensDialog(projects: _projects, lens: start),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(picked!.on, isFalse);
    expect(picked!.projectIds, {'tac', 'dt'}, reason: 'remembered for next time');
    expect(picked!.active, isFalse);
  });

  testWidgets('cancel returns nothing', (tester) async {
    HelmLens? picked = HelmLens.all;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showDialog<HelmLens>(
                context: context,
                builder: (_) => HelmLensDialog(projects: _projects, lens: HelmLens.all),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
