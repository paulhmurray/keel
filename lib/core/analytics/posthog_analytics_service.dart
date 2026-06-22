import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'analytics_service.dart';

/// PostHog-backed analytics sink. POSTs each event to PostHog's
/// `/capture` ingestion endpoint as a fire-and-forget HTTP request.
/// Failures (offline, 5xx, malformed response) are swallowed because
/// analytics must never break the app.
///
/// Why a hand-rolled HTTP client instead of `posthog_flutter`:
///   - Plays nicely on Flutter desktop (Linux/macOS/Windows), where the
///     SDK's platform support is patchier.
///   - One file, no native bridges, trivially testable with a mock
///     [http.Client].
///   - Same code path works against PostHog Cloud (EU/US) or a
///     self-hosted instance — just point [host] at it.
class PosthogAnalyticsService implements AnalyticsService {
  /// Public project API key. Identifies the PostHog project; safe to
  /// ship in the binary because it's a client-side key.
  final String apiKey;

  /// Ingestion base URL, e.g. `https://eu.i.posthog.com`. Trailing
  /// slashes are tolerated.
  final String host;

  final http.Client _client;
  String? _distinctId;

  PosthogAnalyticsService({
    required this.apiKey,
    required this.host,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Uri get _captureUrl {
    final normalised =
        host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    return Uri.parse('$normalised/capture/');
  }

  @override
  Future<void> identify(String installId) async {
    _distinctId = installId;
  }

  @override
  Future<void> track(String name, {Map<String, Object?>? props}) async {
    final id = _distinctId;
    if (id == null) {
      // No identity yet — drop the event rather than emit a synthetic
      // anonymous one. The provider always calls identify() before
      // tracking, so this is a defensive check, not an expected path.
      return;
    }
    final body = <String, Object?>{
      'api_key': apiKey,
      'event': name,
      'distinct_id': id,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (props != null && props.isNotEmpty)
        'properties': _scrub(props),
    };
    unawaited(_send(body));
  }

  /// Strips null-valued props and converts non-scalar values to strings
  /// so the dashboard sees a clean, stable schema. PostHog tolerates
  /// nested objects but we explicitly don't ship them — every analytics
  /// payload should be flat and obvious from a dashboard glance.
  Map<String, Object> _scrub(Map<String, Object?> props) {
    final out = <String, Object>{};
    for (final entry in props.entries) {
      final v = entry.value;
      if (v == null) continue;
      if (v is num || v is bool || v is String) {
        out[entry.key] = v;
      } else {
        out[entry.key] = v.toString();
      }
    }
    return out;
  }

  Future<void> _send(Map<String, Object?> body) async {
    try {
      final res = await _client
          .post(
            _captureUrl,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode >= 400 && kDebugMode) {
        debugPrint(
            '[analytics] posthog rejected: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[analytics] posthog send failed: $e');
      }
    }
  }

  @override
  Future<void> flush() async {
    // No buffer — every track() POSTs immediately. The fire-and-forget
    // unawaited futures may still be in flight on dispose, but they
    // either complete in the background or get cancelled with the
    // process; no user-visible event survives.
  }

  @override
  Future<void> clear() async {
    _distinctId = null;
  }

  /// Closes the underlying HTTP client. Call this when the service is
  /// being torn down (e.g. provider dispose) so its connection pool
  /// releases.
  void dispose() {
    _client.close();
  }
}
