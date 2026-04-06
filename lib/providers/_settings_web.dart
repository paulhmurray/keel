import 'settings_provider.dart';

// Web stub — actual web storage is handled via shared_preferences in
// SettingsProvider._load() and .save() using the kIsWeb guard.
// These functions are never called on web.

Future<AppSettings> loadSettingsFromFile() async {
  return const AppSettings();
}

Future<void> saveSettingsToFile(Map<String, dynamic> json) async {
  // No-op on web — handled by shared_preferences in SettingsProvider
}
