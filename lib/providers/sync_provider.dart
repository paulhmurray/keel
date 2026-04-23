import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/database/database.dart';
import '../core/export/json_exporter.dart';
import '../core/import/json_importer.dart';
import '../core/sync/encryption_service.dart';
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
  DateTime? _lastSyncAt;
  DateTime? _lastLocalChangeAt;
  bool _importing = false; // suppresses markLocalChange during pull

  // Persisted settings (loaded/saved by caller via SettingsProvider)
  String serverUrl = 'https://sync.keel-app.dev';
  bool syncEnabled = false;
  String? email;

  // --- Getters ---

  bool get isAuthenticated => _accessToken != null && _userId != null;
  String? get userId => _userId;
  String? get plan => _plan;
  String? get userEmail => email;
  SyncStatus get status => _status;
  String? get lastError => _lastError;
  DateTime? get lastSyncAt => _lastSyncAt;

  /// True when the user has unsynced local changes and is authenticated.
  bool get hasPendingChanges {
    if (!isAuthenticated) return false;
    if (_lastLocalChangeAt == null) return false;
    if (_lastSyncAt == null) return true;
    return _lastLocalChangeAt!.isAfter(_lastSyncAt!);
  }

  void markLocalChange() {
    if (_importing) return; // don't flag pull-imported data as a local change
    _lastLocalChangeAt = DateTime.now();
    notifyListeners();
    _saveTimestamps();
  }

  Future<void> _saveTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    if (_lastLocalChangeAt != null) {
      await prefs.setString('keel_sync_lastLocalChangeAt', _lastLocalChangeAt!.toIso8601String());
    }
    if (_lastSyncAt != null) {
      await prefs.setString('keel_sync_lastSyncAt', _lastSyncAt!.toIso8601String());
    }
  }

  Future<void> loadTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    final changeStr = prefs.getString('keel_sync_lastLocalChangeAt') ?? '';
    final syncStr = prefs.getString('keel_sync_lastSyncAt') ?? '';
    _lastLocalChangeAt = changeStr.isNotEmpty ? DateTime.tryParse(changeStr) : null;
    _lastSyncAt = syncStr.isNotEmpty ? DateTime.tryParse(syncStr) : null;
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
    _lastSyncAt = null;
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
      _lastSyncAt = updatedAt;
      _saveTimestamps();
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
      _lastSyncAt = result.updatedAt;
      // Align local-change timestamp so pull doesn't look like pending changes
      _lastLocalChangeAt = _lastSyncAt;
      _saveTimestamps();
      _setStatus(SyncStatus.success);
    } on SyncApiException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError(e.toString());
    }
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
        'lastSyncAt': _lastSyncAt?.toIso8601String() ?? '',
        'lastLocalChangeAt': _lastLocalChangeAt?.toIso8601String() ?? '',
      };

  void loadFromSettings(Map<String, dynamic> json) {
    serverUrl = json['syncServerUrl'] as String? ?? 'https://sync.keel-app.dev';
    syncEnabled = json['syncEnabled'] as bool? ?? false;
    email = json['syncEmail'] as String? ?? '';
    if (email!.isEmpty) email = null;
    final lastSyncStr = json['lastSyncAt'] as String? ?? '';
    _lastSyncAt = lastSyncStr.isNotEmpty ? DateTime.tryParse(lastSyncStr) : null;
    final lastChangeStr = json['lastLocalChangeAt'] as String? ?? '';
    _lastLocalChangeAt = lastChangeStr.isNotEmpty ? DateTime.tryParse(lastChangeStr) : null;
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
