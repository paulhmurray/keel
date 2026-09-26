/// The milestone tracker's hard-deadline banner used to be red whatever
/// the date said. Now its tone follows the deadline: quiet while it is
/// comfortably ahead, amber inside a fortnight, red once it has passed.
/// The PM can set the date explicitly; failing that, the statement text
/// is read for a date ("by end September 2025", "1 Nov 26", "Aug 27").
library;

enum DeadlineTone { unknown, ahead, near, overdue }

const int kDeadlineNearDays = 14;

const _kMonths = {
  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
  'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
  'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9,
  'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
};

DateTime _endOfMonth(int y, int m) => DateTime(y, m + 1, 0);

int _year(String raw) {
  var y = int.parse(raw);
  if (y < 100) y += 2000;
  return y;
}

/// Best-effort date from a free-text deadline statement. Recognises an
/// ISO date, `day Month yy|yyyy`, `Month yy|yyyy` (taken as the month's
/// last day, which "by end September" also means), and `Qn yyyy`
/// (calendar quarter end). Null when nothing date-like is there.
DateTime? parseDeadlineText(String? text) {
  if (text == null) return null;
  final t = text.trim();
  if (t.isEmpty) return null;

  final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
  if (iso != null) {
    return DateTime(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
        int.parse(iso.group(3)!));
  }
  final dmy = RegExp(r'\b(\d{1,2})\s+([A-Za-z]{3,9})\.?\s+(\d{2}|\d{4})\b')
      .firstMatch(t);
  if (dmy != null) {
    final m = _kMonths[dmy.group(2)!.toLowerCase()];
    if (m != null) {
      final y = _year(dmy.group(3)!);
      final d = int.parse(dmy.group(1)!);
      final last = _endOfMonth(y, m).day;
      return DateTime(y, m, d > last ? last : d);
    }
  }
  final my = RegExp(r'\b([A-Za-z]{3,9})\.?\s+(\d{2}|\d{4})\b').firstMatch(t);
  if (my != null) {
    final m = _kMonths[my.group(1)!.toLowerCase()];
    if (m != null) return _endOfMonth(_year(my.group(2)!), m);
  }
  final q = RegExp(r'\bQ([1-4])\s*(\d{2}|\d{4})\b', caseSensitive: false)
      .firstMatch(t);
  if (q != null) {
    final y = _year(q.group(2)!);
    return _endOfMonth(y, int.parse(q.group(1)!) * 3);
  }
  return null;
}

/// The date the banner should judge by: the explicit date wins, else
/// whatever the statement says, else nothing.
DateTime? effectiveDeadline({String? explicitIso, String? statement}) {
  if (explicitIso != null && explicitIso.isNotEmpty) {
    final d = DateTime.tryParse(explicitIso);
    if (d != null) return DateTime(d.year, d.month, d.day);
  }
  return parseDeadlineText(statement);
}

/// Whole days from [today] to [deadline], computed in UTC so a DST
/// change inside the span can't shave a day off.
int _daysUntil(DateTime deadline, DateTime today) {
  final t = DateTime.utc(today.year, today.month, today.day);
  final d = DateTime.utc(deadline.year, deadline.month, deadline.day);
  return d.difference(t).inDays;
}

DeadlineTone deadlineTone(DateTime? deadline, DateTime today) {
  if (deadline == null) return DeadlineTone.unknown;
  final days = _daysUntil(deadline, today);
  if (days < 0) return DeadlineTone.overdue;
  if (days <= kDeadlineNearDays) return DeadlineTone.near;
  return DeadlineTone.ahead;
}

/// "12 days overdue", "due in 9 days", "due today", or null when unknown.
String? deadlineCountdown(DateTime? deadline, DateTime today) {
  if (deadline == null) return null;
  final days = _daysUntil(deadline, today);
  if (days == 0) return 'due today';
  if (days < 0) return '${-days} day${days == -1 ? '' : 's'} overdue';
  return 'due in $days day${days == 1 ? '' : 's'}';
}
