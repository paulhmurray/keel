import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

/// Web implementation: triggers a browser download via file_saver.
Future<String> saveAndOpenWeb(
    String filename, Uint8List bytes, String mimeType) async {
  // Strip extension for the name param (file_saver adds it back)
  final dotIdx = filename.lastIndexOf('.');
  final name = dotIdx >= 0 ? filename.substring(0, dotIdx) : filename;
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    mimeType: MimeType.other,
  );
  return 'Downloaded: $filename';
}

/// Not called on web — stub to satisfy import.
Future<String> saveTextAndOpenNative(String filename, String content) async {
  throw UnsupportedError('saveTextAndOpenNative not available on web');
}

/// Not called on web — stub to satisfy import.
Future<String> saveAndOpenNative(String filename, List<int> bytes) async {
  throw UnsupportedError('saveAndOpenNative not available on web');
}
