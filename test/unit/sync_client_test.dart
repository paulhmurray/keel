import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keel/core/sync/sync_client.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MockClient _mockClient(int status, Map<String, dynamic> body) {
  return MockClient((_) async => http.Response(jsonEncode(body), status,
      headers: {'content-type': 'application/json'}));
}

SyncClient _clientWith(MockClient mock) {
  return SyncClient(baseUrl: 'http://localhost', httpClient: mock);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // --- SyncApiException ---

  group('SyncApiException', () {
    test('stores statusCode and message', () {
      const e = SyncApiException(401, 'unauthorized');
      expect(e.statusCode, 401);
      expect(e.message, 'unauthorized');
    });

    test('toString includes statusCode and message', () {
      const e = SyncApiException(500, 'internal error');
      expect(e.toString(), contains('500'));
      expect(e.toString(), contains('internal error'));
    });
  });

  // --- AuthTokens.fromJson ---

  group('AuthTokens.fromJson', () {
    test('parses all fields', () {
      final tokens = AuthTokens.fromJson({
        'access_token': 'acc.tok.en',
        'refresh_token': 'ref.tok.en',
        'user_id': 'user-uuid-123',
        'plan': 'solo',
      });
      expect(tokens.accessToken, 'acc.tok.en');
      expect(tokens.refreshToken, 'ref.tok.en');
      expect(tokens.userId, 'user-uuid-123');
      expect(tokens.plan, 'solo');
    });

    test('free plan is parsed correctly', () {
      final tokens = AuthTokens.fromJson({
        'access_token': 'a',
        'refresh_token': 'r',
        'user_id': 'u',
        'plan': 'free',
      });
      expect(tokens.plan, 'free');
    });
  });

  // --- ProjectSummary.fromJson ---

  group('ProjectSummary.fromJson', () {
    test('parses all fields', () {
      final summary = ProjectSummary.fromJson({
        'id': 'proj-uuid-456',
        'name': 'Alpha Programme',
        'updated_at': '2025-03-28T12:00:00Z',
      });
      expect(summary.id, 'proj-uuid-456');
      expect(summary.name, 'Alpha Programme');
      expect(summary.updatedAt.year, 2025);
      expect(summary.updatedAt.month, 3);
      expect(summary.updatedAt.day, 28);
    });

    test('updatedAt is a DateTime', () {
      final summary = ProjectSummary.fromJson({
        'id': 'p',
        'name': 'N',
        'updated_at': '2024-01-15T09:30:00Z',
      });
      expect(summary.updatedAt, isA<DateTime>());
    });
  });

  // --- SyncClient HTTP interactions ---

  group('SyncClient.register', () {
    test('success returns AuthTokens', () async {
      final mock = _mockClient(201, {
        'access_token': 'acc',
        'refresh_token': 'ref',
        'user_id': 'uid',
        'plan': 'free',
      });
      final client = _clientWith(mock);
      final tokens = await client.register('user@test.com', 'password123');
      expect(tokens.accessToken, 'acc');
      expect(tokens.userId, 'uid');
    });

    test('409 conflict throws SyncApiException', () async {
      final mock =
          _mockClient(409, {'error': 'email already registered'});
      final client = _clientWith(mock);
      expect(
        () => client.register('taken@test.com', 'password123'),
        throwsA(isA<SyncApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)),
      );
    });

    test('400 bad request throws SyncApiException', () async {
      final mock = _mockClient(400, {'error': 'invalid email'});
      final client = _clientWith(mock);
      expect(
        () => client.register('bad', 'pw'),
        throwsA(isA<SyncApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('SyncClient.login', () {
    test('success returns AuthTokens', () async {
      final mock = _mockClient(200, {
        'access_token': 'acc2',
        'refresh_token': 'ref2',
        'user_id': 'uid2',
        'plan': 'solo',
      });
      final tokens = await _clientWith(mock).login('u@test.com', 'pass');
      expect(tokens.plan, 'solo');
      expect(tokens.refreshToken, 'ref2');
    });

    test('401 throws SyncApiException', () async {
      final mock =
          _mockClient(401, {'error': 'invalid email or password'});
      expect(
        () => _clientWith(mock).login('u@test.com', 'wrong'),
        throwsA(isA<SyncApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('SyncApiException message is extracted from JSON error field', () async {
      final mock = _mockClient(401, {'error': 'invalid email or password'});
      try {
        await _clientWith(mock).login('u@test.com', 'wrong');
        fail('expected exception');
      } on SyncApiException catch (e) {
        expect(e.message, contains('invalid email or password'));
      }
    });
  });

  group('SyncClient.listProjects', () {
    test('success returns list of ProjectSummary', () async {
      final mock = MockClient((_) async => http.Response(
            jsonEncode([
              {
                'id': 'p1',
                'name': 'Project One',
                'updated_at': '2025-01-01T00:00:00Z'
              },
              {
                'id': 'p2',
                'name': 'Project Two',
                'updated_at': '2025-02-01T00:00:00Z'
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final projects = await _clientWith(mock).listProjects('access-token');
      expect(projects.length, 2);
      expect(projects[0].name, 'Project One');
      expect(projects[1].id, 'p2');
    });

    test('empty list is returned correctly', () async {
      final mock = MockClient((_) async => http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          ));
      final projects = await _clientWith(mock).listProjects('token');
      expect(projects, isEmpty);
    });

    test('401 throws SyncApiException', () async {
      final mock = _mockClient(401, {'error': 'unauthorized'});
      expect(
        () => _clientWith(mock).listProjects('bad-token'),
        throwsA(isA<SyncApiException>()),
      );
    });
  });

  group('SyncClient.pushSync', () {
    test('success returns updatedAt DateTime', () async {
      final mock = MockClient((_) async => http.Response(
            jsonEncode({'updated_at': '2025-03-28T14:00:00Z'}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final updatedAt =
          await _clientWith(mock).pushSync('token', 'proj-id', 'base64data==');
      expect(updatedAt.year, 2025);
      expect(updatedAt.month, 3);
      expect(updatedAt.day, 28);
    });

    test('404 project not found throws SyncApiException', () async {
      final mock = _mockClient(404, {'error': 'project not found'});
      expect(
        () => _clientWith(mock).pushSync('token', 'proj-id', 'data'),
        throwsA(isA<SyncApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('SyncClient.pullSync', () {
    test('success returns encrypted data and updatedAt', () async {
      final mock = MockClient((_) async => http.Response(
            jsonEncode({
              'encrypted_data': 'base64encryptedblob==',
              'updated_at': '2025-03-28T15:30:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final result =
          await _clientWith(mock).pullSync('token', 'proj-id');
      expect(result.encryptedBase64, 'base64encryptedblob==');
      expect(result.updatedAt.year, 2025);
    });

    test('404 throws SyncApiException', () async {
      final mock = _mockClient(404, {'error': 'no sync data available'});
      expect(
        () => _clientWith(mock).pullSync('token', 'proj-id'),
        throwsA(isA<SyncApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('SyncClient.refresh', () {
    test('success returns new access token string', () async {
      final mock = MockClient((_) async => http.Response(
            jsonEncode({'access_token': 'new-access-token'}),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final token =
          await _clientWith(mock).refresh('old-refresh-token');
      expect(token, 'new-access-token');
    });

    test('401 throws SyncApiException', () async {
      final mock = _mockClient(401, {'error': 'invalid or expired token'});
      expect(
        () => _clientWith(mock).refresh('bad-token'),
        throwsA(isA<SyncApiException>()),
      );
    });
  });

  group('SyncClient._checkStatus (5xx errors)', () {
    test('500 error extracts error message from JSON body', () async {
      final mock = _mockClient(500, {'error': 'internal server error'});
      try {
        await _clientWith(mock).listProjects('token');
        fail('expected exception');
      } on SyncApiException catch (e) {
        expect(e.statusCode, 500);
        expect(e.message, contains('internal server error'));
      }
    });

    test('503 with non-JSON body still throws SyncApiException', () async {
      final mock = MockClient((_) async =>
          http.Response('Service Unavailable', 503));
      try {
        await _clientWith(mock).listProjects('token');
        fail('expected exception');
      } on SyncApiException catch (e) {
        expect(e.statusCode, 503);
      }
    });
  });
}
