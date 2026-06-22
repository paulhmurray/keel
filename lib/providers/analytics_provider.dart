import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/analytics/analytics_config.dart';
import '../core/analytics/analytics_service.dart';
import '../core/analytics/keel_events.dart';
import '../core/analytics/posthog_analytics_service.dart';
import 'settings_provider.dart';

/// Reactive bridge between [SettingsProvider] and [AnalyticsService].
///
/// Listens to settings changes and swaps the underlying analytics
/// implementation as the user toggles opt-in. Importantly, when the
/// user is opted out the sink is a [NoopAnalyticsService] — *not* a
/// "real" sink with a disabled flag. That means call sites can never
/// accidentally leak data through a half-configured pipeline: the only
/// way an event gets sent is if the active impl chooses to send it.
///
/// Phase A wires Noop ↔ Logging (debug mode only). Phase B will swap
/// the debug-and-opted-in branch for a real PostHog impl.
class AnalyticsProvider extends ChangeNotifier {
  final SettingsProvider _settings;
  AnalyticsService _service = const NoopAnalyticsService();
  bool _disposed = false;
  // Fires app_launched exactly once per provider lifecycle, on the
  // first transition into a non-Noop sink. Re-toggling opt-in within
  // the same launch doesn't fire it again — repeat events would
  // inflate session counts in the dashboard.
  bool _didFireLaunch = false;

  AnalyticsService get service => _service;

  AnalyticsProvider(this._settings) {
    _settings.addListener(_onSettingsChanged);
    // Initial sync — settings may already be loaded by the time we're
    // constructed (e.g. on a Settings UI rebuild).
    _onSettingsChanged();
  }

  /// Returns the live impl, rebuilding it if the opt-in state changed
  /// since the last call. Pure dispatch — does NOT fire any events.
  void _onSettingsChanged() {
    if (_disposed) return;
    final s = _settings.settings;
    final wantsEnabled = s.analyticsEnabled && s.analyticsInstallId != null;
    final next = _pickImpl(wantsEnabled);
    if (next.runtimeType == _service.runtimeType) return;
    // Flush whatever was on the previous sink so opt-out doesn't drop
    // events the user *did* consent to before flipping the switch.
    final previous = _service;
    previous.flush();
    _service = next;
    if (wantsEnabled) {
      _service.identify(s.analyticsInstallId!);
      if (!_didFireLaunch) {
        _didFireLaunch = true;
        _fireAppLaunched();
      }
    } else {
      // Switching to Noop: actively clear the previous impl so any
      // in-memory buffer is dropped immediately, not on next launch.
      previous.clear();
    }
    // Release any per-sink resources (e.g. PostHog's http.Client
    // connection pool) on the impl we're stepping away from.
    if (previous is PosthogAnalyticsService) previous.dispose();
    notifyListeners();
  }

  /// One-shot app_launched event with coarse runtime info. Failures here
  /// (PackageInfo unavailable in tests, etc.) are swallowed because
  /// analytics must never break the app.
  Future<void> _fireAppLaunched() async {
    String version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
    } catch (_) {
      // Leaves the default.
    }
    if (_disposed) return;
    await _service.track(
      KeelEvents.appLaunched,
      props: {
        KeelEventProps.version: version,
        KeelEventProps.platform: _platformTag(),
      },
    );
  }

  String _platformTag() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isLinux) return 'linux';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isWindows) return 'windows';
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {
      // Platform unavailable in some test environments.
    }
    return 'unknown';
  }

  /// Chooses the concrete impl for a given opt-in state. The priority
  /// order is:
  ///   1. opted out                 → Noop
  ///   2. opted in + PostHog key    → PosthogAnalyticsService
  ///   3. opted in + no key + debug → LoggingAnalyticsService
  ///   4. opted in + no key + rel.  → Noop (never silently break)
  ///
  /// A debug build with `--dart-define=POSTHOG_API_KEY=...` therefore
  /// sends real events while iterating; without the key it stays in
  /// the on-screen Logging preview.
  AnalyticsService _pickImpl(bool optedIn) {
    if (!optedIn) return const NoopAnalyticsService();
    if (AnalyticsConfig.hasPosthogKey) {
      return PosthogAnalyticsService(
        apiKey: AnalyticsConfig.posthogApiKey,
        host: AnalyticsConfig.posthogHost,
      );
    }
    if (kDebugMode) return LoggingAnalyticsService();
    return const NoopAnalyticsService();
  }

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    _service.flush();
    final s = _service;
    if (s is PosthogAnalyticsService) s.dispose();
    super.dispose();
  }
}
