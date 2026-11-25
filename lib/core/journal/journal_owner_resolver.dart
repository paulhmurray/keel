/// Resolves an owner written in a journal note ("Sasi", "Yoshi", "Me",
/// "Chris (Deloitte)") to a person in the project's People list.
///
/// RAID items, actions and decisions store the owner as free text, and the
/// person-centred views (a person's workload) only match the EXACT full
/// name — so a parsed "Sasi" never shows up against Sasi Sasindran. The
/// journal review resolves owners up front so confirmed items land on the
/// right person. Pure Dart so it is unit-tested without a database.
library;

/// The bits of a Person the resolver needs.
class PersonRef {
  final String name;
  final String? organisation;
  const PersonRef(this.name, [this.organisation]);
}

enum OwnerMatch {
  /// Exactly one person — [OwnerResolution.name] is their full name.
  person,

  /// Several people fit — [OwnerResolution.candidates] lists them.
  ambiguous,

  /// A team or organisation ("TAC and Deloitte", "Deloitte").
  group,

  /// Nobody in People fits.
  unknown,
}

class OwnerResolution {
  final OwnerMatch kind;
  final String? name;
  final List<String> candidates;
  const OwnerResolution(this.kind, {this.name, this.candidates = const []});

  bool get isPerson => kind == OwnerMatch.person;
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

final _groupSep = RegExp(
  r'\s+(?:and|&|\+)\s+|\s*[,/;]\s*',
  caseSensitive: false,
);
final _paren = RegExp(r'[\(\[]([^\)\]]*)[\)\]]');

/// Resolves [raw] against [people]. [myName] is the user's own name
/// (Settings → My name), matched by "Me"/"myself" and by name. [hint] is
/// extra context — the entry title — whose organisation names break ties
/// ("Chris" in "chat with Chris[Deloitte]" → the Deloitte Chris).
/// Returns null for an empty owner.
OwnerResolution? resolveOwner(
  String? raw,
  List<PersonRef> people, {
  String myName = '',
  String hint = '',
}) {
  var text = (raw ?? '').trim().replaceFirst(RegExp(r'^@'), '').trim();
  if (text.isEmpty) return null;

  final me = myName.trim();
  if (me.isNotEmpty &&
      RegExp(r'^(me|myself)$', caseSensitive: false).hasMatch(text)) {
    return OwnerResolution(OwnerMatch.person, name: me);
  }

  // Exact full name first — "Sasi Sasindran" is never ambiguous.
  for (final p in people) {
    if (_norm(p.name) == _norm(text)) {
      return OwnerResolution(OwnerMatch.person, name: p.name);
    }
  }
  if (me.isNotEmpty && _norm(me) == _norm(text)) {
    return OwnerResolution(OwnerMatch.person, name: me);
  }

  // "Chris (Deloitte)" — the bracket is an organisation hint, not the name.
  final hints = <String>[hint];
  text = text.replaceAllMapped(_paren, (m) {
    hints.add(m.group(1)!);
    return ' ';
  }).trim();
  if (text.isEmpty) return const OwnerResolution(OwnerMatch.unknown);

  if (_groupSep.hasMatch(text)) {
    return const OwnerResolution(OwnerMatch.group);
  }

  final orgs = {
    for (final p in people)
      if ((p.organisation ?? '').trim().isNotEmpty) _norm(p.organisation!),
  };
  if (orgs.contains(_norm(text))) {
    return const OwnerResolution(OwnerMatch.group);
  }

  // Everyone the note could mean: People plus the user themselves.
  final pool = [
    ...people,
    if (me.isNotEmpty && !people.any((p) => _norm(p.name) == _norm(me)))
      PersonRef(me),
  ];
  final words = _norm(text).split(' ');

  List<PersonRef> matching({required bool firstNameOnly}) => pool.where((p) {
    final tokens = _norm(p.name).split(' ');
    if (words.length == 1) {
      return firstNameOnly
          ? tokens.first.startsWith(words.first)
          : tokens.any((t) => t.startsWith(words.first));
    }
    // "Sasi S" / "Chris Baker": each word prefixes the name in order.
    if (words.length > tokens.length) return false;
    for (var i = 0; i < words.length; i++) {
      final t = i == words.length - 1 ? tokens.last : tokens[i];
      if (!t.startsWith(words[i])) return false;
    }
    return true;
  }).toList();

  // A lone word is a first name if anyone has it; only then try surnames
  // ("Yoshi" → Yosuke Yoshikawa).
  var found = matching(firstNameOnly: true);
  if (found.isEmpty) found = matching(firstNameOnly: false);

  if (found.length > 1) {
    final hintText = _norm(hints.join(' '));
    final byOrg = found.where((p) {
      final o = _norm(p.organisation ?? '');
      return o.isNotEmpty &&
          RegExp('\\b${RegExp.escape(o)}\\b').hasMatch(hintText);
    }).toList();
    if (byOrg.length == 1) found = byOrg;
  }

  if (found.length == 1) {
    return OwnerResolution(OwnerMatch.person, name: found.single.name);
  }
  if (found.length > 1) {
    return OwnerResolution(
      OwnerMatch.ambiguous,
      candidates: [for (final p in found) p.name],
    );
  }
  return const OwnerResolution(OwnerMatch.unknown);
}
