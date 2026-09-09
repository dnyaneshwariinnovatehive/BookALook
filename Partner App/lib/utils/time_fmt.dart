/// Tiny helpers for rendering times the way a human reads them.
///
/// Backend times arrive as `HH:MM:SS` (occasionally `HH:MM`). We never want to
/// show the trailing seconds, and couples of times read best as a range.
class TimeFmt {
  /// `"09:30:00"` -> `"9:30 AM"`, `"17:05"` -> `"5:05 PM"`. Falls back to the
  /// raw string when it cannot be parsed.
  static String hr(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final parts = value.trim().split(':');
    if (parts.length < 2) return value;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return value;

    final period = h >= 12 ? 'PM' : 'AM';
    final displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayHour:${m.toString().padLeft(2, '0')} $period';
  }

  /// `"09:30:00"`, `"10:15:00"` -> `"9:30 AM - 10:15 AM"`. Both times are
  /// trimmed of seconds. Falls back gracefully when either is missing.
  static String slot(String? start, String? end) {
    final s = hr(start);
    final e = hr(end);
    if (s.isEmpty && e.isEmpty) return '';
    if (s.isNotEmpty && e.isNotEmpty) return '$s - $e';
    return s.isNotEmpty ? s : e;
  }
}
