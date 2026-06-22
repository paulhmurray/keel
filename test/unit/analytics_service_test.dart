import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/analytics/analytics_service.dart';

void main() {
  group('NoopAnalyticsService', () {
    test('every method is a no-op and never throws', () async {
      const sink = NoopAnalyticsService();
      // None of these should throw. There's no observable side effect
      // by design — that's the point of Noop.
      await sink.identify('any-id');
      await sink.track('any.event');
      await sink.track('with.props', props: {'k': 'v', 'n': 1});
      await sink.flush();
      await sink.clear();
    });
  });

  group('LoggingAnalyticsService', () {
    test('records events in history with name + props', () async {
      final sink = LoggingAnalyticsService();
      await sink.identify('install-1');
      await sink.track('app.launched', props: {'version': '1.0.0'});
      await sink.track('canvas.opened');

      expect(sink.history, hasLength(2));
      expect(sink.history[0].name, 'app.launched');
      expect(sink.history[0].props, {'version': '1.0.0'});
      expect(sink.history[1].name, 'canvas.opened');
      expect(sink.history[1].props, isEmpty);
    });

    test('clear() empties history and drops identity', () async {
      final sink = LoggingAnalyticsService();
      await sink.identify('install-2');
      await sink.track('a');
      await sink.track('b');
      await sink.clear();
      expect(sink.history, isEmpty);
      // Identity is dropped — subsequent events still record without
      // an install ID; LoggingAnalyticsService doesn't refuse to log
      // post-clear because it's purely a debug aid.
      await sink.track('c');
      expect(sink.history.single.name, 'c');
    });
  });

  group('AnalyticsService.bucketCount', () {
    test('small counts pass through as-is', () {
      expect(AnalyticsService.bucketCount(0), '0');
      expect(AnalyticsService.bucketCount(3), '3');
      expect(AnalyticsService.bucketCount(9), '9');
    });

    test('crosses into the first bucket at the threshold', () {
      // Threshold is 10 (largeCountBucketThreshold).
      expect(AnalyticsService.bucketCount(10), '10-49');
      expect(AnalyticsService.bucketCount(47), '10-49');
      expect(AnalyticsService.bucketCount(49), '10-49');
    });

    test('walks through every bucket label', () {
      expect(AnalyticsService.bucketCount(50), '50-99');
      expect(AnalyticsService.bucketCount(99), '50-99');
      expect(AnalyticsService.bucketCount(100), '100-499');
      expect(AnalyticsService.bucketCount(499), '100-499');
      expect(AnalyticsService.bucketCount(500), '500+');
      expect(AnalyticsService.bucketCount(10000), '500+');
    });
  });
}
