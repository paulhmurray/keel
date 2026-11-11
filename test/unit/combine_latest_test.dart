import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/helm/combine_latest.dart';

void main() {
  test('emits once every source has a value, then on every change', () async {
    final a = StreamController<int>();
    final b = StreamController<int>();
    final out = <List<int>>[];
    final sub = combineLatest([a.stream, b.stream]).listen(out.add);

    a.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(out, isEmpty); // b hasn't spoken yet
    b.add(10);
    await Future<void>.delayed(Duration.zero);
    expect(out, [[1, 10]]);
    a.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(out, [[1, 10], [2, 10]]);

    await sub.cancel();
    expect(a.hasListener, isFalse);
    expect(b.hasListener, isFalse);
    await a.close();
    await b.close();
  });

  test('empty input emits a single empty list', () async {
    expect(await combineLatest<int>(const []).first, isEmpty);
  });

  group('shareReplay', () {
    test('a late listener gets the latest value at once', () async {
      final source = StreamController<int>.broadcast();
      final shared = shareReplay(source.stream);
      final first = <int>[];
      final s1 = shared.listen(first.add);
      source.add(1);
      source.add(2);
      await Future<void>.delayed(Duration.zero);

      final late = <int>[];
      final s2 = shared.listen(late.add);
      await Future<void>.delayed(Duration.zero);
      expect(late, [2], reason: 'replayed the latest, not the history');

      source.add(3);
      await Future<void>.delayed(Duration.zero);
      expect(first, [1, 2, 3]);
      expect(late, [2, 3]);
      await s1.cancel();
      await s2.cancel();
    });

    test('one upstream subscription, released when the last listener leaves',
        () async {
      var listens = 0;
      final source = StreamController<int>.broadcast(onListen: () => listens++);
      final shared = shareReplay(source.stream);
      final s1 = shared.listen((_) {});
      final s2 = shared.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(listens, 1);
      await s1.cancel();
      await s2.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(source.hasListener, isFalse);

      // A fresh listener starts clean: no stale replay.
      final fresh = <int>[];
      final s3 = shared.listen(fresh.add);
      await Future<void>.delayed(Duration.zero);
      expect(fresh, isEmpty);
      await s3.cancel();
    });
  });
}
