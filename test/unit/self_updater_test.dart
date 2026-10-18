import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/update/self_updater.dart';

/// The parts of the in-app updater that can be proven without relaunching
/// anything: which asset to fetch, where the install lives, when a Mac
/// copy must not be touched, and the directory swap with its rollback.
void main() {
  group('asset urls', () {
    test('one known file name per platform under the tag', () {
      expect(
        updateAssetUrl('1.2.12', 'macos'),
        'https://github.com/paulhmurray/keel/releases/download/v1.2.12/keel-macos.zip',
      );
      expect(
        updateAssetUrl('v1.2.12', 'windows'),
        endsWith('/v1.2.12/keel-windows-setup.exe'),
      );
      expect(
        updateAssetUrl('1.2.12', 'linux'),
        endsWith('/v1.2.12/keel-linux.tar.gz'),
      );
    });
  });

  group('paths', () {
    test('translocated Mac copies are refused', () {
      expect(
        isTranslocated(
          '/private/var/folders/x/AppTranslocation/abc/d/Keel.app/Contents/MacOS/keel',
        ),
        isTrue,
      );
      expect(
        isTranslocated('/Applications/Keel.app/Contents/MacOS/keel'),
        isFalse,
      );
    });
    test('the bundle is found from the executable, whatever it is called', () {
      expect(
        macBundlePath('/Applications/keel.app/Contents/MacOS/keel'),
        '/Applications/keel.app',
      );
      expect(
        macBundlePath('/Users/s/Applications/Keel.app/Contents/MacOS/keel'),
        '/Users/s/Applications/Keel.app',
      );
      expect(macBundlePath('/usr/local/bin/keel'), isNull);
    });
    test('the install root is the executable directory', () {
      expect(
        installRootFor('/home/paulm/.local/share/keel/keel'),
        '/home/paulm/.local/share/keel',
      );
    });
  });

  group('directory swap', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('keel_swap_');
    });
    tearDown(() => root.delete(recursive: true));

    test('new in, old parked, parked swept next time', () async {
      final install = Directory('${root.path}/keel')..createSync();
      File('${install.path}/keel').writeAsStringSync('old');
      final staged = Directory('${root.path}/.keel-staging-1')..createSync();
      File('${staged.path}/keel').writeAsStringSync('new');

      final parked = await swapInstallDirs(
        installDir: install,
        stagedDir: staged,
        now: DateTime(2026, 10, 15),
      );
      expect(File('${install.path}/keel').readAsStringSync(), 'new');
      expect(
        parked,
        endsWith('/.keel-old-${DateTime(2026, 10, 15).millisecondsSinceEpoch}'),
      );
      expect(File('$parked/keel').readAsStringSync(), 'old');
      expect(staged.existsSync(), isFalse);

      await sweepOldInstalls(install);
      expect(Directory(parked).existsSync(), isFalse);
      expect(
        install.existsSync(),
        isTrue,
        reason: 'the live install is never swept',
      );
    });

    test('a failed second rename puts the old install back', () async {
      final install = Directory('${root.path}/keel')..createSync();
      File('${install.path}/keel').writeAsStringSync('old');
      // A staged dir that does not exist makes the second rename fail.
      final staged = Directory('${root.path}/missing');
      await expectLater(
        swapInstallDirs(installDir: install, stagedDir: staged),
        throwsA(isA<UpdateFailure>()),
      );
      expect(File('${install.path}/keel').readAsStringSync(), 'old');
      expect(
        root.listSync().whereType<Directory>().length,
        1,
        reason: 'nothing parked is left behind',
      );
    });
  });
}
