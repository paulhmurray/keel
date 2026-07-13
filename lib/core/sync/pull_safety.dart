/// Pull is destructive: importing a server blob clears every synced row
/// for that project and re-inserts from the blob. These helpers decide,
/// BEFORE the clear runs, whether that import can lose local work — and
/// what to do instead when it would.
///
/// All timestamps compared against `serverUpdatedAt` are themselves
/// server-issued (push and pull both return the server's `updated_at`,
/// which is what gets stored as "last sync"), so the server-moved check
/// never mixes clocks. `lastLocalChange` is local wall-clock and is only
/// used for the dirty check, same as the pending-changes indicator.
library;

/// What a Pull decided to do for one project.
enum PullOutcome {
  /// Server blob imported; there were no unpushed local edits to lose.
  imported,

  /// Local had unpushed edits and the server had nothing newer, so the
  /// import was skipped and local state was pushed up instead.
  keptLocalAndPushed,

  /// Local had unpushed edits AND the server blob was newer (edited on
  /// another machine). Local state was saved to a JSON snapshot, then the
  /// server blob was imported.
  conflictImported,

  /// The pull failed (network, decrypt, snapshot write, …). Nothing was
  /// cleared or imported.
  failed,
}

/// The safe action for a pull, decided before any destructive step.
enum PullSafety {
  /// No unpushed local edits — importing loses nothing.
  importClean,

  /// Unpushed local edits, server unchanged since our last sync —
  /// importing would only discard local work. Push local instead.
  keepLocalAndPush,

  /// Unpushed local edits AND the server moved since our last sync.
  /// Neither side can be discarded: snapshot local, then import server.
  conflict,
}

/// Pure pending-state rule shared with the sync status indicator: there
/// are unsynced changes when a change exists and it's newer than the last
/// sync (or there's been no sync at all).
bool hasUnpushedChanges(DateTime? lastLocalChange, DateTime? lastSync) {
  if (lastLocalChange == null) return false;
  if (lastSync == null) return true;
  return lastLocalChange.isAfter(lastSync);
}

/// Decides what a pull of one project may safely do.
///
/// [lastLocalChange] — when this machine last edited the project (null if
/// never / unknown). [lastSync] — server `updated_at` recorded at this
/// machine's last successful push or pull of the project (null if never).
/// [serverUpdatedAt] — server `updated_at` on the blob just fetched.
PullSafety resolvePullSafety({
  required DateTime? lastLocalChange,
  required DateTime? lastSync,
  required DateTime serverUpdatedAt,
}) {
  if (!hasUnpushedChanges(lastLocalChange, lastSync)) {
    return PullSafety.importClean;
  }
  // Dirty. If the server blob is still the one we last synced against,
  // pulling gains nothing and loses the local edits — keep local.
  final serverMoved = lastSync == null || serverUpdatedAt.isAfter(lastSync);
  return serverMoved ? PullSafety.conflict : PullSafety.keepLocalAndPush;
}
