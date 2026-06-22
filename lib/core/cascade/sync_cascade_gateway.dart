import '../sync/sync_client.dart';
import 'cascade_service.dart';

/// HTTP-backed [CascadeGateway]. Same pattern as SyncLinksGateway —
/// kept out of the database layer so drift code doesn't depend on
/// http/json. Caller passes the live access token; an expired token
/// surfaces as a thrown SyncApiException which CascadeService
/// swallows for best-effort behaviour.
class SyncCascadeGateway implements CascadeGateway {
  final SyncClient client;
  final String accessToken;

  SyncCascadeGateway({
    required this.client,
    required this.accessToken,
  });

  @override
  Future<void> push({
    required String code,
    required String sourceEntityId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  }) =>
      client.pushCascadeItem(
        accessToken: accessToken,
        code: code,
        sourceEntityId: sourceEntityId,
        itemKind: itemKind,
        itemId: itemId,
        payload: payload,
      );

  @override
  Future<CascadePullSnapshot> pull({
    required String code,
    String? since,
  }) async {
    final result = await client.pullCascadeItems(
      accessToken: accessToken,
      code: code,
      since: since,
    );
    return CascadePullSnapshot(
      items: result.items
          .map((i) => CascadeRecord(
                sourceEntityId: i.sourceEntityId,
                itemKind: i.itemKind,
                itemId: i.itemId,
                payload: i.payload,
                deleted: i.deleted,
              ))
          .toList(),
      cursor: result.cursor,
    );
  }

  @override
  Future<void> delete({
    required String code,
    required String itemKind,
    required String itemId,
  }) =>
      client.deleteCascadeItem(
        accessToken: accessToken,
        code: code,
        itemKind: itemKind,
        itemId: itemId,
      );
}
