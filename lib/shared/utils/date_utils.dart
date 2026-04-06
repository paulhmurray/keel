/// Converts an ISO date string (YYYY-MM-DD) to display format (DD-MM-YYYY).
/// Returns empty string if null or empty.
String formatDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '';
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate; // fallback: return as-is
  return '${parts[2]}-${parts[1]}-${parts[0]}';
}

/// Converts a display date string (DD-MM-YYYY) to ISO format (YYYY-MM-DD)
/// for database storage. Returns null if blank or unparseable.
String? parseDisplayDate(String displayDate) {
  final s = displayDate.trim();
  if (s.isEmpty) return null;
  final parts = s.split('-');
  if (parts.length != 3) return s; // fallback: store as-is
  return '${parts[2]}-${parts[1]}-${parts[0]}';
}

/// Formats a DateTime to ISO storage format (YYYY-MM-DD).
String toIsoDate(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';

/// Formats a DateTime to display format (DD-MM-YYYY).
String toDisplayDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.year.toString().padLeft(4, '0')}';

/// Parses an ISO date string to DateTime. Returns null if invalid.
DateTime? parseIsoDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return null;
  return DateTime.tryParse(isoDate);
}
