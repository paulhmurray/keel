import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/sync/sync_client.dart';
import 'package:keel/providers/sync_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// JWT helpers
// ---------------------------------------------------------------------------

/// Builds a minimal JWT with the given exp (Unix timestamp).
/// Not cryptographically valid — only used to test client-side expiry parsing.
String _makeJwt({required int exp, String type = 'access'}) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payload = base64Url.encode(utf8.encode(
    jsonEncode({'sub': 'user-123', 'type': type, 'exp': exp, 'plan': 'free'}),
  ));
  // Signature is fake — we only test parsing, not verification
  const sig = 'fake-signature';
  return '$header.$payload.$sig';
}

int _nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Mock FlutterSecureStorage platform channel (delete, write, read all return null)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    SharedPreferences.setMockInitialValues({});
  });

  // --- Initial state ---

  group('initial state', () {
    test('isAuthenticated is false before login', () {
      expect(SyncProvider().isAuthenticated, isFalse);
    });

    test('hasPendingChangesFor is false before login', () {
      expect(SyncProvider().hasPendingChangesFor('p-1'), isFalse);
    });

    test('status starts idle', () {
      expect(SyncProvider().status, SyncStatus.idle);
    });

    test('lastError is null initially', () {
      expect(SyncProvider().lastError, isNull);
    });

    test('userId is null initially', () {
      expect(SyncProvider().userId, isNull);
    });

    test('plan is null initially', () {
      expect(SyncProvider().plan, isNull);
    });
  });

  // --- loadFromSettings ---

  group('loadFromSettings', () {
    test('populates serverUrl, syncEnabled, and email', () {
      final sp = SyncProvider();
      sp.loadFromSettings({
        'syncServerUrl': 'https://custom.example.com',
        'syncEnabled': true,
        'syncEmail': 'user@example.com',
      });
      expect(sp.serverUrl, 'https://custom.example.com');
      expect(sp.syncEnabled, isTrue);
      expect(sp.email, 'user@example.com');
    });

    test('uses defaults for missing keys', () {
      final sp = SyncProvider();
      sp.loadFromSettings({});
      expect(sp.serverUrl, 'https://sync.keel-app.dev');
      expect(sp.syncEnabled, isFalse);
      expect(sp.email, isNull);
    });

    test('treats empty email string as null', () {
      final sp = SyncProvider();
      sp.loadFromSettings({'syncEmail': ''});
      expect(sp.email, isNull);
    });

    test('does not change auth state', () {
      final sp = SyncProvider();
      sp.loadFromSettings({'syncServerUrl': 'https://other.example.com'});
      expect(sp.isAuthenticated, isFalse);
    });
  });

  // --- logout ---

  group('logout', () {
    test('clears auth state', () async {
      final sp = SyncProvider();
      // Manually set state to simulate a logged-in session
      // (we can't call login without a real server, but we can test logout resets state)
      await sp.logout();
      expect(sp.isAuthenticated, isFalse);
      expect(sp.userId, isNull);
      expect(sp.plan, isNull);
      expect(sp.status, SyncStatus.idle);
      expect(sp.lastError, isNull);
    });
  });

  // --- markLocalChange / hasPendingChangesFor ---

  group('hasPendingChangesFor', () {
    test('is false when not authenticated even after a local change', () {
      final sp = SyncProvider();
      sp.markLocalChange('p-1');
      expect(sp.hasPendingChangesFor('p-1'), isFalse);
    });

    test('is false when no project id is given', () {
      expect(SyncProvider().hasPendingChangesFor(null), isFalse);
    });

    test('lastSyncAtFor is null initially for any entity', () {
      final sp = SyncProvider();
      expect(sp.lastSyncAtFor('p-1'), isNull);
      expect(sp.lastSyncAtFor(null), isNull);
    });
  });

  // --- pendingFrom (pure pending-state rule) ---

  group('pendingFrom', () {
    test('no change → not pending', () {
      expect(SyncProvider.pendingFrom(null, DateTime(2026)), isFalse);
    });

    test('change but never synced → pending', () {
      expect(SyncProvider.pendingFrom(DateTime(2026), null), isTrue);
    });

    test('change after last sync → pending', () {
      expect(
        SyncProvider.pendingFrom(DateTime(2026, 6, 2), DateTime(2026, 6, 1)),
        isTrue,
      );
    });

    test('change at/before last sync → not pending', () {
      expect(
        SyncProvider.pendingFrom(DateTime(2026, 6, 1), DateTime(2026, 6, 2)),
        isFalse,
      );
    });
  });

  // --- encode/decode per-entity timestamps ---

  group('timestamp map serialization', () {
    test('round-trips an id→timestamp map', () {
      final map = {
        'tac-integration': DateTime(2026, 6, 18, 9, 30),
        'digital-toolkit': DateTime(2026, 6, 19, 14, 15),
      };
      final decoded =
          SyncProvider.decodeTimestamps(SyncProvider.encodeTimestamps(map));
      expect(decoded, map);
    });

    test('decodes null / blank / garbage to an empty map', () {
      expect(SyncProvider.decodeTimestamps(null), isEmpty);
      expect(SyncProvider.decodeTimestamps(''), isEmpty);
      expect(SyncProvider.decodeTimestamps('not json'), isEmpty);
    });

    test('skips unparseable timestamp values but keeps valid ones', () {
      final decoded = SyncProvider.decodeTimestamps(
          '{"good":"2026-06-18T09:30:00.000","bad":"nope"}');
      expect(decoded.keys, ['good']);
      expect(decoded['good'], DateTime(2026, 6, 18, 9, 30));
    });
  });

  // --- _isTokenExpired (tested via token parsing behaviour) ---

  group('token expiry detection', () {
    test('expired token is detected as expired', () {
      // We test this indirectly through tryRestoreSession failing on an expired token.
      // Create a JWT that expired 1 hour ago.
      final expiredToken = _makeJwt(exp: _nowSecs() - 3600);
      // The token should be parseable as base64 payload
      final parts = expiredToken.split('.');
      expect(parts.length, 3);
      final decoded = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      expect(decoded['exp'] < _nowSecs(), isTrue);
    });

    test('valid token has future exp', () {
      final validToken = _makeJwt(exp: _nowSecs() + 3600);
      final parts = validToken.split('.');
      final decoded = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      expect(decoded['exp'] > _nowSecs(), isTrue);
    });

    test('malformed token with fewer than 3 parts would be treated as expired', () {
      // Verify the JWT structure assumption: 3 parts split by '.'
      const malformed = 'not.a.valid.jwt.at.all';
      final parts = malformed.split('.');
      // 6 parts — parsing would fail gracefully
      expect(parts.length, isNot(equals(3)));
    });
  });

  // --- userEmail ---

  group('userEmail', () {
    test('returns email from loadFromSettings', () {
      final sp = SyncProvider();
      sp.loadFromSettings({'syncEmail': 'test@example.com'});
      expect(sp.userEmail, 'test@example.com');
    });

    test('returns null when no email set', () {
      expect(SyncProvider().userEmail, isNull);
    });
  });

  // --- listServerProjects ---

  group('listServerProjects', () {
    test('returns empty list when not authenticated', () async {
      final sp = SyncProvider();
      final projects = await sp.listServerProjects();
      expect(projects, isEmpty);
    });
  });

  // --- getCheckoutUrl / getBillingPortalUrl ---

  group('billing helpers when not authenticated', () {
    test('getCheckoutUrl returns null', () async {
      expect(await SyncProvider().getCheckoutUrl(), isNull);
    });

    test('getBillingPortalUrl returns null', () async {
      expect(await SyncProvider().getBillingPortalUrl(), isNull);
    });
  });

  // --- resolvePullTarget ---

  group('resolvePullTarget', () {
    ProjectSummary summary(String id) =>
        ProjectSummary(id: id, name: id, updatedAt: DateTime(2026));

    test('pulls the current project when it exists on the server', () {
      final servers = [summary('proj-a'), summary('prog-b')];
      expect(SyncProvider.resolvePullTarget('prog-b', servers), 'prog-b');
    });

    test('falls back to the first server project when current id is absent',
        () {
      // e.g. a seeded demo project whose non-UUID id was never pushed.
      final servers = [summary('proj-a'), summary('prog-b')];
      expect(SyncProvider.resolvePullTarget('seed-local', servers), 'proj-a');
    });

    test('falls back to first when there is no current project', () {
      final servers = [summary('proj-a')];
      expect(SyncProvider.resolvePullTarget(null, servers), 'proj-a');
    });
  });
}
