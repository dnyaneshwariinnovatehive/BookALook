import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/booking_payments_api.dart';
import '../theme/app_theme.dart';

/// Payments on a booking, as the salon sees and records them.
///
/// There is no online payment: the customer pays the salon — the advance
/// before the visit, the rest at the counter — and the salon records it here.
/// Refunds of money the salon took are returned by the salon and marked here.
class BookingPaymentsCard extends StatefulWidget {
  final String salonId;
  final String appointmentId;

  /// Whether new payments can be recorded (not for cancelled bookings).
  final bool canRecord;

  /// Told after anything changes, so the screen can refresh its totals.
  final ValueChanged<PaymentLedger>? onChanged;

  @visibleForTesting
  final Future<PaymentLedger> Function()? loader;
  @visibleForTesting
  final Future<PaymentLedger> Function(double amount, String type, String mode, String? reference)? recorder;

  const BookingPaymentsCard({
    super.key,
    required this.salonId,
    required this.appointmentId,
    this.canRecord = true,
    this.onChanged,
    this.loader,
    this.recorder,
  });

  @override
  State<BookingPaymentsCard> createState() => _BookingPaymentsCardState();
}

class _BookingPaymentsCardState extends State<BookingPaymentsCard> {
  PaymentLedger? _ledger;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ledger = await (widget.loader?.call() ?? BookingPaymentsApi.fetch(widget.salonId, widget.appointmentId));
      if (!mounted) return;
      setState(() {
        _ledger = ledger;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _inr(double v) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: v % 1 == 0 ? 0 : 2).format(v);

  String _label(String s) => switch (s) {
        'upi' => 'UPI',
        'bank_transfer' => 'Bank transfer',
        'online' => 'Online',
        _ => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}',
      };

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _record() async {
    final ledger = _ledger;
    if (ledger == null) return;

    final result = await showModalBottomSheet<_Recorded>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RecordPaymentSheet(ledger: ledger, label: _label),
    );
    if (result == null) return;

    setState(() => _busy = true);
    try {
      final updated = await (widget.recorder?.call(result.amount, result.type, result.mode, result.reference) ??
          BookingPaymentsApi.record(widget.salonId, widget.appointmentId,
              amount: result.amount, type: result.type, mode: result.mode, reference: result.reference));
      if (!mounted) return;
      setState(() => _ledger = updated);
      widget.onChanged?.call(updated);
      _say('${_inr(result.amount)} recorded.');
    } catch (e) {
      _say(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markReturned(BookingRefund refund) async {
    setState(() => _busy = true);
    try {
      final updated = await BookingPaymentsApi.refundReturned(widget.salonId, widget.appointmentId, refund.id);
      if (!mounted) return;
      setState(() => _ledger = updated);
      widget.onChanged?.call(updated);
      _say('Refund marked as returned.');
    } catch (e) {
      _say(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _ledger;
    final (Color tone, Color toneBg) = switch (l?.status) {
      'paid' || 'not_required' => (AppTheme.lightSuccess, AppTheme.lightSuccessBg),
      'partially_paid' => (Colors.orange.shade800, Colors.orange.shade50),
      _ => (Colors.red.shade700, Colors.red.shade50),
    };

    return Container(
      key: const ValueKey('booking_payments_card'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Payments', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (l != null)
                Container(
                  key: const ValueKey('payment_status_badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: toneBg, borderRadius: BorderRadius.circular(20)),
                  child: Text(l.statusLabel,
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: tone)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (l == null && _error == null)
            // Text rather than a spinner: this sits low on a long screen and
            // does not need to draw the eye while it loads.
            Text('Loading payments…', style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody))
          else if (l == null)
            Row(children: [
              Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.lightTextBody, fontSize: 13))),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ])
          else ...[
            if (l.advanceOutstanding > 0)
              Container(
                key: const ValueKey('advance_outstanding'),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  'Advance of ${_inr(l.advanceOutstanding)} not yet received.',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                ),
              ),
            _row('Total', _inr(l.total)),
            if (l.advanceDue > 0) _row('Advance asked for', _inr(l.advanceDue)),
            _row('Paid so far', _inr(l.paid)),
            _row('Still to pay', _inr(l.outstanding), bold: true),
            if (l.payments.isNotEmpty) ...[
              const Divider(height: 20),
              for (final p in l.payments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(p.source == 'online' ? Icons.language : Icons.receipt_long_outlined,
                          size: 16, color: AppTheme.lightTextBody),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_label(p.type)} · ${_label(p.mode)}'
                          '${p.paidAt != null ? ' · ${DateFormat('d MMM, h:mm a').format(p.paidAt!)}' : ''}',
                          style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.lightTextBody),
                        ),
                      ),
                      Text(_inr(p.amount), style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
            for (final r in l.refunds.where((r) => !r.isDone))
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.salonReturns
                            ? 'Refund ${_inr(r.amount)} to the customer.'
                            : 'Refund ${_inr(r.amount)} — BookALook returns this.',
                        style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.red.shade800),
                      ),
                    ),
                    if (r.salonReturns)
                      TextButton(
                        onPressed: _busy ? null : () => _markReturned(r),
                        child: const Text('Mark returned'),
                      ),
                  ],
                ),
              ),
            if (widget.canRecord && l.outstanding > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('record_payment_button'),
                  onPressed: _busy ? null : _record,
                  icon: const Icon(Icons.add_card_outlined, size: 18),
                  label: Text(l.advanceOutstanding > 0 ? 'Record advance received' : 'Record payment'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.outfit(fontSize: 13.5, color: AppTheme.lightTextBody)),
            Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
          ],
        ),
      );
}

class _Recorded {
  final double amount;
  final String type;
  final String mode;
  final String? reference;
  const _Recorded(this.amount, this.type, this.mode, this.reference);
}

class _RecordPaymentSheet extends StatefulWidget {
  final PaymentLedger ledger;
  final String Function(String) label;
  const _RecordPaymentSheet({required this.ledger, required this.label});

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  late String _type = widget.ledger.advanceOutstanding > 0 ? 'advance' : 'balance';
  String _mode = 'cash';
  late final TextEditingController _amount = TextEditingController(text: _defaultAmount());
  final TextEditingController _reference = TextEditingController();
  String? _error;

  String _defaultAmount() {
    final v = _type == 'advance' ? widget.ledger.advanceOutstanding : widget.ledger.outstanding;
    return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount received.');
      return;
    }
    if (amount > widget.ledger.outstanding + 0.009) {
      setState(() => _error = 'That is more than is owed (₹${widget.ledger.outstanding.toStringAsFixed(0)}).');
      return;
    }
    Navigator.pop(context, _Recorded(amount, _type, _mode, _reference.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    const types = {'advance': 'Advance', 'balance': 'Part payment', 'full': 'Full amount', 'other': 'Other'};

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Record a payment', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Money the customer paid the salon for this booking.',
                style: GoogleFonts.outfit(fontSize: 12.5, color: AppTheme.lightTextBody)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in types.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _type == e.key,
                    onSelected: (_) => setState(() {
                      _type = e.key;
                      _amount.text = _defaultAmount();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('record_amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            Text('Paid by', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in widget.ledger.modes)
                  ChoiceChip(
                    label: Text(widget.label(m)),
                    selected: _mode == m,
                    onSelected: (_) => setState(() => _mode = m),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
                hintText: 'UPI ref, receipt number…',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('record_submit'),
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Record payment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
