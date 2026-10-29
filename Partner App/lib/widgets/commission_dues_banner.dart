import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../screens/dashboard/more/salon_payouts_screen.dart';
import '../services/salon_access_api.dart';

/// Overdue commission, on the owner's Home tab.
///
/// Says how much, since when, what has already changed (full payment online,
/// deductions, paused bookings) and what happens next, with a way to pay.
/// Driven entirely by the server's dues state, so it disappears by itself
/// once the salon pays.
class CommissionDuesBanner extends StatelessWidget {
  final CommissionDues dues;
  final String salonId;

  /// Opens the payouts screen; injectable for tests.
  final VoidCallback? onPay;

  const CommissionDuesBanner({super.key, required this.dues, required this.salonId, this.onPay});

  String _inr(double v) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v);

  String _day(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '' : DateFormat('d MMM').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (!dues.showBanner) return const SizedBox.shrink();

    final paused = dues.has('stop_bookings');
    final overdue = dues.isOverdue;
    final color = paused
        ? Colors.red.shade700
        : overdue
            ? Colors.deepOrange.shade700
            : Colors.amber.shade800;

    final title = paused
        ? 'Online bookings paused'
        : overdue
            ? '${_inr(dues.owed)} commission overdue'
            : '${_inr(dues.owed)} commission due ${_day(dues.dueDate)}';

    final lines = <String>[
      if (paused) '${_inr(dues.owed)} has been overdue since ${_day(dues.dueDate)}. Customers cannot book until it is paid.',
      if (!paused && overdue) 'It was due on ${_day(dues.dueDate)}.',
      if (!overdue) 'Pay it before the due date to avoid restrictions.',
      if (dues.has('force_advance')) 'Customers now pay the full amount online.',
      if (dues.has('deduct')) 'It will be deducted from the money BookALook pays you.',
      if (dues.nextLabel != null && dues.nextOn != null) 'From ${_day(dues.nextOn)}: ${dues.nextLabel!.toLowerCase()}.',
      if (dues.underReview > 0) 'A payment you sent is being verified.',
    ];

    return Container(
      key: const ValueKey('commission_dues_banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(paused ? Icons.block_rounded : Icons.warning_amber_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line, style: GoogleFonts.outfit(fontSize: 12.5, height: 1.35)),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('commission_dues_pay'),
              onPressed: onPay ??
                  () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SalonPayoutsScreen(salonId: salonId)),
                      ),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: Text('Pay ${_inr(dues.owed)} now'),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
