// Web stub — actual web storage is handled via shared_preferences in
// SettingsProvider._load() and .save() using the kIsWeb guard.
// These functions are never called on web.

Future<Map<String, dynamic>?> loadSettingsJsonFromFile() async => null;

Future<void> saveSettingsToFile(Map<String, dynamic> json) async {
  // No-op on web — handled by shared_preferences in SettingsProvider
}
