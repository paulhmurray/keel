/// In-app update: download the new release, swap it over the running
/// install, relaunch. The user sees a notice, clicks Install, Keel greys
/// out while it works, and comes back as the new version — the same
/// shape as a phone app.
///
/// Per platform:
/// - macOS: the release zip is extracted with `ditto` (keeps Apple's
///   signature intact), the running bundle is moved aside, the new one
///   moved to the same path, and `open -n` relaunches it. Bytes written
///   by Keel's own HTTP client carry no quarantine flag, so there is no
///   Gatekeeper prompt. A translocated bundle (run straight from the DMG
///   or a Downloads folder) refuses with a message to move Keel to
///   Applications first.
/// - Windows: the Inno Setup installer is started silently with
///   CloseApplications + RestartApplications; it closes Keel through the
///   Restart Manager, replaces the files and relaunches. Keel must NOT
///   exit first or there is nothing to restart.
/// - Linux: the tarball is extracted into a sibling of the install
///   directory (same filesystem, so the swap is a rename, never a copy
///   over a running binary), old renamed aside, new renamed in, the new
///   executable started detached, then exit. Old installs are swept on
///   the next start.
///
/// The pure parts (asset URLs, install-root resolution, translocation,
/// the directory swap) are unit-tested; the relaunches can only be
/// proven on each platform.
library;

import 'dart:io';

import 'package:http/http.dart' as http;

enum UpdatePhase {
  idle,
  downloading,
  extracting,
  installing,
  relaunching,
  failed,
}

class UpdateProgress {
  final UpdatePhase phase;

  /// 0..1 while downloading, null when indeterminate.
  final double? fraction;
  final String message;
  const UpdateProgress(this.phase, this.message, {this.fraction});

  static const idle = UpdateProgress(UpdatePhase.idle, '');
  bool get busy => phase != UpdatePhase.idle && phase != UpdatePhase.failed;
}

class UpdateFailure implements Exception {
  final String message;
  const UpdateFailure(this.message);
  @override
  String toString() => message;
}

// ─── Pure helpers ────────────────────────────────────────────────────────

const String kReleaseBase =
    'https://github.com/paulhmurray/keel/releases/download';

/// The asset the updater installs for [platform] ('macos' | 'windows' |
/// 'linux') at [version]. macOS uses the zip, not the DMG: a zip can be
/// extracted and swapped without mounting anything.
String updateAssetUrl(String version, String platform) {
  final tag = version.startsWith('v') ? version : 'v$version';
  final name = switch (platform) {
    'macos' => 'keel-macos.zip',
    'windows' => 'keel-windows-setup.exe',
    _ => 'keel-linux.tar.gz',
  };
  return '$kReleaseBase/$tag/$name';
}

/// macOS runs apps opened from an untrusted location (the DMG, Downloads)
/// from a randomised read-only path. Replacing that would not update the
/// copy the user has.
bool isTranslocated(String executablePath) =>
    executablePath.contains('/AppTranslocation/');

/// The `.app` bundle that contains [executablePath]
/// (…/Keel.app/Contents/MacOS/keel → …/Keel.app), or null when the path
/// is not inside a bundle.
String? macBundlePath(String executablePath) {
  final i = executablePath.indexOf('.app/Contents/MacOS/');
  if (i < 0) return null;
  return executablePath.substring(0, i + 4);
}

/// The directory a Linux or Windows install lives in: the executable's
/// own directory.
String installRootFor(String executablePath) {
  final i = executablePath.lastIndexOf(Platform.isWindows ? '\\' : '/');
  return i < 0 ? '.' : executablePath.substring(0, i);
}

/// Name for the directory the old install is parked in beside the new
/// one; swept on the next launch.
String oldInstallName(DateTime now) =>
    '.keel-old-${now.millisecondsSinceEpoch}';

/// Swaps [stagedDir] (a fully extracted new install) into [installDir]'s
/// place by rename, parking the old install beside it. Both must be on
/// the same filesystem. Returns the parked path. Rolls back if the
/// second rename fails so the user is never left without an install.
Future<String> swapInstallDirs({
  required Directory installDir,
  required Directory stagedDir,
  DateTime? now,
}) async {
  final parent = installDir.parent.path;
  final parked = Directory('$parent/${oldInstallName(now ?? DateTime.now())}');
  await installDir.rename(parked.path);
  try {
    await stagedDir.rename(installDir.path);
  } catch (e) {
    await parked.rename(installDir.path); // put it back
    throw UpdateFailure('Could not move the new version into place: $e');
  }
  return parked.path;
}

/// Removes parked old installs next to [installDir]. Best effort.
Future<void> sweepOldInstalls(Directory installDir) async {
  try {
    await for (final e in installDir.parent.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is Directory && name.startsWith('.keel-old-')) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    }
  } catch (_) {}
}

// ─── The updater ─────────────────────────────────────────────────────────

class SelfUpdater {
  final http.Client _client;
  SelfUpdater({http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  static String get platformKey => Platform.isMacOS
      ? 'macos'
      : Platform.isWindows
      ? 'windows'
      : 'linux';

  /// Downloads and installs [version], reporting through [onProgress].
  /// On success the process relaunches itself (Linux, macOS) or hands
  /// over to the installer (Windows) and this future never returns
  /// normally. Throws [UpdateFailure] with a sentence for the user.
  Future<void> install(
    String version, {
    required void Function(UpdateProgress) onProgress,
  }) async {
    final exe = Platform.resolvedExecutable;
    if (Platform.isMacOS && isTranslocated(exe)) {
      throw const UpdateFailure(
        'Keel is running from a temporary location. Move it to your '
        'Applications folder and open it from there, then update.',
      );
    }
    final url = updateAssetUrl(version, platformKey);
    final tmp = await Directory.systemTemp.createTemp('keel_update_');
    final file = File('${tmp.path}/${url.split('/').last}');
    await _download(url, file, onProgress);
    switch (platformKey) {
      case 'macos':
        await _installMac(file, tmp, onProgress);
      case 'windows':
        await _installWindows(file, onProgress);
      default:
        await _installLinux(file, tmp, onProgress);
    }
  }

  Future<void> _download(
    String url,
    File into,
    void Function(UpdateProgress) onProgress,
  ) async {
    onProgress(const UpdateProgress(UpdatePhase.downloading, 'Connecting…'));
    final response = await _client
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw UpdateFailure('Download failed (HTTP ${response.statusCode}).');
    }
    final total = response.contentLength ?? 0;
    var got = 0;
    final sink = into.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        got += chunk.length;
        final mb = (got / 1024 / 1024).toStringAsFixed(0);
        onProgress(
          UpdateProgress(
            UpdatePhase.downloading,
            total > 0
                ? 'Downloading… $mb of ${(total / 1024 / 1024).toStringAsFixed(0)} MB'
                : 'Downloading… $mb MB',
            fraction: total > 0 ? (got / total).clamp(0.0, 1.0) : null,
          ),
        );
      }
    } finally {
      await sink.close();
    }
    if (got == 0) throw const UpdateFailure('The download was empty.');
  }

  Future<void> _installMac(
    File zip,
    Directory tmp,
    void Function(UpdateProgress) onProgress,
  ) async {
    final bundle = macBundlePath(Platform.resolvedExecutable);
    if (bundle == null) {
      throw const UpdateFailure('Keel is not running from an app bundle.');
    }
    onProgress(const UpdateProgress(UpdatePhase.extracting, 'Unpacking…'));
    final staged = Directory('${tmp.path}/staged');
    await staged.create();
    final r = await Process.run('ditto', ['-x', '-k', zip.path, staged.path]);
    if (r.exitCode != 0) throw UpdateFailure('Unpacking failed: ${r.stderr}');
    final newApp = await staged
        .list()
        .where((e) => e is Directory && e.path.endsWith('.app'))
        .cast<Directory>()
        .first
        .catchError(
          (_) => throw const UpdateFailure('No app in the download.'),
        );
    if (!await File('${newApp.path}/Contents/MacOS/keel').exists()) {
      throw const UpdateFailure('The download does not contain Keel.');
    }
    onProgress(const UpdateProgress(UpdatePhase.installing, 'Installing…'));
    final current = Directory(bundle);
    final parked = Directory(
      '${current.parent.path}/${oldInstallName(DateTime.now())}.app',
    );
    await current.rename(parked.path);
    try {
      // Same volume? rename. Different (temp on another volume)? copy.
      try {
        await newApp.rename(bundle);
      } on FileSystemException {
        final cp = await Process.run('ditto', [newApp.path, bundle]);
        if (cp.exitCode != 0) {
          throw UpdateFailure('Copy failed: ${cp.stderr}');
        }
      }
      // Belt and braces: our own download has no quarantine flag, but a
      // stray one would block the relaunch.
      await Process.run('xattr', ['-dr', 'com.apple.quarantine', bundle]);
    } catch (e) {
      // Restore the working copy. Anything half-landed at the install
      // path must go first or the rename back would fail and leave the
      // user with a broken bundle and their real one parked.
      try {
        final landed = Directory(bundle);
        if (await landed.exists()) await landed.delete(recursive: true);
      } catch (_) {}
      await parked.rename(bundle);
      throw UpdateFailure('Could not install the new version: $e');
    }
    onProgress(const UpdateProgress(UpdatePhase.relaunching, 'Relaunching…'));
    await Process.start('open', [
      '-n',
      bundle,
    ], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }

  Future<void> _installWindows(
    File setup,
    void Function(UpdateProgress) onProgress,
  ) async {
    // The installer can only replace an install it made. A copy run from
    // the portable zip has no uninstaller beside it.
    final root = installRootFor(Platform.resolvedExecutable);
    if (!await File('$root\\unins000.exe').exists()) {
      throw const UpdateFailure(
        'This copy of Keel was unpacked from the zip, so it cannot update '
        'itself. Download keel-windows-setup.exe once; installs made by '
        'the installer update in place from then on.',
      );
    }
    onProgress(
      const UpdateProgress(
        UpdatePhase.installing,
        'Handing over to the installer…',
      ),
    );
    // Inno Setup closes Keel (Restart Manager), replaces it and relaunches.
    await Process.start(setup.path, [
      '/VERYSILENT',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/RESTARTAPPLICATIONS',
    ], mode: ProcessStartMode.detached);
    onProgress(
      const UpdateProgress(
        UpdatePhase.relaunching,
        'Installing… Keel will close and reopen.',
      ),
    );
  }

  Future<void> _installLinux(
    File tarball,
    Directory tmp,
    void Function(UpdateProgress) onProgress,
  ) async {
    final exe = Platform.resolvedExecutable;
    final installDir = Directory(installRootFor(exe));
    final parent = installDir.parent;
    // Writable check without touching the running files.
    try {
      final probe = File('${parent.path}/.keel-write-probe');
      await probe.writeAsString('x');
      await probe.delete();
    } catch (_) {
      throw UpdateFailure(
        'Keel is installed somewhere this user cannot write '
        '(${installDir.path}). Update it the way it was installed.',
      );
    }
    onProgress(const UpdateProgress(UpdatePhase.extracting, 'Unpacking…'));
    // Stage beside the install so the final move is a rename on one
    // filesystem — never a copy over a running binary.
    final staged = Directory(
      '${parent.path}/.keel-staging-${DateTime.now().millisecondsSinceEpoch}',
    );
    await staged.create();
    final r = await Process.run('tar', [
      '-xzf',
      tarball.path,
      '-C',
      staged.path,
    ]);
    if (r.exitCode != 0) {
      await staged.delete(recursive: true);
      throw UpdateFailure('Unpacking failed: ${r.stderr}');
    }
    final newExe = File('${staged.path}/keel');
    if (!await newExe.exists()) {
      await staged.delete(recursive: true);
      throw const UpdateFailure('The download does not contain Keel.');
    }
    onProgress(const UpdateProgress(UpdatePhase.installing, 'Installing…'));
    await swapInstallDirs(installDir: installDir, stagedDir: staged);
    await Process.run('chmod', ['+x', '${installDir.path}/keel']);
    onProgress(const UpdateProgress(UpdatePhase.relaunching, 'Relaunching…'));
    await Process.start(
      '${installDir.path}/keel',
      const [],
      mode: ProcessStartMode.detached,
      workingDirectory: installDir.path,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }
}
