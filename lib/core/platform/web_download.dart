import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

// On web: use file_saver to trigger a browser download.
// On native: write to downloads dir and open the directory.
// All public functions return a user-friendly message string.

// Conditional imports so dart:io is never referenced on web.
import '_web_download_web.dart' if (dart.library.io) '_web_download_io.dart';

/// Saves [bytes] as a file named [filename].
///
/// On web, triggers a browser download. On native, writes to the downloads
/// directory and opens it in the file manager.
///
/// Returns a user-friendly result message.
Future<String> saveAndOpen(
  String filename,
  List<int> bytes, {
  String mimeType = 'application/octet-stream',
}) async {
  if (kIsWeb) {
    return saveAndOpenWeb(filename, Uint8List.fromList(bytes), mimeType);
  }
  return saveAndOpenNative(filename, bytes);
}

/// Saves [content] (UTF-8 text) as a file named [filename].
///
/// On web, triggers a browser download. On native, writes to the downloads
/// directory and opens it in the file manager.
///
/// Returns a user-friendly result message.
Future<String> saveTextAndOpen(String filename, String content) async {
  if (kIsWeb) {
    return saveAndOpenWeb(
        filename, Uint8List.fromList(utf8.encode(content)), 'text/plain');
  }
  return saveTextAndOpenNative(filename, content);
}
