import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keel/core/analytics/posthog_analytics_service.dart';

void main() {
  group('PosthogAnalyticsService', () {
    test(
        'track POSTs to <host>/capture/ with api_key, event, distinct_id, '
        'properties, and a timestamp', () async {
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('1', 200);
      });
      final sink = PosthogAnalyticsService(
        apiKey: 'phc_test',
        host: 'https://eu.i.posthog.com',
        client: client,
      );

      await sink.identify('install-abc');
      await sink.track(
        'card_created',
        props: {'source': 'new_button', 'count': 3},
      );
      // Fire-and-forget — wait a tick for the POST to land.
      await Future<void>.delayed(Duration.zero);

      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(
        captured!.url.toString(),
        'https://eu.i.posthog.com/capture/',
      );
      expect(captured!.headers['Content-Type'], 'application/json');

      final body =
          jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['api_key'], 'phc_test');
      expect(body['event'], 'card_created');
      expect(body['distinct_id'], 'install-abc');
      expect(body['properties'], {'source': 'new_button', 'count': 3});
      expect(body['timestamp'], isA<String>());
      // ISO-8601 in UTC.
      expect((body['timestamp'] as String).endsWith('Z'), isTrue);
    });

    test(
        'a track() before identify() is dropped — never emits an '
        'anonymous event', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('1', 200);
      });
      final sink = PosthogAnalyticsService(
        apiKey: 'phc_test',
        host: 'https://eu.i.posthog.com',
        client: client,
      );
      await sink.track('orphan.event');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    });

    test('host with trailing slash normalises to /capture/', () async {
      String? capturedUrl;
      final client = MockClient((req) async {
        capturedUrl = req.url.toString();
        return http.Response('1', 200);
      });
      final sink = PosthogAnalyticsService(
        apiKey: 'k',
        host: 'https://self-hosted.example.com/',
        client: client,
      );
      await sink.identify('id');
      await sink.track('e');
      await Future<void>.delayed(Duration.zero);
      expect(capturedUrl, 'https://self-hosted.example.com/capture/');
    });

    test('omits properties key when props is empty/null', () async {
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('1', 200);
      });
      final sink = PosthogAnalyticsService(
        apiKey: 'k',
        host: 'https://eu.i.posthog.com',
        client: client,
      );
      await sink.identify('id');
      await sink.track('app_launched');
      await Future<void>.delayed(Duration.zero);
      expect(body!.containsKey('properties'), isFalse);
    });

    test('null-valued props are scrubbed from the payload', () async {
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('1', 200);
      });
      final sink = PosthogAnalyticsService(
        apiKey: 'k',
        host: 'https://eu.i.posthog.com',
        client: client,
      );
      await sink.identify('id');
      await sink.track('e', props: {'keep': 'yes', 'drop': null});
      await Future<void>.delayed(Duration.zero);
      expect(body!['properties'], {'keep': 'yes'});
    });

    test('network failures never throw out of track()', () async {
      final client = MockClient((_) async => throw Exception('offline'));
      final sink = PosthogAnalyticsService(
        apiKey: 'k',
        host: 'https://eu.i.posthog.com',
        client: client,
      );
      await sink.identify('id');
      // Must NOT throw — analytics failures cannot break the app.
      await sink.track('e');
      await Future<void>.delayed(Duration.zero);
    });

    test('HTTP 4xx/5xx responses never throw out of track()', () async {
      final client = MockClient(
          (_) async => http.Response('rate-limited', 429));
      final sink = PosthogAnalyticsService(
        apiKey: 'k',
        host: 'https://eu.i.posthog.com',
        client: client,
      );
      await sink.identify('id');
      await sink.track('e');
      await Future<void>.delayed(Duration.zero);
    });

    test('clear() drops the identity so subsequent tracks are no-ops',
        () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('1', 200);
      });
      final sink = PosthogAnalyticsService(
        apiKey: 'k',
        host: 'https://eu.i.posthog.com',
        client: client,
      );
      await sink.identify('id');
      await sink.clear();
      await sink.track('after_clear');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    });
  });
}
