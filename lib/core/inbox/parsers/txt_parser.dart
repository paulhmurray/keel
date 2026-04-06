import '../inbox_item_draft.dart';

/// Parses plain text (.txt) content into a list of [InboxItemDraft] objects.
///
/// Rules:
/// - Lines starting with "TODO:", "ACTION:", "RISK:", "DECISION:", "ISSUE:"
///   (case-insensitive) become typed items.
/// - Lines with "[ ]" or "- [ ]" become todos.
/// - Lines with "[x]" or "- [x]" are skipped (completed).
/// - @name or "Owner: Name" patterns are used for person detection.
/// - Unrecognised non-empty lines become type 'note'.
class TxtParser {
  static final _ownerPrefixRe = RegExp(r'Owner:\s*([^\n,;]+)', caseSensitive: false);
  static final _atNameRe = RegExp(r'@([A-Za-z][A-Za-z0-9_.-]*)');

  /// Parses [content] and returns a list of draft items.
  /// [sourceLabel] is stored in parsedData for traceability.
  List<InboxItemDraft> parse(String content, {String sourceLabel = ''}) {
    final drafts = <InboxItemDraft>[];

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Skip completed checkboxes
      if (_isCompletedCheckbox(line)) continue;

      final draft = _parseLine(line, sourceLabel: sourceLabel);
      if (draft != null) drafts.add(draft);
    }

    return drafts;
  }

  bool _isCompletedCheckbox(String line) {
    return RegExp(r'^-?\s*\[x\]', caseSensitive: false).hasMatch(line);
  }

  InboxItemDraft? _parseLine(String line, {String sourceLabel = ''}) {
    // Open checkbox — todo
    if (RegExp(r'^-?\s*\[\s*\]').hasMatch(line)) {
      final text = line.replaceFirst(RegExp(r'^-?\s*\[\s*\]\s*'), '').trim();
      if (text.isEmpty) return null;
      final person = _detectPerson(line);
      return InboxItemDraft(
        rawText: text,
        parsedType: 'todo',
        parsedData: _baseData(text, sourceLabel),
        suggestedPersonName: person,
      );
    }

    // Keyword-prefixed lines
    final keywordMatch = RegExp(
      r'^(TODO|ACTION|RISK|DECISION|ISSUE)\s*:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(line);
    if (keywordMatch != null) {
      final keyword = keywordMatch.group(1)!.toUpperCase();
      final text = keywordMatch.group(2)!.trim();
      final type = _keywordToType(keyword);
      final person = _detectPerson(line);
      return InboxItemDraft(
        rawText: text,
        parsedType: type,
        parsedData: _typedData(type, text, sourceLabel, person: person),
        suggestedPersonName: person,
      );
    }

    // Plain text — note
    final person = _detectPerson(line);
    return InboxItemDraft(
      rawText: line,
      parsedType: 'note',
      parsedData: _baseData(line, sourceLabel),
      suggestedPersonName: person,
    );
  }

  String _keywordToType(String keyword) {
    switch (keyword) {
      case 'TODO':
        return 'todo';
      case 'ACTION':
        return 'action';
      case 'RISK':
        return 'risk';
      case 'DECISION':
        return 'decision';
      case 'ISSUE':
        return 'note';
      default:
        return 'note';
    }
  }

  String? _detectPerson(String line) {
    // Check "Owner: Name" first
    final ownerMatch = _ownerPrefixRe.firstMatch(line);
    if (ownerMatch != null) {
      final name = ownerMatch.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    // Check @name
    final atMatch = _atNameRe.firstMatch(line);
    if (atMatch != null) {
      return atMatch.group(1)?.trim();
    }
    return null;
  }

  Map<String, dynamic> _baseData(String text, String source) {
    return {
      'description': text,
      if (source.isNotEmpty) 'source_label': source,
    };
  }

  Map<String, dynamic> _typedData(
    String type,
    String text,
    String source, {
    String? person,
  }) {
    final base = <String, dynamic>{
      'description': text,
      if (source.isNotEmpty) 'source_label': source,
    };
    switch (type) {
      case 'risk':
        return {...base, 'likelihood': 'medium', 'impact': 'medium', 'status': 'open'};
      case 'decision':
        return {
          ...base,
          'status': 'pending',
          if (person != null) 'decision_maker': person,
        };
      case 'action':
      case 'todo':
        return {
          ...base,
          'status': 'open',
          if (person != null) 'owner': person,
        };
      default:
        return base;
    }
  }
}
