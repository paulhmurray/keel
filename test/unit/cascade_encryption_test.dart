import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_service.dart';
import 'package:keel/core/cascade/composite_cascade_gateway.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/sync/encryption_service.dart';

/// Records what a remote gateway is asked to send, and serves it back —
/// standing in for the server. Its stored payloads are exactly what the
/// server would see.
class _RecordingRemote implements CascadeGateway {
  final Map<String, CascadeRecord> store = {};
  Map<String, dynamic>? lastPushedPayload;

  String _k(String kind, String id) => '$kind/$id';

  @override
  Future<void> push({
    required String code,
    required String sourceEntityId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  }) async {
    lastPushedPayload = payload;
    store[_k(itemKind, itemId)] = CascadeRecord(
      sourceEntityId: sourceEntityId,
      itemKind: itemKind,
      itemId: itemId,
      payload: payload,
      deleted: false,
    );
  }

  @override
  Future<CascadePullSnapshot> pull({required String code, String? since}) async {
    return CascadePullSnapshot(items: store.values.toList(), cursor: 'c');
  }

  @override
  Future<void> delete(
      {required String code,
      required String itemKind,
      required String itemId}) async {
    store.remove(_k(itemKind, itemId));
  }
}

void main() {
  group('EncryptionService link secret', () {
    test('a generated secret yields a 32-byte AES key', () {
      final secret = EncryptionService.generateLinkSecret();
      expect(EncryptionService.keyFromLinkSecret(secret), isNotNull);
    });

    test('missing / malformed secrets yield no key', () {
      expect(EncryptionService.keyFromLinkSecret(null), isNull);
      expect(EncryptionService.keyFromLinkSecret(''), isNull);
      expect(EncryptionService.keyFromLinkSecret('too-short'), isNull);
    });

    test('encrypt → decrypt round-trips with a link-secret key', () async {
      final key = EncryptionService.keyFromLinkSecret(
          EncryptionService.generateLinkSecret())!;
      final blob = await EncryptionService.encrypt(key, 'top secret risk');
      expect(blob, isNot(contains('top secret')));
      expect(await EncryptionService.decrypt(key, blob), 'top secret risk');
    });
  });

  group('CompositeCascadeGateway E2E encryption (remote links)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.memory();
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'proj', name: 'Proj'));
    });
    tearDown(() async => db.close());

    /// Cross-machine link on the project side: a pending_remote row with a
    /// secret and no local partner.
    Future<String> remoteLink() async {
      final secret = EncryptionService.generateLinkSecret();
      const routing = 'KL-AAAA-BBBB-CCCC';
      await db.programmeLinksDao.redeemCode(
        code: '$routing#$secret',
        ownerEntityId: 'proj',
        ownerKind: 'project',
      );
      return routing;
    }

    test('the server only ever sees ciphertext — never the plaintext '
        'payload', () async {
      final routing = await remoteLink();
      final remote = _RecordingRemote();
      final gw = CompositeCascadeGateway(db, remote: remote);

      await gw.push(
        code: routing,
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: {'description': 'vendor may breach SLA', 'owner': 'Jane'},
      );

      // What the "server" received is an opaque envelope, not the fields.
      final seen = remote.lastPushedPayload!;
      expect(seen.keys, ['__enc__']);
      expect(seen.toString(), isNot(contains('vendor may breach')));
      expect(seen.toString(), isNot(contains('Jane')));
    });

    test('pull decrypts back to the original payload', () async {
      final routing = await remoteLink();
      final remote = _RecordingRemote();
      final gw = CompositeCascadeGateway(db, remote: remote);
      await gw.push(
        code: routing,
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: {'description': 'vendor may breach SLA', 'owner': 'Jane'},
      );

      final snap = await gw.pull(code: routing);
      expect(snap.items, hasLength(1));
      final rec = snap.items.single;
      expect(rec.payload['description'], 'vendor may breach SLA');
      expect(rec.payload['owner'], 'Jane');
    });

    test('an item encrypted under a different secret is dropped, not '
        'surfaced as junk', () async {
      final routing = await remoteLink();
      final remote = _RecordingRemote();
      // Push with the real key.
      final gw = CompositeCascadeGateway(db, remote: remote);
      await gw.push(
        code: routing,
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: const {'description': 'x'},
      );

      // Now rotate the link's secret so decryption keys no longer match.
      await (db.update(db.programmeLinks)
            ..where((t) => t.code.equals(routing)))
          .write(ProgrammeLinksCompanion(
              linkSecret: Value(EncryptionService.generateLinkSecret())));

      final snap = await gw.pull(code: routing);
      expect(snap.items, isEmpty);
    });
  });
}
