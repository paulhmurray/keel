import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_plan_detail.dart';

void main() {
  group('cascadeMonthOffset', () {
    test('re-keys onto the programme axis when both anchors are known', () {
      // Project month 0 = Jan 2026, activity at M3 (Apr 2026).
      // Programme month 0 = Oct 2025 → Apr 2026 is its M6 → offset +3.
      expect(
          cascadeMonthOffset(
            rawStartMonth: 3,
            startMonthDate: DateTime(2026, 4, 1),
            programmeAnchor: DateTime(2025, 10, 1),
          ),
          3);
      // Programme starts later than the project → negative offset.
      expect(
          cascadeMonthOffset(
            rawStartMonth: 3,
            startMonthDate: DateTime(2026, 4, 1),
            programmeAnchor: DateTime(2026, 3, 1),
          ),
          -2);
    });
    test('assumes aligned axes when either side has no anchor', () {
      expect(
          cascadeMonthOffset(
              rawStartMonth: 3, startMonthDate: null, programmeAnchor: DateTime(2026, 1, 1)),
          0);
      expect(
          cascadeMonthOffset(
              rawStartMonth: 3, startMonthDate: DateTime(2026, 4, 1), programmeAnchor: null),
          0);
      expect(
          cascadeMonthOffset(
              rawStartMonth: null, startMonthDate: DateTime(2026, 4, 1), programmeAnchor: DateTime(2026, 1, 1)),
          0);
    });
  });

  group('remapPlanLinkNote', () {
    test('re-keys RAID dependency and decision markers onto cascaded ids', () {
      expect(remapPlanLinkNote('projA', 'raid-dependency:d1'),
          'raid-dependency:cascade:dependency:projA:d1');
      expect(remapPlanLinkNote('projA', 'raid-decision:dc9'),
          'raid-decision:cascade:decision:projA:dc9');
    });
    test('leaves ordinary notes and nulls alone', () {
      expect(remapPlanLinkNote('projA', 'vendor lag'), 'vendor lag');
      expect(remapPlanLinkNote('projA', null), isNull);
    });
  });
}
