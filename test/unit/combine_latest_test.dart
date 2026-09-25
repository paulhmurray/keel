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
}
