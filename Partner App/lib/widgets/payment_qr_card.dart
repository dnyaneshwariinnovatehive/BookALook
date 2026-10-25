import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/payroll_api.dart';
import '../theme/app_theme.dart';

/// BookALook's payment QR, UPI ID and payee, as the superadmin set them in
/// policy settings, with the amount to pay. Used wherever a salon pays
/// BookALook — buying a plan, or paying what a payout says it owes.
class PaymentQrCard extends StatefulWidget {
  final double amount;

  /// Loads the details; defaults to the API. Injectable for tests.
  final Future<PaymentDetails> Function()? load;

  /// Draws its own border; off where the host already frames it.
  final bool framed;

  const PaymentQrCard({super.key, required this.amount, this.load, this.framed = true});

  @override
  State<PaymentQrCard> createState() => _PaymentQrCardState();
}

class _PaymentQrCardState extends State<PaymentQrCard> {
  late Future<PaymentDetails> _details;

  @override
  void initState() {
    super.initState();
    _details = (widget.load ?? PayrollApi.paymentDetails)();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey('payment_qr_card'),
      padding: widget.framed ? const EdgeInsets.all(16) : EdgeInsets.zero,
      decoration: widget.framed
          ? BoxDecoration(
              border: Border.all(color: scheme.outline),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: FutureBuilder<PaymentDetails>(
        future: _details,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
          }

          final details = snap.data ?? const PaymentDetails();

          return Column(
            children: [
              const Text('Scan QR to Pay', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              if ((details.qrUrl ?? '').isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    details.qrUrl!,
                    key: const ValueKey('payment_qr_image'),
                    width: 210,
                    height: 210,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _qrUnavailable(scheme, 'The QR could not be loaded. Use the UPI ID below.'),
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const SizedBox(width: 210, height: 210, child: Center(child: CircularProgressIndicator())),
                  ),
                )
              else
                _qrUnavailable(
                  scheme,
                  details.isSetUp
                      ? 'Pay to the UPI ID below.'
                      : 'BookALook has not added its payment QR yet. Please contact BookALook support to pay.',
                ),
              const SizedBox(height: 12),
              Text(
                'Pay ₹${widget.amount.toStringAsFixed(widget.amount % 1 == 0 ? 0 : 2)}',
                key: const ValueKey('payment_qr_amount'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              if ((details.payeeName ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('to ${details.payeeName}', style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
              if ((details.upiId ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          details.upiId!,
                          key: const ValueKey('payment_upi_id'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy UPI ID',
                        icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.accentColor),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: details.upiId!));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('UPI ID copied'), duration: Duration(seconds: 2)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _qrUnavailable(ColorScheme scheme, String message) {
    return Column(
      children: [
        Icon(Icons.qr_code_2, size: 96, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }
}
