import 'dart:convert';
import '../llm/llm_client.dart';

enum DeltaType { decision, action, risk, issue, dependency, timelineChange }

class DetectedDelta {
  final String id;
  DeltaType type;
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

    // ── Pass 1: Slash-command template patterns ──────────────────────────
    // Unambiguous — the user explicitly tagged these with /action, /decision
    // etc. The templates use **Bold:** prefixes which are not produced by
    // free-form prose, so there are no false positives.

    // /action  →  **Action:** Owner — description — by date
    // The @-prefix on the owner is optional (user may type @name via mention picker).
    // Separator can be em-dash (—) or double-hyphen (--) or plain hyphen.
    final cmdActionRe = RegExp(
      r'^\*\*Action:\*\*\s+@?(.*?)\s+[—\-]{1,2}\s+(.+?)(?:\s+[—\-]{1,2}\s+by\s+(.+?))?$',
      caseSensitive: false,
      multiLine: true,
    );
    for (final m in cmdActionRe.allMatches(body)) {
      final rawOwner = m.group(1)?.trim() ?? '';
      final desc    = m.group(2)?.trim() ?? '';
      final rawDue  = m.group(3)?.trim() ?? '';
      // Skip lines that still contain the placeholder text
      if (desc.isEmpty || desc == 'task') continue;
      final owner = (rawOwner.isEmpty || rawOwner == 'name') ? null : rawOwner;
      final due   = (rawDue.isEmpty   || rawDue   == 'date') ? null : rawDue;
      deltas.add(DetectedDelta(
        id: 'delta_${idx++}',
        type: DeltaType.action,
        title: owner != null ? '$owner: $desc' : desc,
        fields: {'description': desc, 'owner': owner, 'dueDate': due},
      ));
    }

    // /decision  →  **Decision:** description
    //               Decision-maker: name          (optional next line)
    final cmdDecisionRe = RegExp(
      r'^\*\*Decision:\*\*\s+(.+?)$(?:\nDecision-maker:\s*(.+?)$)?',
      caseSensitive: false,
      multiLine: true,
    );
    for (final m in cmdDecisionRe.allMatches(body)) {
      final desc  = m.group(1)?.trim() ?? '';
      final maker = m.group(2)?.trim() ?? '';
      if (desc.isEmpty) continue;
      deltas.add(DetectedDelta(
        id: 'delta_${idx++}',
        type: DeltaType.decision,
        title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
        fields: {
          'description': desc,
          'decisionMaker': maker.isEmpty ? null : maker,
        },
      ));
    }

    // /risk  →  **Risk:** description
    //           Likelihood: medium | Impact: medium   (optional next line)
    final cmdRiskRe = RegExp(
      r'^\*\*Risk:\*\*\s+(.+?)$(?:\nLikelihood:\s*(low|medium|high)\s*\|\s*Impact:\s*(low|medium|high))?',
      caseSensitive: false,
      multiLine: true,
    );
    for (final m in cmdRiskRe.allMatches(body)) {
      final desc       = m.group(1)?.trim() ?? '';
      final likelihood = m.group(2)?.trim() ?? 'medium';
      final impact     = m.group(3)?.trim() ?? 'medium';
      if (desc.isEmpty) continue;
      deltas.add(DetectedDelta(
        id: 'delta_${idx++}',
        type: DeltaType.risk,
        title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
        fields: {
          'description': desc,
          'likelihood': likelihood,
          'impact': impact,
        },
      ));
    }

    // /issue  →  **Issue:** description
    //            Owner: name                        (optional next line)
    final cmdIssueRe = RegExp(
      r'^\*\*Issue:\*\*\s+(.+?)$(?:\nOwner:\s*(.+?)$)?',
      caseSensitive: false,
      multiLine: true,
    );
    for (final m in cmdIssueRe.allMatches(body)) {
      final desc  = m.group(1)?.trim() ?? '';
      final owner = m.group(2)?.trim() ?? '';
      if (desc.isEmpty) continue;
      deltas.add(DetectedDelta(
        id: 'delta_${idx++}',
        type: DeltaType.issue,
        title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
        fields: {
          'description': desc,
          'owner': owner.isEmpty ? null : owner,
          'priority': 'medium',
        },
      ));
    }

    // /dep  →  **Dependency:** description
    //          Owner: name                          (optional next line)
    final cmdDepRe = RegExp(
      r'^\*\*Dependency:\*\*\s+(.+?)$(?:\nOwner:\s*(.+?)$)?',
      caseSensitive: false,
      multiLine: true,
    );
    for (final m in cmdDepRe.allMatches(body)) {
      final desc  = m.group(1)?.trim() ?? '';
      final owner = m.group(2)?.trim() ?? '';
      if (desc.isEmpty) continue;
      deltas.add(DetectedDelta(
        id: 'delta_${idx++}',
        type: DeltaType.dependency,
        title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
        fields: {
          'description': desc,
          'owner': owner.isEmpty ? null : owner,
        },
      ));
    }

    // ── Pass 2: Free-form prose patterns ────────────────────────────────
    // Run on a version of the body with slash-command lines removed to
    // avoid double-detecting the same item.
    final freeFormBody = body
        .split('\n')
        .where((line) => !line.startsWith('**Action:**') &&
                         !line.startsWith('**Decision:**') &&
                         !line.startsWith('**Risk:**') &&
                         !line.startsWith('**Issue:**') &&
                         !line.startsWith('**Dependency:**') &&
                         !line.startsWith('Decision-maker:') &&
                         !line.startsWith('Likelihood:') &&
                         !line.startsWith('Owner:'))
        .join('\n');

    // Action: "Name will/to/shall <task> [by date]"
    final actionRe = RegExp(
      r'(?:^|[,\.] )([A-Z][a-z]+(?:\s[A-Z][a-z]+)?)\s+(?:will|to|shall|needs to|has to)\s+(.+?)(?:\s+by\s+(.+?))?[,\.\n]',
      caseSensitive: false,
    );
    for (final m in actionRe.allMatches(freeFormBody)) {
      final owner = m.group(1)?.trim();
      final desc  = m.group(2)?.trim();
      final due   = m.group(3)?.trim();
      if (desc != null && desc.length > 3) {
        deltas.add(DetectedDelta(
          id: 'delta_${idx++}',
          type: DeltaType.action,
          title: owner != null ? '$owner: $desc' : desc,
          fields: {'description': desc, 'owner': owner, 'dueDate': due},
        ));
      }
    }

    // Decision: "decided / agreed / confirmed / going with / chose …"
    final decisionRe = RegExp(
      r'(?:decided|agreed|confirmed|going with|we will use|chose)\s+(.+?)(?:[,\.\n]|$)',
      caseSensitive: false,
    );
    for (final m in decisionRe.allMatches(freeFormBody)) {
      final desc = m.group(1)?.trim();
      if (desc != null && desc.length > 3) {
        deltas.add(DetectedDelta(
          id: 'delta_${idx++}',
          type: DeltaType.decision,
          title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
          fields: {'description': desc},
        ));
      }
    }

    // Risk: "risk / concern / worried about / at risk / could fail …"
    final riskRe = RegExp(
      r'(?:risk|concern|worried about|may not|at risk|could fail)\s*[:—\-]?\s*(.+?)(?:[,\.\n]|$)',
      caseSensitive: false,
    );
    for (final m in riskRe.allMatches(freeFormBody)) {
      final desc = m.group(1)?.trim();
      if (desc != null && desc.length > 5) {
        deltas.add(DetectedDelta(
          id: 'delta_${idx++}',
          type: DeltaType.risk,
          title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
          fields: {'description': desc, 'likelihood': 'medium', 'impact': 'medium'},
        ));
      }
    }

    // Issue: "blocked / problem / stuck / cannot proceed / issue with …"
    final issueRe = RegExp(
      r"(?:blocked|problem|stuck|cannot proceed|issue with|can't proceed)\s*[:—\-]?\s*(.+?)(?:[,\.\n]|$)",
      caseSensitive: false,
    );
    for (final m in issueRe.allMatches(freeFormBody)) {
      final desc = m.group(1)?.trim();
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
