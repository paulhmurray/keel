import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/helm/helm_lens.dart';
import 'package:keel/providers/settings_provider.dart';

void main() {
  group('HelmLens', () {
    test('off or empty means every project', () {
      expect(HelmLens.all.active, isFalse);
      expect(const HelmLens(projectIds: {'a'}, on: false).active, isFalse);
      expect(const HelmLens(projectIds: {}, on: true).active, isFalse);
      expect(HelmLens.all.includes('anything'), isTrue);
    });

    test('an active lens keeps only its projects', () {
      const lens = HelmLens(projectIds: {'tac'}, on: true);
      final items = [
        (id: 1, project: 'tac'),
        (id: 2, project: 'sample'),
        (id: 3, project: 'tac'),
      ];
      expect(lens.apply(items, (i) => i.project).map((i) => i.id), [1, 3]);
      expect(lens.includes('sample'), isFalse);
    });

    test('an inactive lens returns the list untouched', () {
      final items = [(project: 'a'), (project: 'b')];
      expect(identical(HelmLens.all.apply(items, (i) => i.project), items), isTrue);
    });

    test('ids of deleted projects are dropped; only stale ids falls back to all', () {
      const lens = HelmLens(projectIds: {'tac', 'gone'}, on: true);
      final trimmed = lens.restrictedTo(['tac', 'sample']);
      expect(trimmed.projectIds, {'tac'});
      expect(trimmed.active, isTrue);

      final stale = const HelmLens(projectIds: {'gone'}, on: true)
          .restrictedTo(['tac', 'sample']);
      expect(stale.active, isFalse, reason: 'Helm must never go blank');
      expect(stale.includes('sample'), isTrue);
    });

    test('equality ignores set order', () {
      expect(const HelmLens(projectIds: {'a', 'b'}, on: true),
          const HelmLens(projectIds: {'b', 'a'}, on: true));
      expect(const HelmLens(projectIds: {'a'}, on: true),
          isNot(const HelmLens(projectIds: {'a'}, on: false)));
    });

    test('label: all, one by name, else a count', () {
      final names = {'tac': 'TAC Integration', 'dt': 'Digital Toolkit'};
      expect(helmLensLabel(HelmLens.all, names), 'All projects');
      expect(helmLensLabel(const HelmLens(projectIds: {'tac'}, on: true), names),
          'TAC Integration');
      expect(helmLensLabel(const HelmLens(projectIds: {'tac', 'dt'}, on: true), names),
          '2 projects');
      expect(helmLensLabel(const HelmLens(projectIds: {'gone'}, on: true), names),
          'All projects');
    });
  });

  group('AppSettings lens', () {
    test('defaults to all projects and survives a JSON round trip', () {
      const s = AppSettings();
      expect(s.helmLens, HelmLens.all);

      final narrowed = s.copyWith(helmLensProjectIds: ['tac', 'dt'], helmLensOn: true);
      expect(narrowed.helmLens, const HelmLens(projectIds: {'tac', 'dt'}, on: true));

      final back = AppSettings.fromJson(narrowed.toJson());
      expect(back.helmLens, narrowed.helmLens);
      expect(back.helmLensProjectIds, ['tac', 'dt']);
    });

    test('old settings files without the keys read as all projects', () {
      final s = AppSettings.fromJson({'themeId': 'keel'});
      expect(s.helmLens.active, isFalse);
    });
  });
}
