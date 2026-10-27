import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Shown at checkout when the customer has reached the platform's limit on
/// cancellations or no-shows: bookings blocked, full payment required, or a
/// warning — whichever BookALook has set. Draws nothing otherwise.
class BookingStandingBanner extends StatelessWidget {
  /// The `standing` object from `/customer/booking-standing`.
  final Map<String, dynamic>? standing;

  const BookingStandingBanner({super.key, required this.standing});

  /// True when bookings are blocked outright, so the Book button can say so.
  static bool blocks(Map<String, dynamic>? standing) =>
      standing?['restricted'] == true && standing?['action'] == 'block';

  @override
  Widget build(BuildContext context) {
    final s = standing;
    if (s == null || s['restricted'] != true) return const SizedBox.shrink();

    final action = s['action']?.toString();
    final blocked = action == 'block';
    final color = blocked ? context.colors.danger : const Color(0xFFB45309);
    final title = switch (action) {
      'block' => 'Bookings are paused on your account',
      'full_payment' => 'Full payment needed for new bookings',
      _ => 'Heads up about your bookings',
    };

    return Container(
      key: const ValueKey('booking_standing_banner'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(blocked ? Icons.block : Icons.info_outline, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                if (s['message'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    s['message'].toString(),
                    style: GoogleFonts.outfit(fontSize: 13, height: 1.35, color: context.colors.textPrimary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
