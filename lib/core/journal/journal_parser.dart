import 'dart:convert';
import '../llm/llm_client.dart';

enum DeltaType { decision, action, risk, issue, dependency, timelineChange }

class DetectedDelta {
  final String id;
  final DeltaType type;
  final String title;
  final Map<String, String?> fields;
  final String? previousValue;
  bool confirmed;
  bool ignored;
  late Map<String, String?> editFields;

  DetectedDelta({
    required this.id,
    required this.type,
    required this.title,
    required this.fields,
    this.previousValue,
    this.confirmed = false,
    this.ignored = false,
  }) {
    editFields = Map<String, String?>.from(fields);
  }

  String get typeLabel {
    switch (type) {
      case DeltaType.decision: return 'Decision';
      case DeltaType.action: return 'Action';
      case DeltaType.risk: return 'Risk';
      case DeltaType.issue: return 'Issue';
      case DeltaType.dependency: return 'Dependency';
      case DeltaType.timelineChange: return 'Timeline change';
    }
  }

  String get typeIcon {
    switch (type) {
      case DeltaType.decision: return '◇';
      case DeltaType.action: return '✓';
      case DeltaType.risk: return '△';
      case DeltaType.issue: return '⚠';
      case DeltaType.dependency: return '⇒';
      case DeltaType.timelineChange: return '⌇';
    }
  }
}

class JournalParser {
  final LLMClient? llmClient;

  JournalParser({this.llmClient});

  Future<List<DetectedDelta>> parse(String body, {String? projectContext}) async {
    if (body.trim().isEmpty) return [];

    if (llmClient != null) {
      try {
        return await _parsWithLlm(body, projectContext: projectContext);
      } catch (_) {
        // fall through to rule-based
      }
    }
    return _parseWithRules(body);
  }

  Future<List<DetectedDelta>> _parsWithLlm(String body, {String? projectContext}) async {
    final contextStr = projectContext != null ? '\n\nProject context:\n$projectContext' : '';
    final systemPrompt = '''You are a programme management assistant. Extract structured items from meeting notes and programme journal entries.

Respond ONLY with valid JSON in this exact format, no markdown, no explanation:
{
  "items": [
    {
      "type": "action|decision|risk|issue|dependency|timeline_change",
      "title": "brief display title (max 80 chars)",
      "fields": {}
    }
  ]
}

Field schemas per type:
- action: {"description": "...", "owner": "person name or null", "dueDate": "YYYY-MM-DD or null"}
- decision: {"description": "...", "decisionMaker": "person name or null"}
- risk: {"description": "...", "likelihood": "low|medium|high", "impact": "low|medium|high"}
- issue: {"description": "...", "owner": "person name or null", "priority": "low|medium|high"}
- dependency: {"description": "...", "owner": "person name or null"}
- timeline_change: {"description": "...", "item": "milestone/workstream name", "previousDate": "date or null", "newDate": "date or null"}

Rules:
- Only include items clearly implied by the text
- Actions: person + task pattern (e.g. "Sarah to chase...", "Ricki will...")
- Decisions: "decided", "agreed", "confirmed", "going with", "we will use"
- Risks: "risk", "concern", "worried", "may not", "could fail", "at risk"
- Issues: "blocked", "problem", "stuck", "cannot proceed", "issue with"
- Timeline changes: dates shifting, "pushed to", "moved to", "delayed", "slipped"
- If nothing relevant, return {"items": []}
- Maximum 10 items$contextStr''';

    final response = await llmClient!.complete(
      systemPrompt: systemPrompt,
      userMessage: body,
      maxTokens: 1500,
    );

    return _parseJsonResponse(response);
  }

  List<DetectedDelta> _parseJsonResponse(String response) {
    // Strip markdown code blocks if present
    String cleaned = response.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceAll(RegExp(r'^```[a-z]*\n?'), '').replaceAll(RegExp(r'\n?```$'), '').trim();
    }

    final json = jsonDecode(cleaned) as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>? ?? [];
    final deltas = <DetectedDelta>[];
    int idx = 0;

    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final typeStr = map['type'] as String? ?? '';
      final type = _parseType(typeStr);
      if (type == null) continue;

      final fields = (map['fields'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v?.toString()));

      deltas.add(DetectedDelta(
        id: 'delta_${idx++}',
        type: type,
        title: map['title'] as String? ?? fields['description'] ?? 'Item',
        fields: fields,
      ));
    }
    return deltas;
  }

  DeltaType? _parseType(String s) {
    switch (s) {
      case 'action': return DeltaType.action;
      case 'decision': return DeltaType.decision;
      case 'risk': return DeltaType.risk;
      case 'issue': return DeltaType.issue;
      case 'dependency': return DeltaType.dependency;
      case 'timeline_change': return DeltaType.timelineChange;
      default: return null;
    }
  }

  List<DetectedDelta> _parseWithRules(String body) {
    final deltas = <DetectedDelta>[];
    int idx = 0;

    // Action patterns: "Name will/to/shall <task>"
    final actionRegex = RegExp(
      r'(?:^|[,\.] )([A-Z][a-z]+(?:\s[A-Z][a-z]+)?)\s+(?:will|to|shall|needs to|has to)\s+(.+?)(?:\s+by\s+(.+?))?[,\.\n]',
      caseSensitive: false,
    );
    for (final match in actionRegex.allMatches(body)) {
      final owner = match.group(1)?.trim();
      final desc = match.group(2)?.trim();
      final due = match.group(3)?.trim();
      if (desc != null && desc.length > 3) {
        deltas.add(DetectedDelta(
          id: 'delta_${idx++}',
          type: DeltaType.action,
          title: owner != null ? '$owner: $desc' : desc,
          fields: {'description': desc, 'owner': owner, 'dueDate': due},
        ));
      }
    }

    // Decision patterns
    final decisionRegex = RegExp(
      r'(?:decided|agreed|confirmed|going with|we will use|chose)\s+(.+?)(?:[,\.\n]|$)',
      caseSensitive: false,
    );
    for (final match in decisionRegex.allMatches(body)) {
      final desc = match.group(1)?.trim();
      if (desc != null && desc.length > 3) {
        deltas.add(DetectedDelta(
          id: 'delta_${idx++}',
          type: DeltaType.decision,
          title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
          fields: {'description': desc},
        ));
      }
    }

    // Risk patterns
    final riskRegex = RegExp(
      r'(?:risk|concern|worried about|may not|at risk|could fail)\s*[:—-]?\s*(.+?)(?:[,\.\n]|$)',
      caseSensitive: false,
    );
    for (final match in riskRegex.allMatches(body)) {
      final desc = match.group(1)?.trim();
      if (desc != null && desc.length > 5) {
        deltas.add(DetectedDelta(
          id: 'delta_${idx++}',
          type: DeltaType.risk,
          title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
          fields: {'description': desc, 'likelihood': 'medium', 'impact': 'medium'},
        ));
      }
    }

    // Issue patterns
    final issueRegex = RegExp(
      r"(?:blocked|problem|stuck|cannot proceed|issue with|can't proceed)\s*[:—-]?\s*(.+?)(?:[,\.\n]|$)",
      caseSensitive: false,
    );
    for (final match in issueRegex.allMatches(body)) {
      final desc = match.group(1)?.trim();
      if (desc != null && desc.length > 5) {
        deltas.add(DetectedDelta(
          id: 'delta_${idx++}',
          type: DeltaType.issue,
          title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
          fields: {'description': desc, 'priority': 'medium'},
        ));
      }
    }

    return deltas;
  }
}
