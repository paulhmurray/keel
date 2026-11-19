import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


Future<File> _settingsFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'keel_settings.json'));
}

/// The raw settings JSON from disk, or null when there is no file yet.
/// Raw (not an [AppSettings]) so secrets can be merged in from the
/// keyring before parsing.
Future<Map<String, dynamic>?> loadSettingsJsonFromFile() async {
  final file = await _settingsFile();
  if (await file.exists()) {
    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }
  return null;
}

Future<void> saveSettingsToFile(Map<String, dynamic> json) async {
  final file = await _settingsFile();
  await file.writeAsString(jsonEncode(json));
}
