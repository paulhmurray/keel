import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/database/database.dart';
import 'core/inbox/watcher_service.dart';
import 'providers/analytics_provider.dart';
import 'providers/project_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/update_provider.dart';
import 'shared/theme/keel_theme.dart';
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
          create: (ctx) =>
              AnalyticsProvider(ctx.read<SettingsProvider>()),
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
        ChangeNotifierProxyProvider2<SettingsProvider, ProjectProvider, WatcherService>(
          create: (ctx) => WatcherService(
            ctx.read<AppDatabase>(),
            ctx.read<SettingsProvider>(),
            ctx.read<ProjectProvider>(),
          ),
          update: (ctx, settings, project, previous) =>
              previous ?? WatcherService(
                ctx.read<AppDatabase>(),
                settings,
                project,
              ),
        ),
      ],
      child: MaterialApp(
        title: 'Keel',
        theme: keelTheme,
        debugShowCheckedModeBanner: false,
        home: Consumer<SettingsProvider>(
          builder: (context, settingsProvider, _) {
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
                      child: const ShellLayout(),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
