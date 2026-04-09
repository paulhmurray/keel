import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/database/database.dart';
import '../core/export/json_exporter.dart';
import '../core/import/json_importer.dart';
import '../core/sync/encryption_service.dart';
import '../core/sync/sync_client.dart';

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

      await JsonImporter.importFromString(jsonStr, db);
      _lastSyncAt = result.updatedAt;
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
