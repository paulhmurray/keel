import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// Renders journal body text, turning @PersonName and #GlossaryName spans
/// into coloured, tappable inline links.
///
/// • amber  → @person  (click → person card popup)
/// • green  → #glossary term or system  (click → glossary popup)
class JournalLinkRenderer extends StatefulWidget {
  final String text;
  final List<Person> persons;
  final List<GlossaryEntry> glossaryEntries;
  final TextStyle baseStyle;

  const JournalLinkRenderer({
    super.key,
    required this.text,
    this.persons = const [],
    this.glossaryEntries = const [],
    this.baseStyle = const TextStyle(
      color: KColors.text,
      fontSize: 12,
      height: 1.7,
    ),
  });

  @override
  State<JournalLinkRenderer> createState() => _JournalLinkRendererState();
}

// ---------------------------------------------------------------------------
// Internal token model
// ---------------------------------------------------------------------------

enum _SpanKind { plain, person, glossary }

class _Span {
  final String text;
  final _SpanKind kind;
  final Person? person;
  final GlossaryEntry? glossaryEntry;

  _Span.plain(this.text)
      : kind = _SpanKind.plain,
        person = null,
        glossaryEntry = null;
  _Span.person(this.text, this.person)
      : kind = _SpanKind.person,
        glossaryEntry = null;
  _Span.glossary(this.text, this.glossaryEntry)
      : kind = _SpanKind.glossary,
        person = null;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _JournalLinkRendererState extends State<JournalLinkRenderer> {
  List<_Span> _spans = [];
  // Recognizers are recreated on every build; old ones disposed first.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _parseSpans();
  }

  @override
  void didUpdateWidget(JournalLinkRenderer old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text ||
        old.persons != widget.persons ||
        old.glossaryEntries != widget.glossaryEntries) {
      _parseSpans();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _parseSpans() {
    final text = widget.text;

    // Build lookup maps
    final personMap = <String, Person>{};
    for (final p in widget.persons) {
      personMap['@${p.name}'] = p;
    }

    final glossaryMap = <String, GlossaryEntry>{};
    for (final e in widget.glossaryEntries) {
      glossaryMap['#${e.name}'] = e;
      if (e.acronym != null && e.acronym!.isNotEmpty) {
        glossaryMap['#${e.acronym}'] = e;
      }
    }

    if (text.isEmpty || (personMap.isEmpty && glossaryMap.isEmpty)) {
      setState(() => _spans = [_Span.plain(text)]);
      return;
    }

    // Build a single regex matching all tokens — longest first so partial
    // names don't shadow longer ones (e.g. "@John" vs "@John Smith").
    final allTokens = [...personMap.keys, ...glossaryMap.keys];
    allTokens.sort((a, b) => b.length.compareTo(a.length));
    final regex = RegExp(allTokens.map(RegExp.escape).join('|'));

    final spans = <_Span>[];
    int cursor = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(_Span.plain(text.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      if (personMap.containsKey(token)) {
        spans.add(_Span.person(token, personMap[token]!));
      } else if (glossaryMap.containsKey(token)) {
        spans.add(_Span.glossary(token, glossaryMap[token]!));
      } else {
        spans.add(_Span.plain(token));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(_Span.plain(text.substring(cursor)));
    }

    setState(() => _spans = spans.isEmpty ? [_Span.plain(text)] : spans);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final inlineSpans = <InlineSpan>[];

    for (final span in _spans) {
      switch (span.kind) {
        case _SpanKind.plain:
          inlineSpans.add(TextSpan(text: span.text, style: widget.baseStyle));

        case _SpanKind.person:
          final p = span.person!;
          final r = TapGestureRecognizer()..onTap = () => _showPerson(p);
          _recognizers.add(r);
          inlineSpans.add(TextSpan(
            text: span.text,
            style: widget.baseStyle.copyWith(
              color: KColors.amber,
              fontWeight: FontWeight.w600,
            ),
            recognizer: r,
          ));

        case _SpanKind.glossary:
          final e = span.glossaryEntry!;
          final r = TapGestureRecognizer()..onTap = () => _showGlossary(e);
          _recognizers.add(r);
          inlineSpans.add(TextSpan(
            text: span.text,
            style: widget.baseStyle.copyWith(
              color: KColors.phosphor,
              fontWeight: FontWeight.w600,
            ),
            recognizer: r,
          ));
      }
    }

    return RichText(text: TextSpan(children: inlineSpans));
  }

  void _showPerson(Person p) => showDialog(
        context: context,
        builder: (_) => _PersonPopup(person: p),
      );

  void _showGlossary(GlossaryEntry e) => showDialog(
        context: context,
        builder: (_) => _GlossaryPopup(entry: e),
      );
}

// ---------------------------------------------------------------------------
// Person popup
// ---------------------------------------------------------------------------

class _PersonPopup extends StatelessWidget {
  final Person person;
  const _PersonPopup({required this.person});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(name: person.name, color: KColors.amber,
                      dimColor: KColors.amberDim),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.name,
                            style: const TextStyle(
                                color: KColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        if (person.role != null && person.role!.isNotEmpty)
                          Text(person.role!,
                              style: const TextStyle(
                                  color: KColors.textDim, fontSize: 12)),
                      ],
                    ),
                  ),
                  _CloseButton(),
                ],
              ),
              if (_hasDetails) ...[
                const SizedBox(height: 12),
                const Divider(height: 1, color: KColors.border),
                const SizedBox(height: 8),
              ],
              if (person.organisation?.isNotEmpty ?? false)
                _Row(Icons.business_outlined, person.organisation!),
              if (person.email?.isNotEmpty ?? false)
                _Row(Icons.email_outlined, person.email!),
              if (person.phone?.isNotEmpty ?? false)
                _Row(Icons.phone_outlined, person.phone!),
              if (person.teamsHandle?.isNotEmpty ?? false)
                _Row(Icons.chat_bubble_outline, person.teamsHandle!),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasDetails =>
      (person.organisation?.isNotEmpty ?? false) ||
      (person.email?.isNotEmpty ?? false) ||
      (person.phone?.isNotEmpty ?? false) ||
      (person.teamsHandle?.isNotEmpty ?? false);
}

// ---------------------------------------------------------------------------
// Glossary popup
// ---------------------------------------------------------------------------

class _GlossaryPopup extends StatelessWidget {
  final GlossaryEntry entry;
  const _GlossaryPopup({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isSystem = entry.type == 'system';
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TypeBadge(isSystem: isSystem),
                  const Spacer(),
                  _CloseButton(),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.name,
                style: const TextStyle(
                    color: KColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              if (entry.acronym?.isNotEmpty ?? false)
                Text(entry.acronym!,
                    style: const TextStyle(
                        color: KColors.phosphor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              if (entry.description?.isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                const Divider(height: 1, color: KColors.border),
                const SizedBox(height: 10),
                Text(
                  entry.description!,
                  style: const TextStyle(
                      color: KColors.textDim, fontSize: 12, height: 1.6),
                ),
              ],
              if (isSystem) ...[
                if (entry.owner?.isNotEmpty ?? false)
                  _Row(Icons.person_outline, 'Owner: ${entry.owner}'),
                if (entry.environment?.isNotEmpty ?? false)
                  _Row(Icons.dns_outlined, entry.environment!),
                if (entry.status?.isNotEmpty ?? false)
                  _Row(Icons.circle_outlined, entry.status!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  final String name;
  final Color color;
  final Color dimColor;
  const _Avatar({required this.name, required this.color, required this.dimColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: dimColor,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final bool isSystem;
  const _TypeBadge({required this.isSystem});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: KColors.phosDim,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        isSystem ? 'SYSTEM' : 'TERM',
        style: const TextStyle(
            color: KColors.phosphor,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Row(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 12, color: KColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(color: KColors.textDim, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.close, size: 16, color: KColors.textMuted),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      splashRadius: 14,
    );
  }
}
