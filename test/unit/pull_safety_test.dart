import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/sync/pull_safety.dart';

void main() {
  final t0 = DateTime(2026, 7, 1, 10);
  final t1 = DateTime(2026, 7, 1, 11);
  final t2 = DateTime(2026, 7, 1, 12);

  group('hasUnpushedChanges', () {
    test('no local change ever → clean', () {
      expect(hasUnpushedChanges(null, null), isFalse);
      expect(hasUnpushedChanges(null, t0), isFalse);
    });
    test('changed but never synced → dirty', () {
      expect(hasUnpushedChanges(t0, null), isTrue);
    });
    test('changed after last sync → dirty', () {
      expect(hasUnpushedChanges(t1, t0), isTrue);
    });
    test('changed before (or at) last sync → clean', () {
      expect(hasUnpushedChanges(t0, t1), isFalse);
      expect(hasUnpushedChanges(t0, t0), isFalse);
    });
  });

  group('resolvePullSafety', () {
    test('clean local always imports — nothing to lose', () {
      // Never seen before (new machine pull-all flow).
      expect(
        resolvePullSafety(
            lastLocalChange: null, lastSync: null, serverUpdatedAt: t2),
        PullSafety.importClean,
      );
      // Synced and untouched since.
      expect(
        resolvePullSafety(
            lastLocalChange: t0, lastSync: t1, serverUpdatedAt: t2),
        PullSafety.importClean,
      );
    });

    test('dirty local, server unchanged since our sync → keep local, push',
        () {
      expect(
        resolvePullSafety(
            lastLocalChange: t2, lastSync: t1, serverUpdatedAt: t1),
        PullSafety.keepLocalAndPush,
      );
      // Server blob even older than our last sync (shouldn't happen, but
      // must not clobber local).
      expect(
        resolvePullSafety(
            lastLocalChange: t2, lastSync: t1, serverUpdatedAt: t0),
        PullSafety.keepLocalAndPush,
      );
    });

    test('dirty local, server moved since our sync → conflict', () {
      expect(
        resolvePullSafety(
            lastLocalChange: t1, lastSync: t0, serverUpdatedAt: t2),
        PullSafety.conflict,
      );
    });

    test('dirty local, never synced from this machine → conflict', () {
      // We can't prove the server blob is ours — snapshot before import.
      expect(
        resolvePullSafety(
            lastLocalChange: t1, lastSync: null, serverUpdatedAt: t0),
        PullSafety.conflict,
      );
    });
  });
}
