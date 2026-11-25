/// Turns the loose due dates people write in notes ("January 2027",
/// "end of 2026", "mid-December", "Q1 FY27", "15/1/27") into an ISO date,
/// so overdue and deadline views can see them. Phrases with no date in
/// them ("ASAP", "completion of the workshop") return null and are left
/// for the user. Pure Dart so it is unit-tested without a database.
library;

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};
const _monthRe =
    r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _lastDay(int year, int month) => DateTime(year, month + 1, 0);

int _year(String y) {
  final n = int.parse(y);
  return n < 100 ? 2000 + n : n;
}

/// True when [s] is already a plain ISO date.
bool isIsoDate(String? s) =>
    s != null &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s.trim()) &&
    DateTime.tryParse(s.trim()) != null;

/// The ISO date [raw] describes, or null when it holds no date.
///
/// [ref] is "today" for the note (its entry date): a month with no year
/// means its next occurrence on or after [ref]. [fyAnchorMonth] is the
/// month the financial year starts (Settings → quarter anchor); "Q1 FY27"
/// is read against it, with the FY named for the year it ENDS in (AU).
/// A plain "Q1 2027" is a calendar quarter. Vague positions in a month
/// resolve to a working deadline: early → 7th, mid → 15th, otherwise
/// (end / late / just the month) → the last day.
String? normaliseDueDate(
  String? raw, {
  required DateTime ref,
  int fyAnchorMonth = 1,
}) {
  final text = (raw ?? '').trim().toLowerCase();
  if (text.isEmpty) return null;
  final today = DateTime(ref.year, ref.month, ref.day);

  RegExpMatch? m;

  // 2027-01-15
  m = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(text);
  if (m != null) {
    return _valid(_year(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  // 15/1/2027, 15.1.27 — day first (AU).
  m = RegExp(r'\b(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})\b').firstMatch(text);
  if (m != null) {
    return _valid(_year(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }

  // Q1 FY27 / FY27 Q1 — financial-year quarter.
  m = RegExp(r"\bq([1-4])\s*fy\s*'?(\d{2,4})\b").firstMatch(text);
  final fyAlt = RegExp(r"\bfy\s*'?(\d{2,4})\s*q([1-4])\b").firstMatch(text);
  if (m != null || fyAlt != null) {
    final q = int.parse(m != null ? m[1]! : fyAlt![2]!);
    final fy = _year(m != null ? m[2]! : fyAlt![1]!);
    final startYear = fyAnchorMonth == 1 ? fy : fy - 1;
    final start = DateTime(startYear, fyAnchorMonth + 3 * (q - 1), 1);
    return _iso(_lastDay(start.year, start.month + 2));
  }

  // Q1 2027 — calendar quarter.
  m = RegExp(r'\bq([1-4])\s*(\d{4})\b').firstMatch(text);
  if (m != null) {
    return _iso(_lastDay(_year(m[2]!), int.parse(m[1]!) * 3));
  }

  // 15 January 2027 / 15th Jan
  m = RegExp(
    '\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?$_monthRe\\b\\.?(?:,?\\s+(\\d{4}))?',
  ).firstMatch(text);
  if (m != null) {
    return _inMonth(m[2]!, m[3], today, day: int.parse(m[1]!));
  }

  // January 15, 2027
  m = RegExp(
    '\\b$_monthRe\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?!\\d)(?:,?\\s+(\\d{4}))?',
  ).firstMatch(text);
  if (m != null) {
    return _inMonth(m[1]!, m[3], today, day: int.parse(m[2]!));
  }

  // [early | mid | end of | late] January [2027]
  m = RegExp(
    '\\b(early|start of|beginning of|mid|middle of|late|end of)?[\\s-]*$_monthRe\\b(?:\\s+(\\d{4}))?',
  ).firstMatch(text);
  if (m != null) {
    final pos = m[1];
    final day = switch (pos) {
      'early' || 'start of' || 'beginning of' => 7,
      'mid' || 'middle of' => 15,
      _ => null,
    };
    return _inMonth(m[2]!, m[3], today, day: day);
  }

  // end of 2026 / end of year / end of (this|next) month / week
  m = RegExp(r'\b(?:end of|late)\s+(\d{4})\b').firstMatch(text);
  if (m != null) return '${m[1]}-12-31';
  if (RegExp(r'\bend of (?:the |this )?year\b').hasMatch(text)) {
    return '${today.year}-12-31';
  }
  if (RegExp(r'\bend of next month\b').hasMatch(text)) {
    return _iso(_lastDay(today.year, today.month + 1));
  }
  if (RegExp(r'\bend of (?:the |this )?month\b').hasMatch(text)) {
    return _iso(_lastDay(today.year, today.month));
  }
  if (RegExp(r'\b(?:end of )?next week\b').hasMatch(text)) {
    return _iso(_friday(today).add(const Duration(days: 7)));
  }
  if (RegExp(r'\b(?:end of (?:the |this )?week|this week)\b').hasMatch(text)) {
    return _iso(_friday(today));
  }
  // (next) Friday — the coming one, today included; "next" skips to the
  // following week when the coming one is still this week.
  m = RegExp(
    r'\b(next\s+)?(monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thu|friday|fri|saturday|sat|sunday|sun)\b',
  ).firstMatch(text);
  if (m != null) {
    const wd = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final target = wd.indexOf(m[2]!.substring(0, 3)) + 1;
    var date = today.add(Duration(days: (target - today.weekday) % 7));
    if (m[1] != null) {
      final weekEnd = today.add(Duration(days: 7 - today.weekday));
      if (!date.isAfter(weekEnd)) date = date.add(const Duration(days: 7));
    }
    return _iso(date);
  }
  if (RegExp(r'\btomorrow\b').hasMatch(text)) {
    return _iso(today.add(const Duration(days: 1)));
  }
  return null;
}

DateTime _friday(DateTime d) =>
    d.add(Duration(days: (DateTime.friday - d.weekday) % 7));

String? _valid(int y, int mo, int d) {
  if (mo < 1 || mo > 12 || d < 1 || d > _lastDay(y, mo).day) return null;
  return _iso(DateTime(y, mo, d));
}

String? _inMonth(String monthWord, String? year, DateTime today, {int? day}) {
  final mo = _months[monthWord.substring(0, 3)]!;
  int y;
  if (year != null) {
    y = int.parse(year);
  } else {
    // No year: the next time that month comes round.
    y = today.year;
    final end = _lastDay(y, mo);
    if (end.isBefore(today)) y++;
  }
  final d = day ?? _lastDay(y, mo).day;
  return _valid(y, mo, d);
}
