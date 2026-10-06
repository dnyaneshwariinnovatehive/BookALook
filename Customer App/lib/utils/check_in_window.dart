import 'package:intl/intl.dart';

/// The check-in QR window for a booking, as the server decided it.
///
/// The server owns the rule — the QR opens at the booked start time less the
/// platform's early start allowance and closes at the end of the appointment's
/// day — and sends the outcome on every booking. This only words it, so every
/// screen says the same thing about the same booking.
class CheckInWindow {
  /// The customer can show their QR right now.
  static bool canShowQr(Map<String, dynamic> booking) =>
      booking['can_generate_qr'] == true && booking['status'] == 'scheduled';

  /// "QR available at 4:30 PM" (or "on 3 Oct at 4:30 PM" for a later day)
  /// while the window has not opened yet; null once it is open or when the
  /// booking will never get a QR (cancelled, unpaid, past).
  static String? notYetOpenLabel(Map<String, dynamic> booking) {
    if (canShowQr(booking)) return null;

    final from = DateTime.tryParse('${booking['qr_available_from'] ?? ''}')?.toLocal();
    if (from == null || !from.isAfter(DateTime.now())) return null;

    final now = DateTime.now();
    final sameDay = from.year == now.year && from.month == now.month && from.day == now.day;
    final time = DateFormat('h:mm a').format(from);

    return sameDay
        ? 'QR available at $time'
        : 'QR available on ${DateFormat('d MMM').format(from)} at $time';
  }
}
