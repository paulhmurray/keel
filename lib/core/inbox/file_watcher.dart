import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Watches a directory for changes to .org, .md, and .txt files.
///
/// When a watched file is created or modified, reads it and calls [onFileChanged]
/// with the file path and its content.
class FileWatcher {
  final String watchDirectory;
  final void Function(String path, String content) onFileChanged;

  StreamSubscription<FileSystemEvent>? _subscription;

  FileWatcher({
    required this.watchDirectory,
    required this.onFileChanged,
  });

  /// Starts watching [watchDirectory] recursively.
  ///
  /// Reacts to [FileSystemEvent.create] and [FileSystemEvent.modify] events
  /// for files with .org, .md, or .txt extensions.
  void start() {
    if (kIsWeb) return;
    final dir = Directory(watchDirectory);
    if (!dir.existsSync()) return;

    _subscription = dir
        .watch(events: FileSystemEvent.create | FileSystemEvent.modify, recursive: true)
        .listen(_handleEvent, onError: (_) {});
  }

  /// Stops watching the directory.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _handleEvent(FileSystemEvent event) {
    final path = event.path;
    final ext = path.toLowerCase();
    if (!ext.endsWith('.org') && !ext.endsWith('.md') && !ext.endsWith('.txt')) {
      return;
    }

    final file = File(path);
    if (!file.existsSync()) return;

    try {
      final content = file.readAsStringSync();
      onFileChanged(path, content);
    } catch (_) {
      // Ignore read errors (file may be locked mid-write)
    }
  }
}
