import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/invoice_screen.dart';
import '../theme/app_theme.dart';

/// The invoice details a booking carries, if it has any.
class InvoiceInfo {
  final String url;
  final String number;

  const InvoiceInfo({required this.url, required this.number});

  /// Pulls the invoice off a booking payload.
  ///
  /// Returns null when there is no invoice, or when the link is one we cannot
  /// use. The buttons below render nothing in that case rather than showing an
  /// action that is guaranteed to fail.
  static InvoiceInfo? fromBooking(Map<String, dynamic> booking) {
    final raw = booking['invoice'];
    if (raw is! Map) return null;

    final url = (raw['url'] ?? '').toString().trim();
    if (url.isEmpty) return null;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;

    return InvoiceInfo(
      url: url,
      number: (raw['number'] ?? '').toString().trim(),
    );
  }
}

/// Opens the invoice attached to a booking, if it has one.
void openInvoice(BuildContext context, Map<String, dynamic> booking) {
  final invoice = InvoiceInfo.fromBooking(booking);
  if (invoice == null) return;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => InvoiceScreen(
        url: invoice.url,
        invoiceNumber: invoice.number,
      ),
    ),
  );
}

/// Compact invoice action for a booking card.
class InvoiceLinkButton extends StatelessWidget {
  final Map<String, dynamic> booking;

  const InvoiceLinkButton({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final invoice = InvoiceInfo.fromBooking(booking);
    if (invoice == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => openInvoice(context, booking),
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_rounded,
                  size: 16, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              Text('View invoice',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentColor,
                  )),
              if (invoice.number.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  invoice.number,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width invoice action for the booking details screen.
class InvoiceActionButton extends StatelessWidget {
  final Map<String, dynamic> booking;

  const InvoiceActionButton({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final invoice = InvoiceInfo.fromBooking(booking);
    if (invoice == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () => openInvoice(context, booking),
        icon: const Icon(Icons.receipt_long_rounded, size: 19),
        label: Text(
          invoice.number.isNotEmpty
              ? 'View invoice ${invoice.number}'
              : 'View invoice',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: TextButton.styleFrom(
          backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
          foregroundColor: AppTheme.accentColor,
          side: const BorderSide(color: AppTheme.accentColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
