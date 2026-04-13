import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/update/update_service.dart';

class UpdateProvider extends ChangeNotifier {
  final UpdateService _service = UpdateService();

  UpdateInfo? _updateInfo;
  Timer? _timer;

  UpdateInfo? get updateInfo => _updateInfo;

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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
