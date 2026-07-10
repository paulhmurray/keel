import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../database/database.dart';
import '../sync/sync_client.dart';
import '../../providers/sync_provider.dart';
import 'cascade_service.dart';
import 'composite_cascade_gateway.dart';
import 'sync_cascade_gateway.dart';

/// Single construction point for a [CascadeService] used across every
/// view that pushes or pulls cascaded data.
///
/// The gateway is a [CompositeCascadeGateway] that always has the local
/// transport available — so same-machine project↔programme cascade works
/// even when signed out — and adds the HTTP transport for cross-machine
/// links whenever the user is authenticated. This replaces the per-view
/// `_cascadeFor` helpers that each only ever built the remote gateway and
/// no-op'd when offline.
CascadeService buildCascadeService(BuildContext context) {
  return buildCascadeServiceWith(
    context.read<AppDatabase>(),
    context.read<SyncProvider>(),
  );
}

/// Provider-free variant for call sites that already hold the [db] and
/// [sync] objects (e.g. SyncProvider's own reconcile loop, shell startup).
CascadeService buildCascadeServiceWith(AppDatabase db, SyncProvider sync) {
  final token = sync.accessToken;
  return CascadeService(
    db,
    gateway: CompositeCascadeGateway(
      db,
      remote: token == null
          ? null
          : SyncCascadeGateway(
              client: SyncClient(baseUrl: sync.serverUrl),
              accessToken: token,
            ),
    ),
  );
}
