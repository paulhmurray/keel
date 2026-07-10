import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/database.dart';
import 'cascade_service.dart';

/// Same-machine [CascadeGateway]. When a project and a programme live in
/// one install, the link activates locally and there's no sync server to
/// route through. This gateway IS the transport: it persists pushed
/// items to the local [CascadeItems] table keyed by the link code, and
/// the programme's pull reads them straight back.
///
/// It mirrors [SyncCascadeGateway]'s contract exactly so [CascadeService]
/// can't tell the difference — push upserts a row, delete writes a
/// tombstone, pull returns every row under the code.
class LocalCascadeGateway implements CascadeGateway {
  final AppDatabase db;

  LocalCascadeGateway(this.db);

  @override
  Future<void> push({
    required String code,
    required String sourceEntityId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  }) async {
    await db.into(db.cascadeItems).insertOnConflictUpdate(
          CascadeItemsCompanion.insert(
            code: code,
            sourceEntityId: sourceEntityId,
            itemKind: itemKind,
            itemId: itemId,
            payload: jsonEncode(payload),
            deleted: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<CascadePullSnapshot> pull({
    required String code,
    String? since,
  }) async {
    final rows = await (db.select(db.cascadeItems)
          ..where((t) => t.code.equals(code)))
        .get();
    final items = rows.map((r) {
      Map<String, dynamic> payload;
      try {
        payload = (jsonDecode(r.payload) as Map).cast<String, dynamic>();
      } catch (_) {
        payload = const {};
      }
      return CascadeRecord(
        sourceEntityId: r.sourceEntityId,
        itemKind: r.itemKind,
        itemId: r.itemId,
        payload: payload,
        deleted: r.deleted,
      );
    }).toList();
    // No remote cursor on the local channel — the synthetic value is
    // ignored (pullForProgramme re-fetches the whole channel each call).
    return CascadePullSnapshot(items: items, cursor: 'local');
  }

  @override
  Future<void> delete({
    required String code,
    required String itemKind,
    required String itemId,
  }) async {
    // Tombstone rather than hard-delete so a programme that hasn't
    // pulled yet still learns the item went away on its next pull.
    final existing = await (db.select(db.cascadeItems)
          ..where((t) =>
              t.code.equals(code) &
              t.itemKind.equals(itemKind) &
              t.itemId.equals(itemId)))
        .getSingleOrNull();
    await db.into(db.cascadeItems).insertOnConflictUpdate(
          CascadeItemsCompanion.insert(
            code: code,
            sourceEntityId: existing?.sourceEntityId ?? '',
            itemKind: itemKind,
            itemId: itemId,
            payload: existing?.payload ?? '{}',
            deleted: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
