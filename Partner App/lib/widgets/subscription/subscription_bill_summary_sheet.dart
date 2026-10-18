import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'payment_proof_viewer.dart';

/// Displays a structured bill summary for a subscription payment submission.
///
/// Can be presented in a modal bottom sheet from the billing screen, the
/// confirmation dialog, or the subscription-locked screen.
class SubscriptionBillSummarySheet extends StatelessWidget {
  final Map<String, dynamic> request;

  const SubscriptionBillSummarySheet({super.key, required this.request});

  /// Displays the bill summary sheet in a modal bottom sheet.
  static Future<void> show(BuildContext context, Map<String, dynamic> request) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SubscriptionBillSummarySheet(request: request),
    );
  }

  String _formatDateTime(Object? raw) {
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    return DateFormat('d MMMM yyyy, h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String status = (request['status'] ?? 'pending')
        .toString()
        .toLowerCase();
    final String planName =
        request['plan_name']?.toString() ??
        request['plan']?['name']?.toString() ??
        request['billing_label']?.toString() ??
        'Subscription Plan';

    final int validityDays =
        int.tryParse(
          (request['validity_days'] ?? request['plan']?['validity_days'] ?? 30)
              .toString(),
        ) ??
        30;

    final double payable =
        double.tryParse(
          (request['amount_payable_inr'] ?? request['amount_submitted'] ?? 0)
              .toString(),
        ) ??
        0.0;

    final int coins =
        int.tryParse((request['coins_to_redeem'] ?? 0).toString()) ?? 0;
    final double coinDiscount =
        double.tryParse((request['coin_discount_inr'] ?? 0).toString()) ?? 0.0;

    final double rawBasePrice =
        double.tryParse(
          (request['base_price'] ??
                  request['plan_price'] ??
                  request['plan']?['price'] ??
                  0)
              .toString(),
        ) ??
        0.0;

    // Preserve arithmetic integrity: Base Price = Payable + Coin Discount
    final double basePrice = (rawBasePrice > 0)
        ? rawBasePrice
        : (payable + coinDiscount);

    final String? transactionId = request['transaction_id']?.toString();
    final String? note = request['note']?.toString();
    final String? screenshotUrl = request['screenshot_url']?.toString();
    final String? raisedAt =
        request['raised_at']?.toString() ?? request['created_at']?.toString();

    Color statusColor;
    Color statusBg;
    String statusLabel;
    IconData statusIcon;

    if (status == 'approved') {
      statusColor = isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess;
      statusBg = (isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess)
          .withValues(alpha: 0.14);
      statusLabel = 'APPROVED';
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'rejected') {
      statusColor = colors.danger;
      statusBg = colors.danger.withValues(alpha: 0.12);
      statusLabel = 'NOT ACCEPTED';
      statusIcon = Icons.cancel_rounded;
    } else {
      statusColor = isDark ? AppTheme.darkWarning : AppTheme.lightWarning;
      statusBg = (isDark ? AppTheme.darkWarning : AppTheme.lightWarning)
          .withValues(alpha: 0.14);
      statusLabel = 'UNDER REVIEW';
      statusIcon = Icons.hourglass_top_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title & Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subscription Bill Summary',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Payment submission breakdown',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Plan Info Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: AppTheme.accentColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          planName,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$validityDays days access per billing cycle',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Financial Breakdown
            Text(
              'PAYMENT BREAKDOWN',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  _lineItem(
                    label: 'Base Plan Price',
                    value: '₹${basePrice.toStringAsFixed(2)}',
                    colors: colors,
                  ),
                  if (coins > 0) ...[
                    const SizedBox(height: 8),
                    _lineItem(
                      label: 'Reward Coins Applied ($coins coins)',
                      value: '−₹${coinDiscount.toStringAsFixed(2)}',
                      valueColor: isDark
                          ? AppTheme.darkSuccess
                          : AppTheme.lightSuccess,
                      colors: colors,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Divider(height: 1, color: colors.border),
                  const SizedBox(height: 10),
                  _lineItem(
                    label: status == 'approved'
                        ? 'Total Amount Paid'
                        : 'Amount Submitted',
                    value: '₹${payable.toStringAsFixed(2)}',
                    isBold: true,
                    colors: colors,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Transaction & Audit Details
            Text(
              'TRANSACTION DETAILS',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  _detailRow(
                    label: 'Payment Method',
                    value: 'Manual Bank Transfer / UPI',
                    colors: colors,
                  ),
                  const SizedBox(height: 10),
                  _detailRow(
                    label: 'Transaction ID / UTR',
                    value: (transactionId != null && transactionId.isNotEmpty)
                        ? transactionId
                        : 'Not provided',
                    colors: colors,
                  ),
                  const SizedBox(height: 10),
                  _detailRow(
                    label: 'Submitted On',
                    value: _formatDateTime(raisedAt),
                    colors: colors,
                  ),
                  if (note != null && note.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _detailRow(
                      label: 'Owner Note',
                      value: note,
                      colors: colors,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Review notice box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    status == 'approved'
                        ? Icons.verified_outlined
                        : status == 'rejected'
                        ? Icons.info_outline
                        : Icons.schedule_rounded,
                    size: 20,
                    color: statusColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      status == 'approved'
                          ? 'Payment verified and subscription activated by SuperAdmin.'
                          : status == 'rejected'
                          ? 'This payment submission was not accepted. Please review your transfer or submit a new payment proof.'
                          : 'Your payment submission is awaiting SuperAdmin review. Your subscription entitlements will activate as soon as the bank credit is verified.',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        height: 1.4,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action buttons
            Row(
              children: [
                if (screenshotUrl != null && screenshotUrl.isNotEmpty) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        PaymentProofViewer.show(
                          context,
                          imageUrl: screenshotUrl,
                          title: 'Payment Proof',
                          transactionId: transactionId,
                          note: note,
                        );
                      },
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('View Payment Proof'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineItem({
    required String label,
    required String value,
    required AppColors colors,
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: isBold ? 14.5 : 13.5,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isBold ? colors.textPrimary : colors.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _detailRow({
    required String label,
    required String value,
    required AppColors colors,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
