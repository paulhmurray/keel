import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/database/database.dart';
import 'core/inbox/watcher_service.dart';
import 'core/update/self_updater.dart';
import 'providers/analytics_provider.dart';
import 'providers/project_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/update_provider.dart';
import 'shared/theme/keel_colors.dart';
import 'shared/theme/keel_theme.dart';
import 'shared/widgets/update_banner.dart';
import 'features/shell/shell_layout.dart';

class KeelApp extends StatefulWidget {
  const KeelApp({super.key});

  @override
  State<KeelApp> createState() => _KeelAppState();
}

class _KeelAppState extends State<KeelApp> {
  late final AppDatabase _database;

  @override
  void initState() {
    super.initState();
    _database = AppDatabase();
    // An in-app update parks the previous install beside the new one;
    // clear it now that the new version is running.
    if (!kIsWeb) {
      final exe = Platform.resolvedExecutable;
      // On a Mac the parked copy sits beside the .app bundle, not beside
      // the binary inside it.
      final root = Platform.isMacOS
          ? (macBundlePath(exe) ?? installRootFor(exe))
          : installRootFor(exe);
      sweepOldInstalls(Directory(root));
    }
  }

  @override
  void dispose() {
    _database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Database singleton
        Provider<AppDatabase>.value(value: _database),

        // Settings
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),

        // Analytics — listens to Settings and swaps Noop ↔ real impl
        // when the user toggles opt-in. Noop by default.
        ChangeNotifierProvider<AnalyticsProvider>(
          create: (ctx) => AnalyticsProvider(ctx.read<SettingsProvider>()),
        ),

        // Project state — depends on database
        ChangeNotifierProvider<ProjectProvider>(
          create: (ctx) => ProjectProvider(ctx.read<AppDatabase>()),
        ),

        // Sync — depends on settings (for persisted sync prefs)
        ChangeNotifierProxyProvider<SettingsProvider, SyncProvider>(
          create: (ctx) {
            final s = ctx.read<SettingsProvider>().settings;
            final sp = SyncProvider();
            sp.serverUrl = s.syncServerUrl;
            sp.syncEnabled = s.syncEnabled;
            sp.email = s.syncEmail.isEmpty ? null : s.syncEmail;
            sp.loadTimestamps();
            sp.tryRestoreSession();
            return sp;
          },
          update: (ctx, settings, previous) {
            final sp = previous ?? SyncProvider();
            // Only update persisted prefs; do not disturb in-memory auth state
            sp.serverUrl = settings.settings.syncServerUrl;
            sp.syncEnabled = settings.settings.syncEnabled;
            if (!sp.isAuthenticated) {
              sp.email = settings.settings.syncEmail.isEmpty
                  ? null
                  : settings.settings.syncEmail;
            }
            return sp;
          },
        ),

        // Update checker — runs on launch, rechecks every 4 hours
        ChangeNotifierProvider<UpdateProvider>(
          create: (_) => UpdateProvider()..start(),
        ),

        // File watcher — depends on db, settings, and project
        ChangeNotifierProxyProvider2<
          SettingsProvider,
          ProjectProvider,
          WatcherService
        >(
          create: (ctx) => WatcherService(
            ctx.read<AppDatabase>(),
            ctx.read<SettingsProvider>(),
            ctx.read<ProjectProvider>(),
          ),
          update: (ctx, settings, project, previous) =>
              previous ??
              WatcherService(ctx.read<AppDatabase>(), settings, project),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          // The palette is read through KColors everywhere, so apply it
          // before building and key the app on it: a new key rebuilds
          // every widget, which a ThemeData change alone would not.
          final palette = paletteById(settingsProvider.settings.themeId);
          KColors.apply(palette);
          // Settings load from disk a moment after the first frame. Hold
          // a blank page until then so the saved theme is what the user
          // sees first, not a flash of the default palette.
          if (!settingsProvider.isLoaded) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(backgroundColor: KColors.bg),
            );
          }
          return MaterialApp(
            key: ValueKey('theme-${palette.id}'),
            title: 'Keel',
            theme: keelThemeFor(palette),
            debugShowCheckedModeBanner: false,
            home: Builder(
              builder: (context) {
                final scale = settingsProvider.settings.uiScale;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth / scale;
                    final h = constraints.maxHeight / scale;
                    final mq = MediaQuery.of(context);
                    return FittedBox(
                      fit: BoxFit.fill,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: MediaQuery(
                          data: mq.copyWith(size: Size(w, h)),
                          child: const UpdateOverlay(child: ShellLayout()),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
