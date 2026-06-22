/// Build-time configuration for the analytics sink. Values are injected
/// via `--dart-define` so secrets and per-environment URLs are never
/// committed:
///
/// ```
/// flutter build linux \
///   --dart-define=POSTHOG_API_KEY=phc_xxx \
///   --dart-define=POSTHOG_HOST=https://eu.i.posthog.com
/// ```
///
/// A build with no [posthogApiKey] cannot reach PostHog. In that case
/// the AnalyticsProvider falls back to a Noop (release) or the
/// LoggingAnalyticsService (debug) so opt-in never silently breaks.
class AnalyticsConfig {
  AnalyticsConfig._();

  /// PostHog project API key. Public client-side identifier (NOT a
  /// personal API key) — fine to ship in the binary, but kept out of
  /// source so forks of the repo don't accidentally inherit it.
  static const String posthogApiKey =
      String.fromEnvironment('POSTHOG_API_KEY', defaultValue: '');

  /// Base URL of the PostHog ingestion endpoint. Defaults to the EU
  /// region. Self-hosted deployments override via --dart-define.
  static const String posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );

  /// Whether a real network sink is reachable in this build.
  static bool get hasPosthogKey => posthogApiKey.isNotEmpty;
}
