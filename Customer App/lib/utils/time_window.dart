import 'package:intl/intl.dart';

/// "10:00:00" or "10:00" as "10:00 AM". Returns [raw] unchanged when it does
/// not look like a time, and an empty string for null or empty input.
String formatClock(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final parts = raw.trim().split(':');
  final h = int.tryParse(parts.first);
  final m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return raw;
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
}

/// An appointment's time as the customer reads it: "10:00 AM – 10:45 AM".
/// Just the start when the end is unknown.
String formatTimeWindow(String? start, String? end) {
  final from = formatClock(start);
  final to = formatClock(end);
  if (from.isEmpty) return to;
  return to.isEmpty ? from : '$from – $to';
}

/// The end of an appointment starting at [start] ("HH:mm") and lasting
/// [minutes], as "HH:mm" — or null when either is unusable.
String? addMinutesToClock(String? start, int minutes) {
  if (start == null || minutes <= 0) return null;
  final parts = start.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  final total = (h * 60 + m + minutes) % (24 * 60);
  return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
}

/// A length of time as people say it: "45 minutes", "1 hour",
/// "1 hour 30 minutes", "3 hours", "1 day 2 hours". Used for policy windows
/// such as how close to an appointment it can still be cancelled.
String formatMinutes(int minutes) {
  if (minutes <= 0) return '0 minutes';
  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  final days = minutes ~/ 1440;
  final hours = (minutes % 1440) ~/ 60;
  final mins = minutes % 60;

  final parts = <String>[
    if (days > 0) unit(days, 'day'),
    if (hours > 0) unit(hours, 'hour'),
    if (mins > 0) unit(mins, 'minute'),
  ];
  return parts.join(' ');
}
