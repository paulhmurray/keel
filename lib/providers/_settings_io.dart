import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'settings_provider.dart';

Future<File> _settingsFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'keel_settings.json'));
}

Future<AppSettings> loadSettingsFromFile() async {
  final file = await _settingsFile();
  if (await file.exists()) {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return AppSettings.fromJson(json);
  }
  return const AppSettings();
}

Future<void> saveSettingsToFile(Map<String, dynamic> json) async {
  final file = await _settingsFile();
  await file.writeAsString(jsonEncode(json));
}
