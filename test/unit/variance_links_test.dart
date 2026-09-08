import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/plan/variance_links.dart';

void main() {
  test('encode/parse round-trips and skips malformed entries', () {
    final json = encodeVarianceLinks([
      (type: 'risk', id: 'r1'),
      (type: 'assumption', id: 'a1'),
    ]);
    expect(parseVarianceLinks(json), [
      (type: 'risk', id: 'r1'),
      (type: 'assumption', id: 'a1'),
    ]);
    expect(parseVarianceLinks('not json'), isEmpty);
    expect(parseVarianceLinks('[{"type":1,"id":"x"}]'), isEmpty);
    expect(parseVarianceLinks(null), isEmpty);
  });

  test('encoding caps at $kMaxVarianceLinks links', () {
    final json = encodeVarianceLinks([
      for (var i = 0; i < 9; i++) (type: 'risk', id: 'r$i'),
    ]);
    expect(parseVarianceLinks(json).length, kMaxVarianceLinks);
  });

  test('effective links prefer the JSON list, fall back to the legacy '
      'single-link columns', () {
    expect(
      effectiveVarianceLinks(
        linksJson: encodeVarianceLinks([(type: 'issue', id: 'i1')]),
        legacyType: 'risk',
        legacyId: 'r-old',
      ),
      [(type: 'issue', id: 'i1')],
    );
    expect(
      effectiveVarianceLinks(
          linksJson: null, legacyType: 'risk', legacyId: 'r-old'),
      [(type: 'risk', id: 'r-old')],
    );
    expect(
      effectiveVarianceLinks(
          linksJson: null, legacyType: null, legacyId: null),
      isEmpty,
    );
  });
}
