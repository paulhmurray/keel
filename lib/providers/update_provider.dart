import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/update/self_updater.dart';
import '../core/update/update_service.dart';

class UpdateProvider extends ChangeNotifier {
  final UpdateService _service = UpdateService();
  final SelfUpdater _updater = SelfUpdater();

  UpdateInfo? _updateInfo;
  Timer? _timer;
  UpdateProgress _progress = UpdateProgress.idle;
  String? _lastError;

  UpdateInfo? get updateInfo => _updateInfo;
  UpdateProgress get progress => _progress;
  String? get lastError => _lastError;
  bool get installing => _progress.busy;

  void start() {
    _check();
    _timer = Timer.periodic(const Duration(hours: 4), (_) => _check());
  }

  Future<void> _check() async {
    final info = await _service.checkForUpdate();
    if (info?.version != _updateInfo?.version) {
      _updateInfo = info;
      notifyListeners();
    }
  }

  void dismiss() {
    _updateInfo = null;
    notifyListeners();
  }

  /// Downloads and installs [version] in place. The app greys out while
  /// this runs and relaunches itself at the end; on failure the error is
  /// kept for the UI and the app stays usable.
  Future<void> install(String version) async {
    if (installing) return;
    _lastError = null;
    _progress = const UpdateProgress(UpdatePhase.downloading, 'Starting…');
    notifyListeners();
    try {
      await _updater.install(
        version,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );
    } catch (e) {
      _lastError = e is UpdateFailure ? e.message : 'Update failed: $e';
      _progress = UpdateProgress(UpdatePhase.failed, _lastError!);
      notifyListeners();
    }
  }

  /// Reinstalls whatever the latest published release is, even if it is
  /// the version already running — exercises the whole download, swap
  /// and relaunch path on demand.
  Future<void> reinstallLatest() async {
    final latest = await _service.checkForUpdate(force: true);
    if (latest == null) {
      _lastError = 'Could not reach the release service.';
      _progress = UpdateProgress(UpdatePhase.failed, _lastError!);
      notifyListeners();
      return;
    }
    await install(latest.version);
  }

  void clearError() {
    _lastError = null;
    _progress = UpdateProgress.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
