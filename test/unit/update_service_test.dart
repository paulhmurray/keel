import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keel/core/update/update_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UpdateService _makeService({
  required String serverVersion,
  required String currentVersion,
  bool critical = false,
  String releaseNotes = '',
  int statusCode = 200,
}) {
  final client = MockClient((_) async => http.Response(
        jsonEncode({
          'version': serverVersion,
          'release_notes': releaseNotes,
          'download_url': {
            'linux': 'https://example.com/keel-linux.tar.gz',
            'windows': 'https://example.com/keel-windows-setup.exe',
            'macos': 'https://example.com/keel-macos.dmg',
          },
          'critical': critical,
        }),
        statusCode,
        headers: {'content-type': 'application/json'},
      ));
  return UpdateService(
    httpClient: client,
    overrideCurrentVersion: currentVersion,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // --- Version comparison ---

  group('version comparison', () {
    test('returns UpdateInfo when patch is newer', () async {
      final info = await _makeService(
        serverVersion: '1.0.1',
        currentVersion: '1.0.0',
      ).checkForUpdate();
      expect(info, isNotNull);
      expect(info!.version, '1.0.1');
    });

    test('returns UpdateInfo when minor is newer', () async {
      final info = await _makeService(
        serverVersion: '1.1.0',
        currentVersion: '1.0.5',
      ).checkForUpdate();
      expect(info, isNotNull);
      expect(info!.version, '1.1.0');
    });

    test('returns UpdateInfo when major is newer', () async {
      final info = await _makeService(
        serverVersion: '2.0.0',
        currentVersion: '1.9.9',
      ).checkForUpdate();
      expect(info, isNotNull);
    });

    test('returns null when versions are equal', () async {
      final info = await _makeService(
        serverVersion: '1.0.0',
        currentVersion: '1.0.0',
      ).checkForUpdate();
      expect(info, isNull);
    });

    test('returns null when current is newer than server', () async {
      final info = await _makeService(
        serverVersion: '1.0.0',
        currentVersion: '1.0.1',
      ).checkForUpdate();
      expect(info, isNull);
    });

    test('returns null when current minor is ahead', () async {
      final info = await _makeService(
        serverVersion: '1.0.0',
        currentVersion: '1.1.0',
      ).checkForUpdate();
      expect(info, isNull);
    });

    test('handles 2-part version strings gracefully', () async {
      final info = await _makeService(
        serverVersion: '1.1',
        currentVersion: '1.0',
      ).checkForUpdate();
      // '1.1' parses as [1,1,0], '1.0' as [1,0,0] → newer
      expect(info, isNotNull);
    });

    test('handles non-numeric segments as 0', () async {
      final info = await _makeService(
        serverVersion: '1.0.beta',
        currentVersion: '1.0.0',
      ).checkForUpdate();
      // 'beta' parses to 0, so versions are equal → null
      expect(info, isNull);
    });
  });

  // --- UpdateInfo fields ---

  group('UpdateInfo fields', () {
    test('critical flag is set correctly', () async {
      final info = await _makeService(
        serverVersion: '2.0.0',
        currentVersion: '1.0.0',
        critical: true,
      ).checkForUpdate();
      expect(info!.critical, isTrue);
    });

    test('critical flag is false by default', () async {
      final info = await _makeService(
        serverVersion: '1.0.1',
        currentVersion: '1.0.0',
      ).checkForUpdate();
      expect(info!.critical, isFalse);
    });

    test('release notes are included', () async {
      final info = await _makeService(
        serverVersion: '1.0.1',
        currentVersion: '1.0.0',
        releaseNotes: 'Bug fixes and improvements',
      ).checkForUpdate();
      expect(info!.releaseNotes, 'Bug fixes and improvements');
    });

    test('download URL is non-empty', () async {
      final info = await _makeService(
        serverVersion: '1.0.1',
        currentVersion: '1.0.0',
      ).checkForUpdate();
      expect(info!.downloadUrl, isNotEmpty);
    });
  });

  // --- Error handling ---

  group('error handling', () {
    test('returns null on non-200 response', () async {
      final info = await _makeService(
        serverVersion: '1.0.1',
        currentVersion: '1.0.0',
        statusCode: 503,
      ).checkForUpdate();
      expect(info, isNull);
    });

    test('returns null on 404 response', () async {
      final info = await _makeService(
        serverVersion: '1.0.1',
        currentVersion: '1.0.0',
        statusCode: 404,
      ).checkForUpdate();
      expect(info, isNull);
    });

    test('returns null on network error', () async {
      final client = MockClient((_) async => throw Exception('network error'));
      final svc = UpdateService(
        httpClient: client,
        overrideCurrentVersion: '1.0.0',
      );
      final info = await svc.checkForUpdate();
      expect(info, isNull);
    });

    test('returns null on malformed JSON', () async {
      final client = MockClient((_) async =>
          http.Response('not json', 200));
      final svc = UpdateService(
        httpClient: client,
        overrideCurrentVersion: '1.0.0',
      );
      final info = await svc.checkForUpdate();
      expect(info, isNull);
    });
  });
}
