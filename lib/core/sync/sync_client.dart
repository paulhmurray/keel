import 'dart:convert';
import 'package:http/http.dart' as http;

class SyncApiException implements Exception {
  final int statusCode;
  final String message;

  const SyncApiException(this.statusCode, this.message);

  @override
  String toString() => 'SyncApiException($statusCode): $message';
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String userId;
  final String plan;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.plan,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      userId: json['user_id'] as String,
      plan: json['plan'] as String,
    );
  }
}

class ProjectSummary {
  final String id;
  final String name;
  final DateTime updatedAt;

  const ProjectSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  factory ProjectSummary.fromJson(Map<String, dynamic> json) {
    return ProjectSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// HTTP client wrapping the Keel sync server API.
/// The caller (SyncProvider) manages token state and passes it in.
class SyncClient {
  final String baseUrl;
  final http.Client _client;

  SyncClient({required this.baseUrl, http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  void dispose() => _client.close();

  Map<String, String> _authHeaders(String accessToken) => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  void _checkStatus(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      message = body['error'] as String? ?? response.body;
    } catch (_) {
      message = response.body;
    }
    throw SyncApiException(response.statusCode, message);
  }

  /// POST /auth/register
  Future<AuthTokens> register(String email, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    _checkStatus(response);
    return AuthTokens.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// POST /auth/login
  Future<AuthTokens> login(String email, String password) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    _checkStatus(response);
    return AuthTokens.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// POST /auth/refresh — exchanges refresh token for new access token
  Future<String> refresh(String refreshToken) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {
        'Authorization': 'Bearer $refreshToken',
        'Content-Type': 'application/json',
      },
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['access_token'] as String;
  }

  /// GET /projects — list project summaries (no encrypted_data)
  Future<List<ProjectSummary>> listProjects(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/projects'),
      headers: _authHeaders(accessToken),
    );
    _checkStatus(response);
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => ProjectSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /projects — register a project by client UUID
  Future<void> createProject(
      String accessToken, String projectId, String name) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/projects'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'id': projectId, 'name': name}),
    );
    _checkStatus(response);
  }

  /// POST /projects/:id/sync — push encrypted payload
  /// [encryptedBase64] is base64(nonce + ciphertext) as produced by EncryptionService
  Future<DateTime> pushSync(
      String accessToken, String projectId, String encryptedBase64) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/projects/$projectId/sync'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/octet-stream',
      },
      body: encryptedBase64,
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return DateTime.parse(body['updated_at'] as String);
  }

  /// GET /projects/:id/sync — pull encrypted payload
  /// Returns base64-encoded encrypted blob and server updated_at
  Future<({String encryptedBase64, DateTime updatedAt})> pullSync(
      String accessToken, String projectId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/projects/$projectId/sync'),
      headers: _authHeaders(accessToken),
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      encryptedBase64: body['encrypted_data'] as String,
      updatedAt: DateTime.parse(body['updated_at'] as String),
    );
  }

  /// GET /billing/portal — returns Stripe portal URL
  Future<String> getBillingPortalUrl(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/billing/portal'),
      headers: _authHeaders(accessToken),
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['url'] as String;
  }
}
