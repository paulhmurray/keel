import '../inbox_item_draft.dart';

/// Parses Markdown (.md) content into a list of [InboxItemDraft] objects.
///
/// Rules:
/// - `- [ ] text` → todo
/// - `- [x] text` → skip (done)
/// - `**RISK:** text` or `> RISK: text` → risk
/// - `**DECISION:** text` → decision
/// - `**ACTION:** text` or `**TODO:** text` → action
/// - Headings (`#`, `##`, etc.) → context notes
/// - @name or "Owner: Name" → person detection
class MdParser {
  static final _ownerPrefixRe = RegExp(r'Owner:\s*([^\n,;]+)', caseSensitive: false);
  static final _atNameRe = RegExp(r'@([A-Za-z][A-Za-z0-9_.-]*)');

  List<InboxItemDraft> parse(String content, {String sourceLabel = ''}) {
    final drafts = <InboxItemDraft>[];

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final draft = _parseLine(line, sourceLabel: sourceLabel);
      if (draft != null) drafts.add(draft);
    }

    return drafts;
  }

  InboxItemDraft? _parseLine(String line, {String sourceLabel = ''}) {
    // Completed checkbox — skip
    if (RegExp(r'^-\s*\[x\]', caseSensitive: false).hasMatch(line)) {
      return null;
    }

    // Open checkbox — todo
    if (RegExp(r'^-\s*\[\s*\]').hasMatch(line)) {
      final text = line.replaceFirst(RegExp(r'^-\s*\[\s*\]\s*'), '').trim();
      if (text.isEmpty) return null;
      final person = _detectPerson(text);
      return InboxItemDraft(
        rawText: text,
        parsedType: 'todo',
        parsedData: {
          'description': text,
          'status': 'open',
          if (person != null) 'owner': person,
          if (sourceLabel.isNotEmpty) 'source_label': sourceLabel,
        },
        suggestedPersonName: person,
      );
    }

    // Bold keyword patterns: **RISK:** text, **DECISION:** text, etc.
    final boldKeyword = RegExp(
      r'^\*\*(RISK|DECISION|ACTION|TODO|ISSUE)\s*:?\*\*\s*(.+)',
      caseSensitive: false,
    ).firstMatch(line);
    if (boldKeyword != null) {
      final keyword = boldKeyword.group(1)!.toUpperCase();
      final text = boldKeyword.group(2)!.trim();
      final type = _keywordToType(keyword);
      final person = _detectPerson(text);
      return InboxItemDraft(
        rawText: text,
        parsedType: type,
        parsedData: _typedData(type, text, sourceLabel, person: person),
        suggestedPersonName: person,
      );
    }

    // Blockquote keyword: > RISK: text, > DECISION: text, etc.
    final blockquoteKeyword = RegExp(
      r'^>\s*(RISK|DECISION|ACTION|TODO|ISSUE)\s*:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(line);
    if (blockquoteKeyword != null) {
      final keyword = blockquoteKeyword.group(1)!.toUpperCase();
      final text = blockquoteKeyword.group(2)!.trim();
      final type = _keywordToType(keyword);
      final person = _detectPerson(text);
      return InboxItemDraft(
        rawText: text,
        parsedType: type,
        parsedData: _typedData(type, text, sourceLabel, person: person),
        suggestedPersonName: person,
      );
    }

    // Headings — context
    final headingMatch = RegExp(r'^(#{1,6})\s+(.+)').firstMatch(line);
    if (headingMatch != null) {
      final text = headingMatch.group(2)!.trim();
      return InboxItemDraft(
        rawText: text,
        parsedType: 'context',
        parsedData: {
          'title': text,
          'description': text,
          if (sourceLabel.isNotEmpty) 'source_label': sourceLabel,
        },
        suggestedPersonName: null,
      );
    }

    // Plain list items: `- text` or `* text` (not checkboxes)
    final listItemMatch = RegExp(r'^[-*]\s+(.+)').firstMatch(line);
    if (listItemMatch != null) {
      final text = listItemMatch.group(1)!.trim();
      if (text.isEmpty) return null;
      // Check for inline keyword like "RISK: ..."
      final inlineKeyword = RegExp(
        r'^(RISK|DECISION|ACTION|TODO|ISSUE)\s*:\s*(.+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (inlineKeyword != null) {
        final keyword = inlineKeyword.group(1)!.toUpperCase();
        final kText = inlineKeyword.group(2)!.trim();
        final type = _keywordToType(keyword);
        final person = _detectPerson(kText);
        return InboxItemDraft(
          rawText: kText,
          parsedType: type,
          parsedData: _typedData(type, kText, sourceLabel, person: person),
          suggestedPersonName: person,
        );
      }
      final person = _detectPerson(text);
      return InboxItemDraft(
        rawText: text,
        parsedType: 'note',
        parsedData: {
          'description': text,
          if (person != null) 'owner': person,
          if (sourceLabel.isNotEmpty) 'source_label': sourceLabel,
        },
        suggestedPersonName: person,
      );
    }

    // Everything else — note
    final person = _detectPerson(line);
    return InboxItemDraft(
      rawText: line,
      parsedType: 'note',
      parsedData: {
        'description': line,
        if (sourceLabel.isNotEmpty) 'source_label': sourceLabel,
      },
      suggestedPersonName: person,
    );
  }

  String _keywordToType(String keyword) {
    switch (keyword) {
      case 'RISK':
        return 'risk';
      case 'DECISION':
        return 'decision';
      case 'ACTION':
      case 'TODO':
        return 'action';
      case 'ISSUE':
        return 'note';
      default:
        return 'note';
    }
  }

  String? _detectPerson(String line) {
    final ownerMatch = _ownerPrefixRe.firstMatch(line);
    if (ownerMatch != null) {
      final name = ownerMatch.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    final atMatch = _atNameRe.firstMatch(line);
    if (atMatch != null) {
      return atMatch.group(1)?.trim();
    }
    return null;
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
