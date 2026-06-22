import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/cascade/cascade_service.dart';
import '../core/cascade/cascade_sync.dart';
import '../core/cascade/sync_cascade_gateway.dart';
import '../core/database/database.dart';
import '../core/export/json_exporter.dart';
import '../core/import/json_importer.dart';
import '../core/sync/encryption_service.dart';
import '../core/sync/links_gateway.dart';
import '../core/sync/sync_client.dart';

const _kSecureRefreshToken = 'keel_refresh_token';
const _kSecureUserId = 'keel_user_id';
const _kSecureEmail = 'keel_email';
const _kSecurePlan = 'keel_plan';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

enum SyncStatus { idle, syncing, error, success }

class SyncProvider extends ChangeNotifier {
  // In-memory auth state — never persisted to disk
  String? _accessToken;
  String? _refreshToken;
  String? _userId;
  String? _plan;

  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  // Per-entity sync state. Sync is account-wide for auth, but each
  // project/programme is a separate server slot, so "last synced" and
  // "has pending changes" are tracked per entity id — switching the
  // current project shows that entity's own state, not whatever was
  // synced most recently.
  final Map<String, DateTime> _lastSyncByProject = {};
  final Map<String, DateTime> _lastChangeByProject = {};
  bool _importing = false; // suppresses markLocalChange during pull

  // Persisted settings (loaded/saved by caller via SettingsProvider)
  String serverUrl = 'https://sync.keel-app.dev';
  bool syncEnabled = false;
  String? email;

  // --- Getters ---

  bool get isAuthenticated => _accessToken != null && _userId != null;
  /// In-memory access token — exposed so peer services (e.g.
  /// ProgrammeLinksDao) can call sync endpoints without re-doing the
  /// auth dance. Null when the user isn't signed in.
  String? get accessToken => _accessToken;
  String? get userId => _userId;
  String? get plan => _plan;
  String? get userEmail => email;
  SyncStatus get status => _status;
  String? get lastError => _lastError;

  /// When [projectId] was last synced to the server, or null if never
  /// (or no project is selected).
  DateTime? lastSyncAtFor(String? projectId) =>
      projectId == null ? null : _lastSyncByProject[projectId];

  /// True when [projectId] has local edits made since its last sync and
  /// the user is authenticated. Per-entity so the project's pending
  /// state doesn't bleed into the programme (or vice versa).
  bool hasPendingChangesFor(String? projectId) {
    if (!isAuthenticated || projectId == null) return false;
    return pendingFrom(
        _lastChangeByProject[projectId], _lastSyncByProject[projectId]);
  }

  /// Pure pending-state rule: there are unsynced changes when a change
  /// exists and it's newer than the last sync (or there's been no sync).
  /// Extracted so it can be unit-tested without faking auth.
  static bool pendingFrom(DateTime? lastChange, DateTime? lastSync) {
    if (lastChange == null) return false;
    if (lastSync == null) return true;
    return lastChange.isAfter(lastSync);
  }

  /// Records a local edit against [projectId] (the entity currently
  /// being viewed). No-op during pull import and when no project is in
  /// context.
  void markLocalChange(String? projectId) {
    if (_importing) return; // don't flag pull-imported data as a local change
    if (projectId == null) return;
    _lastChangeByProject[projectId] = DateTime.now();
    notifyListeners();
    _saveTimestamps();
  }

  /// Serialises an id→timestamp map to a JSON string for SharedPreferences.
  static String encodeTimestamps(Map<String, DateTime> m) => jsonEncode(
      m.map((k, v) => MapEntry(k, v.toIso8601String())));

  /// Inverse of [encodeTimestamps]. Tolerates null/blank/garbage by
  /// returning an empty map, so a corrupt pref never crashes startup.
  static Map<String, DateTime> decodeTimestamps(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, DateTime>{};
      decoded.forEach((k, v) {
        final dt = DateTime.tryParse(v as String);
        if (dt != null) out[k] = dt;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'keel_sync_lastSyncByProject', encodeTimestamps(_lastSyncByProject));
    await prefs.setString('keel_sync_lastChangeByProject',
        encodeTimestamps(_lastChangeByProject));
  }

  Future<void> loadTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSyncByProject
      ..clear()
      ..addAll(decodeTimestamps(prefs.getString('keel_sync_lastSyncByProject')));
    _lastChangeByProject
      ..clear()
      ..addAll(
          decodeTimestamps(prefs.getString('keel_sync_lastChangeByProject')));
    notifyListeners();
  }

  SyncClient? _client;

  SyncClient _getClient() {
    if (_client == null || _client!.baseUrl != serverUrl) {
      _client?.dispose();
      _client = SyncClient(baseUrl: serverUrl);
    }
    return _client!;
  }

  // --- Auth ---

  Future<void> register(
    String userEmail,
    String password,
    AppDatabase db,
    String projectId,
  ) async {
    _setStatus(SyncStatus.syncing);
    try {
      final tokens = await _getClient().register(userEmail, password);
      _applyTokens(tokens, userEmail);
      notifyListeners();
      _setStatus(SyncStatus.success);
    } on SyncApiException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> login(String userEmail, String password) async {
    _setStatus(SyncStatus.syncing);
    try {
      final tokens = await _getClient().login(userEmail, password);
      _applyTokens(tokens, userEmail);
      _setStatus(SyncStatus.success);
    } on SyncApiException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    _plan = null;
    _status = SyncStatus.idle;
    _lastError = null;
    _lastSyncByProject.clear();
    _lastChangeByProject.clear();
    await _clearStoredSession();
    notifyListeners();
  }

  // --- Sync ---

  /// Exports [projectId] to JSON, encrypts it, and pushes to the server.
  /// [encryptionPassword] is used to derive the AES key via Argon2id.
  Future<void> syncProject(
    String projectId,
    String encryptionPassword,
    AppDatabase db,
  ) async {
    if (!isAuthenticated) {
      _setError('Not authenticated');
      return;
    }
    _setStatus(SyncStatus.syncing);
    try {
      final token = await _ensureValidToken();
      final uid = _userId!;

      // Ensure the project record exists on the server
      final projects = await _getClient().listProjects(token);
      final exists = projects.any((p) => p.id == projectId);
      if (!exists) {
        final project = await db.projectDao.getProjectById(projectId);
        if (project == null) throw Exception('Project not found in local DB');
        await _getClient().createProject(token, projectId, project.name);
      }

      // Export to JSON string
      final jsonStr = await JsonExporter.exportProjectToString(
          projectId: projectId, db: db);

      // Derive key and encrypt
      final key = await EncryptionService.deriveKey(encryptionPassword, uid);
      final encryptedBlob = await EncryptionService.encrypt(key, jsonStr);

      // Push to server
      final updatedAt =
          await _getClient().pushSync(token, projectId, encryptedBlob);
      _lastSyncByProject[projectId] = updatedAt;
      _saveTimestamps();
      // Cascade rides on the same sync gesture: replay escalated items /
      // cascaded data up to (or down from) any linked programme. Separate
      // channel from the project blob above, best-effort, never blocks.
      await _reconcileCascade(projectId, token, db);
      _setStatus(SyncStatus.success);
    } on SyncApiException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    }
  }

  /// Pulls encrypted data from the server, decrypts it, and imports into local DB.
  Future<void> pullProject(
    String projectId,
    String encryptionPassword,
    AppDatabase db,
  ) async {
    if (!isAuthenticated) {
      _setError('Not authenticated');
      return;
    }
    _setStatus(SyncStatus.syncing);
    try {
      final token = await _ensureValidToken();
      final uid = _userId!;

      final result = await _getClient().pullSync(token, projectId);

      final key = await EncryptionService.deriveKey(encryptionPassword, uid);
      final jsonStr =
          await EncryptionService.decrypt(key, result.encryptedBase64);

      _importing = true;
      try {
        await JsonImporter.importFromString(jsonStr, db);
      } finally {
        _importing = false;
      }
      _lastSyncByProject[projectId] = result.updatedAt;
      // Align local-change timestamp so pull doesn't look like pending changes
      _lastChangeByProject[projectId] = result.updatedAt;
      _saveTimestamps();
      // Reconcile cascade too — a programme pulling its own blob also wants
      // the latest cascaded items from its linked projects in the same go.
      await _reconcileCascade(projectId, token, db);
      _setStatus(SyncStatus.success);
    } on SyncApiException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    }
  }

  /// Best-effort cascade reconcile run as part of a project sync/pull.
  /// Activates any freshly-paired links, then pushes this project's
  /// escalated/cascade-eligible content up to linked programmes (project
  /// side) or pulls cascaded items down (programme side). Wrapped so a
  /// cascade hiccup never flips the core project sync into an error.
  Future<void> _reconcileCascade(
    String projectId,
    String token,
    AppDatabase db,
  ) async {
    final client = _getClient();
    final cascade = CascadeService(
      db,
      gateway: SyncCascadeGateway(client: client, accessToken: token),
    );
    try {
      await reconcileCascade(
        db: db,
        cascade: cascade,
        projectId: projectId,
        linksGateway: SyncLinksGateway(client: client, accessToken: token),
        remoteUserId: _userId,
      );
    } catch (_) {
      // Best-effort — canonical data lives locally; next sync retries.
    }
  }

  /// Reconciles cascade for [projectId] outside of a blob sync. Needed
  /// because a programme that hasn't been pushed to the server yet still
  /// has to pull escalated items down from its links — the blob Pull
  /// can't target it, but cascade lives on a separate link channel.
  /// Best-effort; no-op when not authenticated.
  Future<void> reconcileCascadeNow(String projectId, AppDatabase db) async {
    if (!isAuthenticated) return;
    final String token;
    try {
      token = await _ensureValidToken();
    } catch (_) {
      return;
    }
    await _reconcileCascade(projectId, token, db);
  }

  /// Chooses which server project a Pull should import. Prefers the
  /// project the user is currently viewing ([currentId]); falls back to
  /// the first server project only when that id isn't on the server
  /// (e.g. a seeded demo with a non-UUID id, or a device that hasn't
  /// pushed yet). Pulling the wrong entity clears + re-imports it, so
  /// getting this right avoids clobbering an unrelated project.
  ///
  /// [serverProjects] must be non-empty.
  static String resolvePullTarget(
    String? currentId,
    List<ProjectSummary> serverProjects,
  ) {
    return serverProjects.any((p) => p.id == currentId)
        ? currentId!
        : serverProjects.first.id;
  }

  /// Lists projects from the server. Returns empty list on error.
  Future<List<ProjectSummary>> listServerProjects() async {
    if (!isAuthenticated) return [];
    try {
      final token = await _ensureValidToken();
      return await _getClient().listProjects(token);
    } catch (_) {
      return [];
    }
  }

  /// Returns a Stripe Checkout URL for new subscribers (free → Solo).
  Future<String?> getCheckoutUrl() async {
    if (!isAuthenticated) return null;
    try {
      final token = await _ensureValidToken();
      return await _getClient().getCheckoutUrl(token);
    } catch (_) {
      return null;
    }
  }

  /// Fetches the Stripe billing portal URL for existing subscribers.
  Future<String?> getBillingPortalUrl() async {
    if (!isAuthenticated) return null;
    try {
      final token = await _ensureValidToken();
      return await _getClient().getBillingPortalUrl(token);
    } catch (_) {
      return null;
    }
  }

  // --- Persistence helpers (called by SettingsProvider integration) ---

  Map<String, dynamic> toSettingsJson() => {
        'syncServerUrl': serverUrl,
        'syncEnabled': syncEnabled,
        'syncEmail': email ?? '',
        // Per-entity sync timestamps live in SharedPreferences
        // (see loadTimestamps); only config belongs in settings JSON.
      };

  void loadFromSettings(Map<String, dynamic> json) {
    serverUrl = json['syncServerUrl'] as String? ?? 'https://sync.keel-app.dev';
    syncEnabled = json['syncEnabled'] as bool? ?? false;
    email = json['syncEmail'] as String? ?? '';
    if (email!.isEmpty) email = null;
    // Do not load tokens from settings — security boundary
  }

  // --- Private helpers ---

  void _applyTokens(AuthTokens tokens, String userEmail) {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
    _userId = tokens.userId;
    _plan = tokens.plan;
    email = userEmail;
    _persistSession(tokens.refreshToken, tokens.userId, userEmail, tokens.plan);
  }

  Future<void> _persistSession(
      String refreshToken, String userId, String userEmail, String plan) async {
    await _secureStorage.write(key: _kSecureRefreshToken, value: refreshToken);
    await _secureStorage.write(key: _kSecureUserId, value: userId);
    await _secureStorage.write(key: _kSecureEmail, value: userEmail);
    await _secureStorage.write(key: _kSecurePlan, value: plan);
  }

  /// Called on app startup. Silently restores session using the stored refresh
  /// token. Returns true if session was successfully restored.
  Future<bool> tryRestoreSession() async {
    try {
      final storedRefreshToken =
          await _secureStorage.read(key: _kSecureRefreshToken);
      if (storedRefreshToken == null) return false;

      final storedUserId = await _secureStorage.read(key: _kSecureUserId) ?? '';
      final storedEmail = await _secureStorage.read(key: _kSecureEmail) ?? '';
      final storedPlan = await _secureStorage.read(key: _kSecurePlan) ?? 'free';

      final newAccessToken = await _getClient().refresh(storedRefreshToken);

      _accessToken = newAccessToken;
      _refreshToken = storedRefreshToken;
      _userId = storedUserId;
      _plan = storedPlan;
      email = storedEmail.isEmpty ? null : storedEmail;
      notifyListeners();
      return true;
    } catch (_) {
      // Refresh failed — token expired or revoked; clear stored session
      await _clearStoredSession();
      return false;
    }
  }

  Future<void> _clearStoredSession() async {
    await _secureStorage.delete(key: _kSecureRefreshToken);
    await _secureStorage.delete(key: _kSecureUserId);
    await _secureStorage.delete(key: _kSecureEmail);
    await _secureStorage.delete(key: _kSecurePlan);
  }

  /// Ensures we have a valid access token; refreshes if needed.
  Future<String> _ensureValidToken() async {
    if (_accessToken == null) throw Exception('Not authenticated');
    // Try a quick token validity check by inspecting exp claim
    if (_isTokenExpired(_accessToken!)) {
      if (_refreshToken == null) throw Exception('Session expired, please log in again');
      final newAccess = await _getClient().refresh(_refreshToken!);
      _accessToken = newAccess;
      notifyListeners();
    }
    return _accessToken!;
  }

  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = parts[1];
      // Pad base64 to a multiple of 4
      final padded = payload + '=' * ((4 - payload.length % 4) % 4);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      final exp = decoded['exp'] as int?;
      if (exp == null) return false;
      // Expire 60s early to avoid race conditions
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp - 60;
    } catch (_) {
      return true;
    }
  }

  void _setStatus(SyncStatus s) {
    _status = s;
    if (s != SyncStatus.error) _lastError = null;
    notifyListeners();
  }

  void _setError(String msg) {
    _status = SyncStatus.error;
    _lastError = msg;
    debugPrint('SyncProvider error: $msg');
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}
