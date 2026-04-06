import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Not called on native — stub to satisfy import.
Future<String> saveAndOpenWeb(
    String filename, Uint8List bytes, String mimeType) async {
  throw UnsupportedError('saveAndOpenWeb not available on native');
}

/// Writes [content] to the downloads directory and opens the directory.
Future<String> saveTextAndOpenNative(String filename, String content) async {
  final dir =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, filename);
  await File(path).writeAsString(content);
  _openDir(dir.path);
  return path;
}

/// Writes [bytes] to the downloads directory and opens the directory.
Future<String> saveAndOpenNative(String filename, List<int> bytes) async {
  final dir =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, filename);
  await File(path).writeAsBytes(bytes);
  _openDir(dir.path);
  return path;
}

void _openDir(String path) {
  if (Platform.isLinux) {
    Process.run('xdg-open', [path]);
  } else if (Platform.isMacOS) {
    Process.run('open', [path]);
  } else if (Platform.isWindows) {
    Process.run('explorer', [path]);
  }
}
