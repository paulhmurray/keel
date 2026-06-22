import '../database/database.dart';
import 'sync_client.dart';

/// Concrete [RemoteLinksGateway] backed by the live [SyncClient]. Sits
/// in the sync layer so the database layer can stay framework-free
/// (no imports of http, json, etc.). Caller passes the access token at
/// construction time and a stale token surfaces as a thrown
/// SyncApiException — the DAO swallows those and treats the row as
/// still-pending.
class SyncLinksGateway implements RemoteLinksGateway {
  final SyncClient client;
  final String accessToken;

  SyncLinksGateway({required this.client, required this.accessToken});

  @override
  Future<RemoteLinkSnapshot> claim({
    required String code,
    required String entityId,
    required String kind,
    required String name,
  }) async {
    final state = await client.claimLinkSide(
      accessToken: accessToken,
      code: code,
      entityId: entityId,
      kind: kind,
      name: name,
    );
    return _toSnapshot(state);
  }

  @override
  Future<RemoteLinkSnapshot?> fetch(String code) async {
    final state =
        await client.getLink(accessToken: accessToken, code: code);
    if (state == null) return null;
    return _toSnapshot(state);
  }

  @override
  Future<void> revoke(String code) =>
      client.revokeLinkSide(accessToken: accessToken, code: code);

  RemoteLinkSnapshot _toSnapshot(RemoteLinkState s) {
    return RemoteLinkSnapshot(
      code: s.code,
      sideA: RemoteLinkParty(
        userId: s.sideA.userId,
        entityId: s.sideA.entityId,
        kind: s.sideA.kind,
        name: s.sideA.name,
      ),
      sideB: s.sideB == null
          ? null
          : RemoteLinkParty(
              userId: s.sideB!.userId,
              entityId: s.sideB!.entityId,
              kind: s.sideB!.kind,
              name: s.sideB!.name,
            ),
      isActive: s.isActive,
    );
  }
}
