import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/analytics/analytics_service.dart';
import 'package:keel/core/analytics/keel_events.dart';
import 'package:keel/providers/analytics_provider.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// Bare-bones SettingsProvider double that lets us flip opt-in without
/// touching disk. Mirrors the one used by analytics_provider_test.
class _FakeSettings extends ChangeNotifier implements SettingsProvider {
  AppSettings _s = const AppSettings();

  @override
  AppSettings get settings => _s;

  void set(AppSettings next) {
    _s = next;
    notifyListeners();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'context.analytics is a Noop when no AnalyticsProvider is in scope '
      '(so non-analytics widget tests do not need to mount one)',
      (tester) async {
    AnalyticsService? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            captured = ctx.analytics;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured, isA<NoopAnalyticsService>());
  });

  testWidgets(
      'context.analytics.track records into the active sink while the '
      'user is opted in (debug-mode LoggingAnalyticsService)',
      (tester) async {
    final settings = _FakeSettings();
    settings.set(const AppSettings(
      analyticsEnabled: true,
      analyticsInstallId: 'inst-w',
    ));

    LoggingAnalyticsService? sink;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<AnalyticsProvider>(
            create: (ctx) =>
                AnalyticsProvider(ctx.read<SettingsProvider>()),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) {
              // Capture the live sink and emit one event.
              sink = ctx.read<AnalyticsProvider>().service
                  as LoggingAnalyticsService;
              ctx.analytics.track(
                KeelEvents.cardCreated,
                props: {KeelEventProps.source: 'widget_test'},
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    // Allow the provider's async app_launched fire + our synchronous
    // track to land in the sink.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sink, isNotNull);
    final names = sink!.history.map((e) => e.name).toList();
    expect(names, contains(KeelEvents.cardCreated));
  });
}
