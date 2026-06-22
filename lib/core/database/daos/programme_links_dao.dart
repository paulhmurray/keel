part of '../database.dart';

/// Caller-supplied bridge to the sync server. The DAO doesn't depend
/// on the SyncClient class directly — that would create a layering
/// loop (sync depends on database, database would then depend on sync).
/// Instead, callers pass a thin remote object that knows how to talk
/// to the server when one is reachable, and the DAO degrades to
/// local-only when no remote is given (e.g. tests, offline use).
abstract class RemoteLinksGateway {
  Future<RemoteLinkSnapshot> claim({
    required String code,
    required String entityId,
    required String kind,
    required String name,
  });

  Future<RemoteLinkSnapshot?> fetch(String code);

  Future<void> revoke(String code);
}

/// Server-side view of a link — neutral shape the DAO can write to its
/// local rows. Mirrors the [RemoteLinkState] class in SyncClient but
/// kept here so we don't drag the http client into the database layer.
class RemoteLinkSnapshot {
  final String code;
  final RemoteLinkParty sideA;
  final RemoteLinkParty? sideB;
  final bool isActive;

  const RemoteLinkSnapshot({
    required this.code,
    required this.sideA,
    required this.sideB,
    required this.isActive,
  });

  /// Returns the side that is NOT the caller's. Caller passes their
  /// own [userId] (server-issued) so the DAO can pick the partner.
  RemoteLinkParty? partnerFor(String userId) {
    if (sideA.userId == userId) return sideB;
    if (sideB?.userId == userId) return sideA;
    return null;
  }
}

class RemoteLinkParty {
  final String userId;
  final String entityId;
  final String kind;
  final String name;

  const RemoteLinkParty({
    required this.userId,
    required this.entityId,
    required this.kind,
    required this.name,
  });
}

@DriftAccessor(tables: [ProgrammeLinks])
class ProgrammeLinksDao extends DatabaseAccessor<AppDatabase>
    with _$ProgrammeLinksDaoMixin {
  ProgrammeLinksDao(super.db);

  /// Watch the list of links one side of the relationship has — either
  /// a programme listing its child projects, or a project listing its
  /// parent programme(s). Newest first.
  Stream<List<ProgrammeLink>> watchLinksForEntity(String entityId) =>
      (select(programmeLinks)
            ..where((t) => t.ownerEntityId.equals(entityId))
            ..orderBy(
                [(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<List<ProgrammeLink>> getLinksForEntity(String entityId) =>
      (select(programmeLinks)
            ..where((t) => t.ownerEntityId.equals(entityId)))
          .get();

  Future<ProgrammeLink?> findByCode(String code) =>
      (select(programmeLinks)..where((t) => t.code.equals(code)))
          .getSingleOrNull();

  /// Generates a fresh share code AND inserts a `pending_remote` link
  /// row on this side. The returned code is what the user shares with
  /// the other party. Codes are 12 chars of base32-ish alphabet (no
  /// confusable 0/O/1/I), shown grouped as `KL-XXXX-XXXX-XXXX`.
  Future<String> generateCodeForEntity({
    required String ownerEntityId,
    required String ownerKind,
  }) async {
    final code = _generateCode();
    final partnerKind = ownerKind == 'programme' ? 'project' : 'programme';
    await into(programmeLinks).insert(
      ProgrammeLinksCompanion.insert(
        id: const Uuid().v4(),
        ownerEntityId: ownerEntityId,
        ownerKind: ownerKind,
        partnerKind: partnerKind,
        code: code,
        status: const Value('pending_remote'),
        generatedHere: const Value(true),
      ),
    );
    return code;
  }

  /// Redeems a code shared by the other side. If the partner entity is
  /// on this machine (single-install setup), the link activates both
  /// sides immediately — the redeem row is `active`, and so is the
  /// pre-existing row that holds the matching code. If the partner
  /// isn't on this machine, the redeem row sits at `pending_remote`
  /// and the cross-machine handshake (Phase C) is responsible for
  /// activating it once the server delivers partner identity.
  ///
  /// Returns a tuple describing what landed: the local link id + a
  /// status enum for the caller to surface in toast / dialog text.
  Future<({String id, RedeemOutcome outcome})> redeemCode({
    required String code,
    required String ownerEntityId,
    required String ownerKind,
    String? partnerNameHint,
  }) async {
    final cleanCode = _normaliseCode(code);
    final existingHere = await (select(programmeLinks)
          ..where((t) => t.code.equals(cleanCode)))
        .get();

    // Reject if this side already has a row for this code.
    final ownerAlready = existingHere
        .where((r) => r.ownerEntityId == ownerEntityId)
        .toList();
    if (ownerAlready.isNotEmpty) {
      return (id: ownerAlready.single.id, outcome: RedeemOutcome.alreadyLinked);
    }

    // Look for a same-machine partner — a row holding this code that
    // belongs to a DIFFERENT entity of the partner's kind.
    final partnerKind = ownerKind == 'programme' ? 'project' : 'programme';
    final localPartner = existingHere
        .where((r) =>
            r.ownerEntityId != ownerEntityId &&
            r.ownerKind == partnerKind)
        .toList();

    return transaction(() async {
      final id = const Uuid().v4();

      if (localPartner.isNotEmpty) {
        // Same-machine link: activate both rows + cache each other's
        // ids so future lookups don't need to scan by code.
        final partner = localPartner.first;
        final partnerOwnerName =
            await _lookupProjectName(partner.ownerEntityId);
        final myName = await _lookupProjectName(ownerEntityId);

        await into(programmeLinks).insert(
          ProgrammeLinksCompanion.insert(
            id: id,
            ownerEntityId: ownerEntityId,
            ownerKind: ownerKind,
            partnerKind: partnerKind,
            partnerName: Value(partnerOwnerName),
            partnerLocalId: Value(partner.ownerEntityId),
            code: cleanCode,
            status: const Value('active'),
          ),
        );
        await (update(programmeLinks)
              ..where((t) => t.id.equals(partner.id)))
            .write(ProgrammeLinksCompanion(
          partnerLocalId: Value(ownerEntityId),
          partnerName: Value(myName),
          status: const Value('active'),
        ));
        return (id: id, outcome: RedeemOutcome.activatedLocally);
      }

      // Cross-machine: store a pending_remote row so the user sees
      // their attempt persisted. Phase C upgrades it to 'active' on
      // server handshake.
      await into(programmeLinks).insert(
        ProgrammeLinksCompanion.insert(
          id: id,
          ownerEntityId: ownerEntityId,
          ownerKind: ownerKind,
          partnerKind: partnerKind,
          partnerName: Value(partnerNameHint),
          code: cleanCode,
          status: const Value('pending_remote'),
        ),
      );
      return (id: id, outcome: RedeemOutcome.pendingRemote);
    });
  }

  /// Manually break a link from either side. Mirrors the change to the
  /// same-machine partner row when present, so the other side sees
  /// 'revoked' immediately. Cross-machine partners get the news in
  /// Phase C when the server handshake is wired.
  Future<void> revokeLink(String linkId) async {
    await transaction(() async {
      final row = await (select(programmeLinks)
            ..where((t) => t.id.equals(linkId)))
          .getSingleOrNull();
      if (row == null) return;
      await (update(programmeLinks)..where((t) => t.id.equals(linkId)))
          .write(const ProgrammeLinksCompanion(
        status: Value('revoked'),
        partnerLocalId: Value(null),
      ));
      // Mirror to the local partner row if there is one.
      final twin = await (select(programmeLinks)
            ..where((t) =>
                t.code.equals(row.code) & t.id.equals(linkId).not()))
          .getSingleOrNull();
      if (twin != null) {
        await (update(programmeLinks)
              ..where((t) => t.id.equals(twin.id)))
            .write(const ProgrammeLinksCompanion(
          status: Value('revoked'),
          partnerLocalId: Value(null),
        ));
      }
    });
  }

  /// Hard-deletes a link row. Used by the settings UI to fully discard
  /// a `pending_remote` invitation that's never going to be accepted.
  Future<void> deleteLink(String id) =>
      (delete(programmeLinks)..where((t) => t.id.equals(id))).go();

  // ── Remote-aware variants ────────────────────────────────────────────────

  /// Remote-aware generate. Same shape as [generateCodeForEntity] —
  /// inserts a local pending_remote row — but ALSO attempts to claim
  /// our side on the server so the partner can find us when they
  /// redeem. Failures are silent: if the server is unreachable or
  /// auth isn't valid, the local row still exists and a future
  /// refresh can push it up.
  Future<String> generateCodeWithRemote({
    required String ownerEntityId,
    required String ownerKind,
    required String ownerName,
    required RemoteLinksGateway? remote,
  }) async {
    final code = await generateCodeForEntity(
        ownerEntityId: ownerEntityId, ownerKind: ownerKind);
    if (remote == null) return code;
    try {
      await remote.claim(
        code: code,
        entityId: ownerEntityId,
        kind: ownerKind,
        name: ownerName,
      );
    } catch (_) {
      // Server unreachable / unauthenticated — local row still exists
      // and a later refresh will sync it.
    }
    return code;
  }

  /// Remote-aware redeem. Tries same-machine activation first (cheap
  /// + works without the server). When that misses, falls back to the
  /// server: pushes our claim, reads back the link state, and lands
  /// the row as `active` when the partner is present. Otherwise the
  /// row sits at `pending_remote` and a future refresh will check.
  Future<({String id, RedeemOutcome outcome})> redeemCodeWithRemote({
    required String code,
    required String ownerEntityId,
    required String ownerKind,
    required String ownerName,
    required String? remoteUserId,
    required RemoteLinksGateway? remote,
  }) async {
    final local = await redeemCode(
      code: code,
      ownerEntityId: ownerEntityId,
      ownerKind: ownerKind,
    );
    if (local.outcome == RedeemOutcome.activatedLocally ||
        local.outcome == RedeemOutcome.alreadyLinked) {
      return local;
    }
    // local.outcome == pendingRemote — try to upgrade via the server.
    if (remote == null || remoteUserId == null) return local;
    try {
      final snapshot = await remote.claim(
        code: _normaliseCode(code),
        entityId: ownerEntityId,
        kind: ownerKind,
        name: ownerName,
      );
      final partner = snapshot.partnerFor(remoteUserId);
      if (snapshot.isActive && partner != null) {
        await (update(programmeLinks)
              ..where((t) => t.id.equals(local.id)))
            .write(ProgrammeLinksCompanion(
          status: const Value('active'),
          partnerName: Value(partner.name),
          // Partner is on a different machine — we don't have a local
          // id for them. The cache here is just the human-readable
          // identity sent by the server.
        ));
        return (id: local.id, outcome: RedeemOutcome.activatedLocally);
      }
    } catch (_) {
      // Network / auth failure — keep the pending row, refresh later.
    }
    return local;
  }

  /// Walks every `pending_remote` row and asks the server for its
  /// current state. Rows where the partner has now joined flip to
  /// `active`. Designed to be called on app launch and from a manual
  /// "Refresh" button — never throws.
  Future<int> refreshPendingLinks({
    required String? remoteUserId,
    required RemoteLinksGateway? remote,
  }) async {
    if (remote == null || remoteUserId == null) return 0;
    final rows = await (select(programmeLinks)
          ..where((t) => t.status.equals('pending_remote')))
        .get();
    var activated = 0;
    for (final row in rows) {
      try {
        final snapshot = await remote.fetch(row.code);
        if (snapshot == null) continue;
        final partner = snapshot.partnerFor(remoteUserId);
        if (snapshot.isActive && partner != null) {
          await (update(programmeLinks)..where((t) => t.id.equals(row.id)))
              .write(ProgrammeLinksCompanion(
            status: const Value('active'),
            partnerName: Value(partner.name),
          ));
          activated++;
        }
      } catch (_) {
        // Continue with the next row.
      }
    }
    return activated;
  }

  /// Remote-aware revoke. Flips local rows immediately (same-machine
  /// mirroring) then tells the server to drop our side, so cross-
  /// machine partners stop polling against the dead link.
  Future<void> revokeLinkWithRemote({
    required String linkId,
    required RemoteLinksGateway? remote,
  }) async {
    final row = await (select(programmeLinks)
          ..where((t) => t.id.equals(linkId)))
        .getSingleOrNull();
    await revokeLink(linkId);
    if (row != null && remote != null) {
      try {
        await remote.revoke(row.code);
      } catch (_) {
        // Best-effort — local state has already been updated.
      }
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  // Base32-ish alphabet with confusable characters removed.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  String _generateCode() {
    final rand = Random.secure();
    final buf = StringBuffer('KL-');
    for (var g = 0; g < 3; g++) {
      if (g > 0) buf.write('-');
      for (var i = 0; i < 4; i++) {
        buf.write(_alphabet[rand.nextInt(_alphabet.length)]);
      }
    }
    return buf.toString();
  }

  /// Strips spaces and lowercase chars so a user who pastes "kl ABCD ef…"
  /// still hits the same row a generated code wrote.
  String _normaliseCode(String input) {
    final cleaned = input.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return cleaned;
  }

  Future<String?> _lookupProjectName(String id) async {
    final row = await (select(projects)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.name;
  }
}

/// Result of a [ProgrammeLinksDao.redeemCode] call.
enum RedeemOutcome {
  /// The partner was on this machine and both rows are now `active`.
  activatedLocally,

  /// The partner isn't on this machine yet; row is `pending_remote`.
  /// Will activate once the cross-machine handshake lands.
  pendingRemote,

  /// This entity already has a row for this code — no-op.
  alreadyLinked,
}
