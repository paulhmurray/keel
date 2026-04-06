/// Stub FileWatcher for web — never actually started.
class FileWatcher {
  final String watchDirectory;
  final void Function(String path, String content) onFileChanged;

  FileWatcher({
    required this.watchDirectory,
    required this.onFileChanged,
  });

  void start() {}
  void stop() {}
}
