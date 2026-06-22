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

  /// POST /billing/checkout — returns Stripe Checkout URL for new subscribers
  Future<String> getCheckoutUrl(String accessToken) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/billing/checkout'),
      headers: _authHeaders(accessToken),
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['url'] as String;
  }

  /// GET /billing/portal — returns Stripe portal URL for existing subscribers
  Future<String> getBillingPortalUrl(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/billing/portal'),
      headers: _authHeaders(accessToken),
    );
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['url'] as String;
  }

  // ── Programme links (Phase B) ───────────────────────────────────────────

  /// PUT /links/:code/me — claim our side of a programme ↔ project link.
  /// Returns the full server-side link state (both parties when known,
  /// plus activation timestamp). The server enforces that the two
  /// sides must be a project + a programme (never two of the same
  /// kind), so a 400 here is "kind mismatch".
  Future<RemoteLinkState> claimLinkSide({
    required String accessToken,
    required String code,
    required String entityId,
    required String kind, // 'project' | 'programme'
    required String name,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/links/$code/me'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({
        'entity_id': entityId,
        'kind': kind,
        'name': name,
      }),
    );
    _checkStatus(response);
    return RemoteLinkState.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// GET /links/:code — fetch current link state. Returns null when
  /// the server says 404 (link doesn't exist OR caller isn't a party
  /// to it — the server returns 404 in both cases so codes can't be
  /// enumerated).
  Future<RemoteLinkState?> getLink({
    required String accessToken,
    required String code,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/links/$code'),
      headers: _authHeaders(accessToken),
    );
    if (response.statusCode == 404) return null;
    _checkStatus(response);
    return RemoteLinkState.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// DELETE /links/:code/me — revoke our side. Server-side this either
  /// deletes the row (we were the only party) or downgrades to the
  /// other party + clears activation.
  Future<void> revokeLinkSide({
    required String accessToken,
    required String code,
  }) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/links/$code/me'),
      headers: _authHeaders(accessToken),
    );
    if (response.statusCode == 404) return; // Idempotent.
    _checkStatus(response);
  }

  // ── Cascade items (Phase C) ─────────────────────────────────────────────

  /// PUT /links/:code/items — upsert one cascaded item on the link
  /// channel. The server keys on (kind, item_id) so re-pushes update
  /// in place. Payload shape is opaque to the server.
  Future<void> pushCascadeItem({
    required String accessToken,
    required String code,
    required String sourceEntityId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/links/$code/items'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({
        'source_entity_id': sourceEntityId,
        'item_kind': itemKind,
        'item_id': itemId,
        'payload': payload,
      }),
    );
    _checkStatus(response);
  }

  /// GET /links/:code/items[?since=...] — incremental pull. Pass the
  /// previous response's cursor to receive only newer changes.
  Future<CascadePullResult> pullCascadeItems({
    required String accessToken,
    required String code,
    String? since,
  }) async {
    final uri = since == null
        ? Uri.parse('$baseUrl/links/$code/items')
        : Uri.parse(
            '$baseUrl/links/$code/items?since=${Uri.encodeQueryComponent(since)}');
    final response = await _client.get(uri, headers: _authHeaders(accessToken));
    _checkStatus(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['items'] as List<dynamic>? ?? const [])
        .map((e) =>
            CascadeItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return CascadePullResult(
      items: items,
      cursor: body['cursor'] as String? ?? '',
    );
  }

  /// DELETE /links/:code/items/:kind/:id — soft-tombstone the item on
  /// the channel. The other party sees the deletion as a row with
  /// `deleted=true` on its next pull, allowing local reconciliation.
  Future<void> deleteCascadeItem({
    required String accessToken,
    required String code,
    required String itemKind,
    required String itemId,
  }) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/links/$code/items/$itemKind/$itemId'),
      headers: _authHeaders(accessToken),
    );
    if (response.statusCode == 404) return; // Idempotent.
    _checkStatus(response);
  }
}

/// One cascaded item returned by `GET /links/:code/items`. The
/// [payload] shape is item-kind-specific (work packages send a
/// different shape than e.g. status reports); decoders live in the
/// CascadeService.
class CascadeItem {
  final String sourceEntityId;
  final String itemKind;
  final String itemId;
  final Map<String, dynamic> payload;
  final DateTime updatedAt;
  final bool deleted;

  const CascadeItem({
    required this.sourceEntityId,
    required this.itemKind,
    required this.itemId,
    required this.payload,
    required this.updatedAt,
    required this.deleted,
  });

  factory CascadeItem.fromJson(Map<String, dynamic> json) {
    return CascadeItem(
      sourceEntityId: json['source_entity_id'] as String? ?? '',
      itemKind: json['item_kind'] as String? ?? '',
      itemId: json['item_id'] as String? ?? '',
      payload:
          (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deleted: json['deleted'] as bool? ?? false,
    );
  }
}

class CascadePullResult {
  /// Items changed since the cursor (or everything if none was given).
  final List<CascadeItem> items;

  /// Server cursor for the next call. Echo back as `since=` in the
  /// next pull to fetch only newer rows. Empty when nothing has ever
  /// been pushed on the link.
  final String cursor;

  const CascadePullResult({required this.items, required this.cursor});
}

/// One side of a server-side programme link. Carries enough identity
/// for the client to render the partner without another lookup.
class RemoteLinkSide {
  final String userId;
  final String entityId;
  final String kind;
  final String name;

  const RemoteLinkSide({
    required this.userId,
    required this.entityId,
    required this.kind,
    required this.name,
  });

  factory RemoteLinkSide.fromJson(Map<String, dynamic> json) {
    return RemoteLinkSide(
      userId: json['user_id'] as String? ?? '',
      entityId: json['entity_id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

/// Full server-side state of a programme link. [sideB] is null until
/// the second party has claimed their side; [activatedAt] is set once
/// both sides are present.
class RemoteLinkState {
  final String code;
  final RemoteLinkSide sideA;
  final RemoteLinkSide? sideB;
  final DateTime? activatedAt;
  final DateTime createdAt;

  const RemoteLinkState({
    required this.code,
    required this.sideA,
    required this.sideB,
    required this.activatedAt,
    required this.createdAt,
  });

  bool get isActive => activatedAt != null && sideB != null;

  factory RemoteLinkState.fromJson(Map<String, dynamic> json) {
    final sideBJson = json['side_b'] as Map<String, dynamic>?;
    final activatedAt = json['activated_at'] as String?;
    return RemoteLinkState(
      code: json['code'] as String,
      sideA: RemoteLinkSide.fromJson(
          json['side_a'] as Map<String, dynamic>),
      sideB: sideBJson == null ? null : RemoteLinkSide.fromJson(sideBJson),
      activatedAt: activatedAt == null ? null : DateTime.parse(activatedAt),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Returns the side belonging to a given user, if either matches.
  /// Used by the client to resolve "which one of these is the partner?"
  RemoteLinkSide? partnerForUser(String userId) {
    if (sideA.userId != userId && sideB?.userId != userId) return null;
    return sideA.userId == userId ? sideB : sideA;
  }
}
