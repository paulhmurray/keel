import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '_watcher_service_io.dart' if (dart.library.html) '_watcher_service_web.dart';

import '../database/database.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import 'file_watcher.dart' if (dart.library.html) 'file_watcher_stub.dart';
import 'parsers/txt_parser.dart';
import 'parsers/md_parser.dart';
import 'parsers/org_parser.dart';

/// Manages the FileWatcher lifecycle and pipes file-change events into the
/// inbox for the currently selected project.
class WatcherService with ChangeNotifier {
  final AppDatabase _db;
  final SettingsProvider _settingsProvider;
  final ProjectProvider _projectProvider;

  FileWatcher? _watcher;
  bool _active = false;
  String _statusMessage = 'Not watching';

  bool get isActive => _active;
  String get statusMessage => _statusMessage;

  WatcherService(this._db, this._settingsProvider, this._projectProvider) {
    _settingsProvider.addListener(_onSettingsChanged);
    _projectProvider.addListener(_onSettingsChanged);
    // Apply initial settings once the settings provider has loaded
    _applySettings();
  }

  void _onSettingsChanged() => _applySettings();

  void _applySettings() {
    // File watcher is not supported on web
    if (kIsWeb) return;

    final s = _settingsProvider.settings;
    final shouldRun =
        s.watcherEnabled && s.watcherDirectory.isNotEmpty;

    if (shouldRun && !_active) {
      _start(s.watcherDirectory);
    } else if (!shouldRun && _active) {
      _stop();
    } else if (shouldRun && _active) {
      // Directory may have changed — restart
      final currentDir = _watcher?.watchDirectory;
      if (currentDir != s.watcherDirectory) {
        _stop();
        _start(s.watcherDirectory);
      }
    }
  }

  void _start(String directory) {
    if (!directoryExists(directory)) {
      _statusMessage = 'Directory not found: $directory';
      notifyListeners();
      return;
    }

    _watcher = FileWatcher(
      watchDirectory: directory,
      onFileChanged: _handleFile,
    );
    _watcher!.start();
    _active = true;
    _statusMessage = 'Watching: $directory';
    notifyListeners();
  }

  void _stop() {
    _watcher?.stop();
    _watcher = null;
    _active = false;
    _statusMessage = 'Not watching';
    notifyListeners();
  }

  void _handleFile(String path, String content) {
    final projectId = _projectProvider.currentProjectId;
    if (projectId == null) return;

    final ext = path.toLowerCase();
    final List<dynamic> drafts;
    final String sourceType;

    if (ext.endsWith('.org')) {
      drafts = OrgParser().parse(content);
      sourceType = 'org_file';
    } else if (ext.endsWith('.md')) {
      drafts = MdParser().parse(content);
      sourceType = 'md_file';
    } else if (ext.endsWith('.txt')) {
      drafts = TxtParser().parse(content);
      sourceType = 'txt_file';
    } else {
      return;
    }

    // Use both separators to handle any platform path format
    final sourceRef = path.replaceAll('\\', '/').split('/').last;

    for (final draft in drafts) {
      _db.inboxDao.insertInboxItem(
        InboxItemsCompanion.insert(
          id: const Uuid().v4(),
          projectId: projectId,
          content: draft.rawText,
          tags: Value(draft.parsedType),
          source: Value(sourceType),
          linkedItemId: Value(sourceRef),
          linkedItemType: Value(draft.toJsonString()),
        ),
      );
    }
  }

  @override
  void dispose() {
    _stop();
    _settingsProvider.removeListener(_onSettingsChanged);
    _projectProvider.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
