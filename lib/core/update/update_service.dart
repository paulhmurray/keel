import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String downloadUrl;
  final bool critical;

  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.critical,
  });
}

class UpdateService {
  static const _versionEndpoint = 'https://api.keel-app.dev/version/latest';

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse(_versionEndpoint))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersion = data['version'] as String;
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      if (!_isNewer(latestVersion, currentVersion)) return null;

      final platformKey = _platformKey();
      final urls = data['download_url'] as Map<String, dynamic>;
      final downloadUrl = urls[platformKey] as String? ?? '';

      return UpdateInfo(
        version: latestVersion,
        releaseNotes: data['release_notes'] as String? ?? '',
        downloadUrl: downloadUrl,
        critical: data['critical'] as bool? ?? false,
      );
    } catch (_) {
      // Fail silently — update checks are a courtesy, not a critical path
      return null;
    }
  }

  /// Returns true if [latest] is strictly newer than [current] (semver).
  bool _isNewer(String latest, String current) {
    final l = _parse(latest);
    final c = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  List<int> _parse(String v) {
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) parts.add(0);
    return parts;
  }

  String _platformKey() {
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'linux';
  }
}
