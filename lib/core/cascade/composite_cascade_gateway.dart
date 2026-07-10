import 'dart:convert';

import '../database/database.dart';
import '../sync/encryption_service.dart';
import 'cascade_service.dart';
import 'local_cascade_gateway.dart';

/// Routes each cascade call to the right transport per link:
///   - same-machine links (the link row has a [partnerLocalId]) go to
///     the [LocalCascadeGateway] — no server, no auth, works offline, and
///     stays plaintext because the server is never involved.
///   - cross-machine links go to the [remote] HTTP gateway, with the
///     payload **end-to-end encrypted** using the link's per-link secret
///     so the server only ever stores ciphertext.
///
/// A programme with a mix of local and remote child projects routes each
/// link independently, because every call carries the link [code].
class CompositeCascadeGateway implements CascadeGateway {
  final AppDatabase db;
  final LocalCascadeGateway _local;
  final CascadeGateway? remote;

  CompositeCascadeGateway(this.db, {this.remote})
      : _local = LocalCascadeGateway(db);

  /// Wrapper key under which the ciphertext travels inside the JSON
  /// payload the server stores. Its presence marks an encrypted item.
  static const _encKey = '__enc__';

  /// Resolves a link's routing (local vs remote) + its secret in one read.
  Future<({bool isLocal, String? secret})> _resolve(String code) async {
    final links = await db.programmeLinksDao.getByCode(code);
    final isLocal = links.any((l) => l.partnerLocalId != null);
    String? secret;
    for (final l in links) {
      if (l.linkSecret != null) {
        secret = l.linkSecret;
        break;
      }
    }
    return (isLocal: isLocal, secret: secret);
  }

  @override
  Future<void> push({
    required String code,
    required String sourceEntityId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  }) async {
    final r = await _resolve(code);
    if (r.isLocal) {
      await _local.push(
        code: code,
        sourceEntityId: sourceEntityId,
        itemKind: itemKind,
        itemId: itemId,
        payload: payload,
      );
      return;
    }
    if (remote == null) return;
    // Remote link → encrypt end-to-end. Without a usable key we DECLINE
    // to send rather than leak plaintext to the server.
    final key = EncryptionService.keyFromLinkSecret(r.secret);
    if (key == null) return;
    final ciphertext =
        await EncryptionService.encrypt(key, jsonEncode(payload));
    await remote!.push(
      code: code,
      sourceEntityId: sourceEntityId,
      itemKind: itemKind,
      itemId: itemId,
      payload: {_encKey: ciphertext},
    );
  }

  @override
  Future<CascadePullSnapshot> pull({
    required String code,
    String? since,
  }) async {
    final r = await _resolve(code);
    if (r.isLocal) return _local.pull(code: code, since: since);
    if (remote == null) {
      return const CascadePullSnapshot(items: [], cursor: '');
    }
    final snap = await remote!.pull(code: code, since: since);
    final key = EncryptionService.keyFromLinkSecret(r.secret);
    final items = <CascadeRecord>[];
    for (final rec in snap.items) {
      // Tombstones carry no payload — pass straight through.
      if (rec.deleted) {
        items.add(rec);
        continue;
      }
      final enc = rec.payload[_encKey];
      if (enc is String) {
        if (key == null) continue; // encrypted but no key → can't read; skip
        try {
          final plain = await EncryptionService.decrypt(key, enc);
          final map = (jsonDecode(plain) as Map).cast<String, dynamic>();
          items.add(CascadeRecord(
            sourceEntityId: rec.sourceEntityId,
            itemKind: rec.itemKind,
            itemId: rec.itemId,
            payload: map,
            deleted: false,
          ));
        } catch (_) {
          // Tampered / wrong key — drop the item rather than surface junk.
        }
      } else {
        // No envelope → legacy/plaintext item; pass through unchanged.
        items.add(rec);
      }
    }
    return CascadePullSnapshot(items: items, cursor: snap.cursor);
  }

  @override
  Future<void> delete({
    required String code,
    required String itemKind,
    required String itemId,
  }) async {
    final r = await _resolve(code);
    if (r.isLocal) {
      await _local.delete(code: code, itemKind: itemKind, itemId: itemId);
      return;
    }
    if (remote == null) return;
    await remote!.delete(code: code, itemKind: itemKind, itemId: itemId);
  }
}
