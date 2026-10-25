import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/payroll_api.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/payment_qr_card.dart';

/// Paying BookALook what a payout says the salon owes: scan the QR, pay, and
/// upload the screenshot for BookALook to verify. The same way a plan is
/// bought. Pops with true once the screenshot is sent.
class PayDuesScreen extends StatefulWidget {
  final String salonId;
  final SalonPayoutRecord payout;

  /// Test seams; both default to the real API.
  final Future<PaymentDetails> Function()? loadDetails;
  final Future<PayoutPaymentInfo> Function({
    required String salonId,
    required String payoutId,
    required List<int> screenshotBytes,
    required String screenshotName,
    String? transactionId,
    String? note,
  })? submit;

  /// Picks the screenshot; defaults to the gallery. Injectable for tests.
  final Future<XFile?> Function()? pickImage;

  const PayDuesScreen({
    super.key,
    required this.salonId,
    required this.payout,
    this.loadDetails,
    this.submit,
    this.pickImage,
  });

  @override
  State<PayDuesScreen> createState() => _PayDuesScreenState();
}

class _PayDuesScreenState extends State<PayDuesScreen> {
  final _transaction = TextEditingController();
  final _note = TextEditingController();
  XFile? _screenshot;
  List<int>? _bytes;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _transaction.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await (widget.pickImage ?? () => ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85))();
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _screenshot = picked;
      _bytes = bytes;
      _error = null;
    });
  }

  Future<void> _send() async {
    if (_bytes == null || _screenshot == null) {
      setState(() => _error = 'Upload the screenshot of your payment first.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await (widget.submit ?? PayrollApi.submitPayoutPayment)(
        salonId: widget.salonId,
        payoutId: widget.payout.id,
        screenshotBytes: _bytes!,
        // Some pickers hand back a file with no name; the server still needs one.
        screenshotName: _screenshot!.name.isNotEmpty ? _screenshot!.name : 'payment-screenshot.jpg',
        transactionId: _transaction.text,
        note: _note.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment sent for verification. We will notify you once it is confirmed.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payout;
    final scheme = Theme.of(context).colorScheme;
    final rejected = p.payment != null && p.payment!.isRejected ? p.payment : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Pay BookALook')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.lightDanger.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.lightDanger.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.cycleLabel, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  'You owe ₹${p.amountDue.toStringAsFixed(2)}',
                  key: const ValueKey('pay_dues_amount'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.lightDanger),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your commission of ₹${p.commissionDeducted.toStringAsFixed(2)} was more than the '
                  '₹${p.advancesHeld.toStringAsFixed(2)} of advances BookALook collected for you.',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
          if (rejected != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('pay_dues_rejected'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lightDanger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Your last payment could not be verified: ${rejected.rejectionReason ?? 'no reason given'}. '
                'Please pay the full amount and upload the new screenshot.',
                style: const TextStyle(color: AppTheme.lightDanger, fontSize: 13, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 16),
          PaymentQrCard(amount: p.amountDue, load: widget.loadDetails),
          const SizedBox(height: 16),
          Text('After paying, upload a screenshot of the payment.',
              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('pay_dues_pick'),
            onPressed: _sending ? null : _pick,
            icon: Icon(_screenshot == null ? Icons.upload_file : Icons.check_circle, color: _screenshot == null ? null : Colors.green),
            label: Text(_screenshot == null ? 'Upload Screenshot' : 'Screenshot selected — tap to change'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('pay_dues_utr'),
            controller: _transaction,
            maxLength: 150,
            decoration: const InputDecoration(
              labelText: 'Transaction ID / UTR (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 2,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Note for BookALook (optional)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(_error!, key: const ValueKey('pay_dues_error'), style: const TextStyle(color: AppTheme.lightDanger)),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              key: const ValueKey('pay_dues_submit'),
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit for verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
