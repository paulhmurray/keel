import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/shell/landing.dart';

void main() {
  test('a project lands on Helm, a programme on its overview', () {
    expect(landingIndexFor(isProgramme: false), kNavHelm);
    expect(landingIndexFor(isProgramme: true), kNavOverview);
  });
  test('only the two home pages follow a project switch', () {
    expect(isHomePage(kNavHelm), isTrue);
    expect(isHomePage(kNavOverview), isTrue);
    expect(isHomePage(2), isFalse); // RAID stays put
  });
}
