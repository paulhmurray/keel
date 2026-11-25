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
      case DeltaType.decision:
        return 'Decision';
      case DeltaType.action:
        return 'Action';
      case DeltaType.risk:
        return 'Risk';
      case DeltaType.issue:
        return 'Issue';
      case DeltaType.dependency:
        return 'Dependency';
      case DeltaType.timelineChange:
        return 'Timeline change';
    }
  }

  String get typeIcon {
    switch (type) {
      case DeltaType.decision:
        return '◇';
      case DeltaType.action:
        return '✓';
      case DeltaType.risk:
        return '△';
      case DeltaType.issue:
        return '⚠';
      case DeltaType.dependency:
        return '⇒';
      case DeltaType.timelineChange:
        return '⌇';
    }
  }
}

class JournalParser {
  final LLMClient? llmClient;

  JournalParser({this.llmClient});

  /// Set by [parse] when an AI parse was attempted and failed, so the
  /// review can say the prose was read by the basic keyword rules instead.
  /// Null when the AI handled the prose, or there was no prose to send.
  String? aiFallbackReason;

  /// Labelled lines (`Action:`, `**Decision:**`, `Risk:` …) are read
  /// deterministically — they are unambiguous, and a note can hold dozens
  /// of them. Only the prose left over goes to the AI (or, without one,
  /// to the keyword rules).
  /// [noteDate] is the note's date — the AI resolves "by Friday" or
  /// "in March" against it (without it, a model guesses the year).
  Future<List<DetectedDelta>> parse(
    String body, {
    String? projectContext,
    DateTime? noteDate,
  }) async {
    aiFallbackReason = null;
    if (body.trim().isEmpty) return [];

    final labelled = parseLabelled(body);
    final prose = labelled.remainder;
    var proseDeltas = <DetectedDelta>[];
    if (prose.trim().isNotEmpty) {
      if (llmClient != null) {
        try {
          proseDeltas = await _parsWithLlm(
            prose,
            projectContext: projectContext,
            noteDate: noteDate ?? DateTime.now(),
          );
        } catch (e) {
          aiFallbackReason = _describeFailure(e);
          proseDeltas = _parseFreeForm(prose);
        }
      } else {
        proseDeltas = _parseFreeForm(prose);
      }
    }
    return _rekey([...labelled.deltas, ...proseDeltas]);
  }

  static String _describeFailure(Object e) {
    if (e is FormatException) return "the AI's reply wasn't readable JSON";
    var msg = e.toString().replaceFirst(RegExp(r'^\w*Exception:\s*'), '');
    if (msg.length > 200) msg = '${msg.substring(0, 197)}...';
    return msg;
  }

  static List<DetectedDelta> _rekey(List<DetectedDelta> deltas) => [
    for (var i = 0; i < deltas.length; i++)
      DetectedDelta(
        id: 'delta_$i',
        type: deltas[i].type,
        title: deltas[i].title,
        fields: deltas[i].fields,
        previousValue: deltas[i].previousValue,
      ),
  ];

  Future<List<DetectedDelta>> _parsWithLlm(
    String body, {
    String? projectContext,
    required DateTime noteDate,
  }) async {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final d = noteDate;
    final iso =
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final contextStr = projectContext != null
        ? '\n\nProject context:\n$projectContext'
        : '';
    final systemPrompt =
        '''You are a programme management assistant. Extract structured items from meeting notes and programme journal entries.

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
- action: {"description": "...", "owner": "person name or null", "dueDate": "the due date exactly as the note words it (e.g. 'Friday', 'end of March', '15 Jan') or null"}
- decision: {"description": "...", "decisionMaker": "person name or null"}
- risk: {"description": "...", "owner": "person name or null", "likelihood": "rare|unlikely|possible|likely|almost certain", "impact": "minimal|minor|moderate|major|severe"}
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
- The note was written on ${days[d.weekday - 1]} $iso. Resolve relative dates ("Friday", "next week", "in March") against that date; never use an earlier year unless the text says so
- If nothing relevant, return {"items": []}$contextStr''';

    final response = await llmClient!.complete(
      systemPrompt: systemPrompt,
      userMessage: body,
      // ~20 items of JSON. A local 14B model writes ~14-22 tokens/s, so
      // this must finish inside Ollama's 180 s non-streaming timeout.
      maxTokens: 2000,
    );

    return _parseJsonResponse(response);
  }

  List<DetectedDelta> _parseJsonResponse(String response) {
    // Strip markdown code blocks if present
    String cleaned = response.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceAll(RegExp(r'^```[a-z]*\n?'), '')
          .replaceAll(RegExp(r'\n?```$'), '')
          .trim();
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

      final fields = (map['fields'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, v?.toString()),
      );

      deltas.add(
        DetectedDelta(
          id: 'delta_${idx++}',
          type: type,
          title: map['title'] as String? ?? fields['description'] ?? 'Item',
          fields: fields,
        ),
      );
    }
    return deltas;
  }

  DeltaType? _parseType(String s) {
    switch (s) {
      case 'action':
        return DeltaType.action;
      case 'decision':
        return DeltaType.decision;
      case 'risk':
        return DeltaType.risk;
      case 'issue':
        return DeltaType.issue;
      case 'dependency':
        return DeltaType.dependency;
      case 'timeline_change':
        return DeltaType.timelineChange;
      default:
        return null;
    }
  }

  // ── Labelled lines ─────────────────────────────────────────────────────
  // `Action: Owner — task — by date`, `Decision: … Decision-maker: name`,
  // `Risk: … Likelihood: x | Impact: y`, `Issue:/Dependency: … Owner: name`.
  // The label may be bold (the slash-command templates) or plain (pasted
  // meeting notes), optionally bulleted. Attributes may trail on the same
  // line or sit on the next non-blank line.

  static final _labelRe = RegExp(
    r'^\s*(?:[-*•]\s+)?(?:\*\*)?(action|decision|risk|issue|dependency)(?:\*\*)?\s*:\s*(?:\*\*)?\s*(.*)$',
    caseSensitive: false,
  );
  static final _makerRe = RegExp(
    r'\bDecision[- ]?maker\s*:\s*(.*)$',
    caseSensitive: false,
  );
  static final _likelihoodRe = RegExp(
    r'\bLikelihood\s*:\s*([^|]*)',
    caseSensitive: false,
  );
  static final _impactRe = RegExp(
    r'\bImpact\s*:\s*([^|]*)',
    caseSensitive: false,
  );
  static final _ownerRe = RegExp(
    r'\bOwner\s*:\s*([^|]*)',
    caseSensitive: false,
  );
  static final _attrLineRe = RegExp(
    r'^\s*(?:Decision[- ]?maker|Likelihood|Impact|Owner)\s*:',
    caseSensitive: false,
  );
  static final _dashRe = RegExp(r'\s+(?:—|–|--?)\s+');
  static const _placeholders = {'name', 'task', 'date', 'maker', 'description'};

  /// A trimmed field value, or null when it's empty or an unfilled template
  /// placeholder (`⟨name⟩`, `name`). Trailing full stops are dropped from
  /// short fields (owner, date) but kept on sentences ([keepStop]).
  static String? _value(String? raw, {bool keepStop = false}) {
    var v = raw?.trim() ?? '';
    while (!keepStop && v.endsWith('.')) {
      v = v.substring(0, v.length - 1).trimRight();
    }
    if (v.isEmpty) return null;
    if (v.startsWith('⟨') && v.endsWith('⟩')) return null;
    if (_placeholders.contains(v.toLowerCase())) return null;
    return v;
  }

  static String _short(String s) =>
      s.length > 80 ? '${s.substring(0, 77)}...' : s;

  /// Reads every labelled line in [body]. [LabelledParse.remainder] is the
  /// body without those lines (or their attribute lines) — the prose.
  static LabelledParse parseLabelled(String body) {
    final lines = body.split(RegExp(r'\r?\n'));
    final consumed = <int>{};
    final deltas = <DetectedDelta>[];

    // The next non-blank line after [i], when it is an attribute line.
    int? attrLineAfter(int i) {
      for (var j = i + 1; j < lines.length; j++) {
        if (lines[j].trim().isEmpty) continue;
        return _attrLineRe.hasMatch(lines[j]) ? j : null;
      }
      return null;
    }

    for (var i = 0; i < lines.length; i++) {
      final m = _labelRe.firstMatch(lines[i]);
      if (m == null) continue;
      final label = m.group(1)!.toLowerCase();
      var text = m.group(2)!.replaceAll('**', '').trim();
      consumed.add(i);

      // Attribute text: trailing on this line, else on the next line.
      String attrs = '';
      final attrRe = switch (label) {
        'decision' => _makerRe,
        'risk' => _likelihoodRe,
        'issue' || 'dependency' => _ownerRe,
        _ => null,
      };
      if (attrRe != null) {
        final start = label == 'risk'
            ? _firstOf(text, [_likelihoodRe, _impactRe, _ownerRe])
            : attrRe.firstMatch(text)?.start;
        if (start != null) {
          attrs = text.substring(start);
          text = text.substring(0, start).trim();
        } else {
          final j = attrLineAfter(i);
          if (j != null) {
            consumed.add(j);
            attrs = lines[j].replaceAll('**', '');
          }
        }
      }

      final desc = _value(text, keepStop: true);
      if (desc == null) continue;

      switch (label) {
        case 'action':
          final parts = desc.split(_dashRe);
          String? owner;
          String? due;
          var rest = parts;
          if (rest.length > 1 && rest.last.toLowerCase().startsWith('by ')) {
            due = _value(rest.last.substring(3));
            rest = rest.sublist(0, rest.length - 1);
          }
          if (rest.length > 1) {
            owner = _value(rest.first.replaceFirst(RegExp(r'^@'), ''));
            rest = rest.sublist(1);
          }
          final task = _value(rest.join(' — '), keepStop: true);
          if (task == null) break;
          deltas.add(
            DetectedDelta(
              id: '',
              type: DeltaType.action,
              title: owner != null ? '$owner: $task' : task,
              fields: {'description': task, 'owner': owner, 'dueDate': due},
            ),
          );
        case 'decision':
          final maker = _value(_makerRe.firstMatch(attrs)?.group(1));
          deltas.add(
            DetectedDelta(
              id: '',
              type: DeltaType.decision,
              title: _short(desc),
              fields: {'description': desc, 'decisionMaker': maker},
            ),
          );
        case 'risk':
          final likelihood = _value(
            _likelihoodRe.firstMatch(attrs)?.group(1),
          )?.toLowerCase();
          final impact = _value(
            _impactRe.firstMatch(attrs)?.group(1),
          )?.toLowerCase();
          deltas.add(
            DetectedDelta(
              id: '',
              type: DeltaType.risk,
              title: _short(desc),
              fields: {
                'description': desc,
                'likelihood': likelihood ?? 'medium',
                'impact': impact ?? 'medium',
                'owner': _value(_ownerRe.firstMatch(attrs)?.group(1)),
              },
            ),
          );
        case 'issue':
          deltas.add(
            DetectedDelta(
              id: '',
              type: DeltaType.issue,
              title: _short(desc),
              fields: {
                'description': desc,
                'owner': _value(_ownerRe.firstMatch(attrs)?.group(1)),
                'priority': 'medium',
              },
            ),
          );
        case 'dependency':
          deltas.add(
            DetectedDelta(
              id: '',
              type: DeltaType.dependency,
              title: _short(desc),
              fields: {
                'description': desc,
                'owner': _value(_ownerRe.firstMatch(attrs)?.group(1)),
              },
            ),
          );
      }
    }

    final remainder = <String>[
      for (var i = 0; i < lines.length; i++)
        if (!consumed.contains(i) && !_attrLineRe.hasMatch(lines[i])) lines[i],
    ].join('\n');
    return LabelledParse(deltas: _rekey(deltas), remainder: remainder);
  }

  static int? _firstOf(String text, List<RegExp> res) {
    int? best;
    for (final re in res) {
      final s = re.firstMatch(text)?.start;
      if (s != null && (best == null || s < best)) best = s;
    }
    return best;
  }

  // ── Free-form prose ────────────────────────────────────────────────────
  // Keyword heuristics — the fallback when there's no AI. Labelled lines
  // never reach here (see [parseLabelled]).
  static List<DetectedDelta> _parseFreeForm(String freeFormBody) {
    final deltas = <DetectedDelta>[];
    int idx = 0;

    // Action: "Name will/to/shall <task> [by date]"
    final actionRe = RegExp(
      r'(?:^|[,\.] )([A-Z][a-z]+(?:\s[A-Z][a-z]+)?)\s+(?:will|to|shall|needs to|has to)\s+(.+?)(?:\s+by\s+(.+?))?[,\.\n]',
      caseSensitive: false,
    );
    for (final m in actionRe.allMatches(freeFormBody)) {
      final owner = m.group(1)?.trim();
      final desc = m.group(2)?.trim();
      final due = m.group(3)?.trim();
      if (desc != null && desc.length > 3) {
        deltas.add(
          DetectedDelta(
            id: 'delta_${idx++}',
            type: DeltaType.action,
            title: owner != null ? '$owner: $desc' : desc,
            fields: {'description': desc, 'owner': owner, 'dueDate': due},
          ),
        );
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
        deltas.add(
          DetectedDelta(
            id: 'delta_${idx++}',
            type: DeltaType.decision,
            title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
            fields: {'description': desc},
          ),
        );
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
        deltas.add(
          DetectedDelta(
            id: 'delta_${idx++}',
            type: DeltaType.risk,
            title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
            fields: {
              'description': desc,
              'likelihood': 'medium',
              'impact': 'medium',
            },
          ),
        );
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
        deltas.add(
          DetectedDelta(
            id: 'delta_${idx++}',
            type: DeltaType.issue,
            title: desc.length > 80 ? '${desc.substring(0, 77)}...' : desc,
            fields: {'description': desc, 'priority': 'medium'},
          ),
        );
      }
    }

    return deltas;
  }
}

class LabelledParse {
  final List<DetectedDelta> deltas;
  final String remainder;
  const LabelledParse({required this.deltas, required this.remainder});
}
