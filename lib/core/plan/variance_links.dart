/// Parsing/encoding for a plan item's variance RAID links — the (up to
/// five) RAID items that drive a schedule scenario spread. Stored as a
/// JSON array of {"type": ..., "id": ...} on
/// TimelineActivities.varianceRaidLinksJson; the legacy single-link
/// columns are kept in sync with the first entry for older readers.
library;

import 'dart:convert';

const kMaxVarianceLinks = 5;

typedef VarianceLink = ({String type, String id});

List<VarianceLink> parseVarianceLinks(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final raw = jsonDecode(json) as List;
    return [
      for (final e in raw)
        if (e is Map && e['type'] is String && e['id'] is String)
          (type: e['type'] as String, id: e['id'] as String),
    ];
  } catch (_) {
    return const [];
  }
}

String encodeVarianceLinks(List<VarianceLink> links) {
  return jsonEncode([
    for (final l in links.take(kMaxVarianceLinks))
      {'type': l.type, 'id': l.id},
  ]);
}

/// The effective links for an activity: the JSON list when present,
/// else the legacy single-link columns (pre-v57 rows).
List<VarianceLink> effectiveVarianceLinks({
  required String? linksJson,
  required String? legacyType,
  required String? legacyId,
}) {
  final parsed = parseVarianceLinks(linksJson);
  if (parsed.isNotEmpty) return parsed;
  if (legacyId != null) {
    return [(type: legacyType ?? 'risk', id: legacyId)];
  }
  return const [];
}
