import 'package:flutter/foundation.dart';

/// Abstract analytics sink. Phase A ships the abstraction + a no-op +
/// debug-logging impl; Phase B will add a real network impl (PostHog or
/// equivalent) behind the same interface so the rest of the app never
/// imports a vendor SDK directly.
///
/// All callers route through this interface, which means:
///   - When the user is opted out, every method is a guaranteed no-op
///     (no buffering, no IDs generated, no network).
///   - Swapping vendors later is one file change.
///   - Tests can inject a fake impl.
///
/// **Event payload rules — enforced by callers, not the interface:**
///   - No user-authored content (titles, body text, names, project names).
///   - No file paths.
///   - Counts must be bucketed once they exceed [largeCountBucketThreshold]
///     so a "47-card user" isn't re-identifiable.
///   - Property keys use snake_case (matches PostHog convention).
abstract class AnalyticsService {
  /// Above this raw count, callers should pass a bucketed value via
  /// [bucketCount] (e.g. 47 → "10-49"). Numbers smaller than this can
  /// be sent exactly — they don't carry re-identification risk.
  static const int largeCountBucketThreshold = 10;

  /// Attaches the anonymous install ID to subsequent events. Called once
  /// after opt-in (when the install ID is first generated) and on every
  /// app launch while analytics is enabled.
  Future<void> identify(String installId);

  /// Records a single product event. [name] is a stable snake_case event
  /// name; [props] is an optional map of scalar metadata.
  ///
  /// Implementations MUST tolerate being called from background threads
  /// and MUST NOT throw — analytics failures should never break the app.
  Future<void> track(String name, {Map<String, Object?>? props});

  /// Force any buffered events to be sent. Called on app pause / before
  /// the AnalyticsProvider switches to a Noop impl on opt-out, so the
  /// last opt-in session isn't lost.
  Future<void> flush();

  /// Drop the in-memory install ID + any buffered events. Called when
  /// the user toggles analytics off OR taps "Clear" in Settings.
  Future<void> clear();

  /// Buckets a raw count so user identifiability stays low even when the
  /// caller doesn't know the threshold rule offhand. Returns the original
  /// number as a string for small counts, or a bucket label for larger
  /// ones ("10-49", "50-99", "100-499", "500+"). Pure utility — no I/O.
  static String bucketCount(int n) {
    if (n < largeCountBucketThreshold) return n.toString();
    if (n < 50) return '10-49';
    if (n < 100) return '50-99';
    if (n < 500) return '100-499';
    return '500+';
  }
}

/// Analytics sink for users who are opted out (the default). Every call
/// is a guaranteed no-op — no IDs generated, no buffering, no I/O. Used
/// whenever [SettingsProvider.settings.analyticsEnabled] is false.
class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  Future<void> identify(String installId) async {}

  @override
  Future<void> track(String name, {Map<String, Object?>? props}) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> clear() async {}
}

/// Dev-mode analytics sink — prints events to the debug console with a
/// distinctive prefix and never leaves the device. Useful for iterating
/// on the event schema before any network sink is wired up. Also doubles
/// as a sanity sink in widget tests (assertions can spy on its history
/// via the [history] getter).
class LoggingAnalyticsService implements AnalyticsService {
  final List<LoggedEvent> _history = [];
  String? _installId;

  /// Read-only event history. Tests can use this to assert that an
  /// expected event fired; production code should never read this.
  List<LoggedEvent> get history => List.unmodifiable(_history);

  @override
  Future<void> identify(String installId) async {
    _installId = installId;
    debugPrint('[analytics] identify install=$installId');
  }

  @override
  Future<void> track(String name, {Map<String, Object?>? props}) async {
    final entry = LoggedEvent(name: name, props: props ?? const {});
    _history.add(entry);
    final propsStr = props == null || props.isEmpty ? '' : ' $props';
    debugPrint('[analytics] track $name$propsStr (install=$_installId)');
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> clear() async {
    _installId = null;
    _history.clear();
    debugPrint('[analytics] cleared');
  }
}

/// A single event captured by [LoggingAnalyticsService]. Pure value type
/// so tests can pattern-match on the name + props pair.
class LoggedEvent {
  final String name;
  final Map<String, Object?> props;

  const LoggedEvent({required this.name, required this.props});

  @override
  String toString() => 'LoggedEvent($name, $props)';
}
