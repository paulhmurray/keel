import '../inbox_item_draft.dart';

/// Parses Org-mode (.org) content into a list of [InboxItemDraft] objects.
///
/// Rules:
/// - `* TODO text` → action/todo
/// - `* DONE text` → skip
/// - `* RISK text` or heading containing RISK → risk
/// - `* DECISION text` → decision
/// - `SCHEDULED: <date>` → extract as due_date in parsedData
/// - `:PROPERTIES:` ... `:END:` → extract :OWNER: or :ASSIGNEE:
/// - Plain list items `- text` → note
/// - `** Subheading` → context
class OrgParser {
  static final _atNameRe = RegExp(r'@([A-Za-z][A-Za-z0-9_.-]*)');
  static final _scheduledRe = RegExp(r'SCHEDULED:\s*<([0-9]{4}-[0-9]{2}-[0-9]{2})');
  static final _deadlineRe = RegExp(r'DEADLINE:\s*<([0-9]{4}-[0-9]{2}-[0-9]{2})');
  static final _propOwnerRe = RegExp(r':(?:OWNER|ASSIGNEE):\s*(.+)', caseSensitive: false);

  List<InboxItemDraft> parse(String content, {String sourceLabel = ''}) {
    final drafts = <InboxItemDraft>[];
    final lines = content.split('\n');

    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();

      if (line.isEmpty) {
        i++;
        continue;
      }

      // Heading lines: start with one or more *
      final headingMatch = RegExp(r'^(\*+)\s+(.+)').firstMatch(line);
      if (headingMatch != null) {
        final stars = headingMatch.group(1)!.length;
        final rest = headingMatch.group(2)!.trim();

        // Look ahead for SCHEDULED/DEADLINE and PROPERTIES block
        String? scheduledDate;
        String? deadlineDate;
        String? propertyOwner;

        int j = i + 1;
        bool inProperties = false;
        while (j < lines.length) {
          final nextLine = lines[j].trim();
          // Stop if we hit another heading
          if (RegExp(r'^\*+\s').hasMatch(nextLine)) break;

          if (nextLine == ':PROPERTIES:') {
            inProperties = true;
            j++;
            continue;
          }
          if (nextLine == ':END:') {
            inProperties = false;
            j++;
            continue;
          }

          if (inProperties) {
            final ownerMatch = _propOwnerRe.firstMatch(nextLine);
            if (ownerMatch != null) {
              propertyOwner = ownerMatch.group(1)?.trim();
            }
          }

          final scheduledMatch = _scheduledRe.firstMatch(nextLine);
          if (scheduledMatch != null) {
            scheduledDate = scheduledMatch.group(1);
          }
          final deadlineMatch = _deadlineRe.firstMatch(nextLine);
          if (deadlineMatch != null) {
            deadlineDate = deadlineMatch.group(1);
          }

          j++;
        }

        // Now parse the heading
        final draft = _parseHeading(
          stars: stars,
          rest: rest,
          sourceLabel: sourceLabel,
          scheduledDate: scheduledDate,
          deadlineDate: deadlineDate,
          propertyOwner: propertyOwner,
        );
        if (draft != null) drafts.add(draft);

        i++;
        continue;
      }

      // Plain list items
      final listMatch = RegExp(r'^-\s+(.+)').firstMatch(line);
      if (listMatch != null) {
        final text = listMatch.group(1)!.trim();
        if (text.isNotEmpty) {
          final person = _detectPerson(text);
          drafts.add(InboxItemDraft(
            rawText: text,
            parsedType: 'note',
            parsedData: {
              'description': text,
              if (person != null) 'owner': person,
              if (sourceLabel.isNotEmpty) 'source_label': sourceLabel,
            },
            suggestedPersonName: person,
          ));
        }
        i++;
        continue;
      }

      // Skip metadata lines (SCHEDULED:, DEADLINE:, :PROPERTIES:, etc.)
      if (line.startsWith(':') ||
          line.startsWith('SCHEDULED:') ||
          line.startsWith('DEADLINE:') ||
          line.startsWith('#+')) {
        i++;
        continue;
      }

      // Plain paragraph text — note
      if (line.isNotEmpty) {
        final person = _detectPerson(line);
        drafts.add(InboxItemDraft(
          rawText: line,
          parsedType: 'note',
          parsedData: {
            'description': line,
            if (sourceLabel.isNotEmpty) 'source_label': sourceLabel,
          },
          suggestedPersonName: person,
        ));
      }

      i++;
    }

    return drafts;
  }

  InboxItemDraft? _parseHeading({
    required int stars,
    required String rest,
    required String sourceLabel,
    String? scheduledDate,
    String? deadlineDate,
    String? propertyOwner,
  }) {
    final dueDate = deadlineDate ?? scheduledDate;

    // Extract TODO/DONE/keyword token at start
    final todoMatch = RegExp(
      r'^(TODO|DONE|RISK|DECISION|ACTION|ISSUE|NEXT|WAITING|CANCELLED)\s+(.*)',
      caseSensitive: false,
    ).firstMatch(rest);

    if (todoMatch != null) {
      final keyword = todoMatch.group(1)!.toUpperCase();
      final title = todoMatch.group(2)!.trim();

      // Skip done/cancelled
      if (keyword == 'DONE' || keyword == 'CANCELLED') return null;

      final type = _keywordToType(keyword);
      final person = propertyOwner ?? _detectPerson(title);

      return InboxItemDraft(
        rawText: title,
        parsedType: type,
        parsedData: _typedData(
          type,
          title,
          sourceLabel,
          person: person,
          dueDate: dueDate,
        ),
        suggestedPersonName: person,
      );
    }

    // Heading title contains a RISK/DECISION keyword without leading state
    final titleUpper = rest.toUpperCase();
    if (titleUpper.contains('RISK')) {
      final person = propertyOwner ?? _detectPerson(rest);
      return InboxItemDraft(
        rawText: rest,
        parsedType: 'risk',
        parsedData: _typedData(
          'risk',
          rest,
          sourceLabel,
          person: person,
          dueDate: dueDate,
        ),
        suggestedPersonName: person,
      );
    }
    if (titleUpper.contains('DECISION')) {
      final person = propertyOwner ?? _detectPerson(rest);
      return InboxItemDraft(
        rawText: rest,
        parsedType: 'decision',
        parsedData: _typedData(
          'decision',
          rest,
          sourceLabel,
          person: person,
          dueDate: dueDate,
        ),
        suggestedPersonName: person,
      );
    }

    // Sub-headings (** or deeper) are context
    if (stars > 1) {
      return InboxItemDraft(
        rawText: rest,
        parsedType: 'context',
        parsedData: {
          'title': rest,
          'description': rest,
          if (sourceLabel.isNotEmpty) 'source_label': sourceLabel,
        },
        suggestedPersonName: null,
      );
    }

    // Top-level plain heading → note
    final person = propertyOwner ?? _detectPerson(rest);
    return InboxItemDraft(
      rawText: rest,
      parsedType: 'note',
      parsedData: {
        'description': rest,
        if (person != null) 'owner': person,
        if (sourceLabel.isNotEmpty) 'source_label': sourceLabel,
      },
      suggestedPersonName: person,
    );
  }

  String _keywordToType(String keyword) {
    switch (keyword) {
      case 'TODO':
      case 'NEXT':
        return 'todo';
      case 'ACTION':
        return 'action';
      case 'RISK':
        return 'risk';
      case 'DECISION':
        return 'decision';
      case 'ISSUE':
        return 'note';
      case 'WAITING':
        return 'todo';
      default:
        return 'note';
    }
  }

  String? _detectPerson(String line) {
    final atMatch = _atNameRe.firstMatch(line);
    if (atMatch != null) return atMatch.group(1)?.trim();
    return null;
  }

  Map<String, dynamic> _typedData(
    String type,
    String text,
    String source, {
    String? person,
    String? dueDate,
  }) {
    final base = <String, dynamic>{
      'description': text,
      if (source.isNotEmpty) 'source_label': source,
    };
    switch (type) {
      case 'risk':
        return {
          ...base,
          'likelihood': 'medium',
          'impact': 'medium',
          'status': 'open',
          if (person != null) 'owner': person,
        };
      case 'decision':
        return {
          ...base,
          'status': 'pending',
          if (person != null) 'decision_maker': person,
          if (dueDate != null) 'due_date': dueDate,
        };
      case 'action':
      case 'todo':
        return {
          ...base,
          'status': 'open',
          if (person != null) 'owner': person,
          if (dueDate != null) 'due_date': dueDate,
        };
      default:
        return base;
    }
  }
}
