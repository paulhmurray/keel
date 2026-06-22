import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/analytics/analytics_config.dart';
import 'package:keel/core/analytics/analytics_service.dart';
import 'package:keel/core/analytics/posthog_analytics_service.dart';
import 'package:keel/providers/analytics_provider.dart';
import 'package:keel/providers/settings_provider.dart';

/// Minimal SettingsProvider double that lets tests drive opt-in state
/// without touching disk. The real SettingsProvider loads settings
/// asynchronously from a file in its constructor — unsuitable for a
/// fast unit test of the bridging logic.
class _FakeSettings extends ChangeNotifier implements SettingsProvider {
  AppSettings _s = const AppSettings();

  @override
  AppSettings get settings => _s;

  void set(AppSettings next) {
    _s = next;
    notifyListeners();
  }

  // We only exercise the listener bridge — every other method is
  // unreachable in this test scope.
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AnalyticsProvider impl selection', () {
    test('starts as Noop when settings are opted out (default)', () {
      final settings = _FakeSettings();
      final analytics = AnalyticsProvider(settings);
      expect(analytics.service, isA<NoopAnalyticsService>());
      analytics.dispose();
    });

    test(
        'flipping opt-in WITHOUT an install ID stays on Noop '
        '(safety: identifier must exist before any tracker spins up)',
        () {
      final settings = _FakeSettings();
      final analytics = AnalyticsProvider(settings);
      settings.set(const AppSettings(analyticsEnabled: true));
      expect(analytics.service, isA<NoopAnalyticsService>());
      analytics.dispose();
    });

    test(
        'opting in WITH an install ID swaps to a non-Noop sink '
        '(LoggingAnalyticsService in debug; Noop in release fallback)',
        () {
      final settings = _FakeSettings();
      final analytics = AnalyticsProvider(settings);
      settings.set(const AppSettings(
        analyticsEnabled: true,
        analyticsInstallId: 'inst-1',
      ));
      if (kDebugMode) {
        expect(analytics.service, isA<LoggingAnalyticsService>());
      } else {
        // Release builds with no real network sink wired up yet (Phase
        // A) intentionally fall back to Noop so opt-in never silently
        // ships a half-built pipeline.
        expect(analytics.service, isA<NoopAnalyticsService>());
      }
      analytics.dispose();
    });

    test(
        'opting in with a configured PostHog key picks the PostHog sink '
        '(regardless of debug/release)', () async {
      // This test is meaningful only when the build has a POSTHOG_API_KEY
      // injected via --dart-define. In a default `flutter test` run the
      // key is empty, so the branch we want to exercise isn't reachable
      // and we skip — the no-key branches are covered by the other
      // tests in this group.
      if (!AnalyticsConfig.hasPosthogKey) return;
      final settings = _FakeSettings();
      final analytics = AnalyticsProvider(settings);
      settings.set(const AppSettings(
        analyticsEnabled: true,
        analyticsInstallId: 'inst-posthog',
      ));
      expect(analytics.service, isA<PosthogAnalyticsService>());
      analytics.dispose();
    });

    test('opting back out swaps back to Noop and clears the previous sink',
        () async {
      if (!kDebugMode) return; // Behaviour is meaningful only in debug.
      final settings = _FakeSettings();
      final analytics = AnalyticsProvider(settings);
      settings.set(const AppSettings(
        analyticsEnabled: true,
        analyticsInstallId: 'inst-1',
      ));
      final logging = analytics.service as LoggingAnalyticsService;
      // Flush any pending async work (the provider fires app_launched
      // asynchronously after the impl swap — wait for that to land
      // before continuing so the test isn't racing).
      await Future<void>.delayed(Duration.zero);
      await logging.track('something.happened');
      // Expect at least the app_launched fire + our manual track —
      // exact count depends on whether app_launched completed by now.
      expect(logging.history, isNotEmpty);

      settings.set(const AppSettings(analyticsInstallId: 'inst-1'));
      // Wait a tick for the async clear to land.
      await Future<void>.delayed(Duration.zero);
      expect(analytics.service, isA<NoopAnalyticsService>());
      // Previous Logging impl had its history wiped by clear() so an
      // accidentally-retained reference can't be used to exfiltrate
      // events captured while opted in.
      expect(logging.history, isEmpty);

      analytics.dispose();
    });
  });
}
