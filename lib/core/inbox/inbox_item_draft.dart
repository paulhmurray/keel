import 'dart:convert';

/// A parsed item from a text/markdown/org file before it's saved to the DB.
class InboxItemDraft {
  final String rawText;

  /// One of: 'todo', 'risk', 'decision', 'action', 'note', 'dependency', 'context'
  final String parsedType;

  /// Pre-filled fields extracted from the source text.
  final Map<String, dynamic> parsedData;

  /// Detected person name from @name or "Owner: Name" patterns.
  final String? suggestedPersonName;

  const InboxItemDraft({
    required this.rawText,
    required this.parsedType,
    this.parsedData = const {},
    this.suggestedPersonName,
  });

  /// Serialises [parsedData] to a JSON string for DB storage.
  String toJsonString() => jsonEncode(parsedData);

  /// Creates a copy with overridden fields.
  InboxItemDraft copyWith({
    String? rawText,
    String? parsedType,
    Map<String, dynamic>? parsedData,
    String? suggestedPersonName,
  }) {
    return InboxItemDraft(
      rawText: rawText ?? this.rawText,
      parsedType: parsedType ?? this.parsedType,
      parsedData: parsedData ?? this.parsedData,
      suggestedPersonName: suggestedPersonName ?? this.suggestedPersonName,
    );
  }

  @override
  String toString() =>
      'InboxItemDraft(type=$parsedType, person=$suggestedPersonName, '
      'text=${rawText.length > 60 ? rawText.substring(0, 60) : rawText})';
}
