import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/check_in_api.dart';
import '../theme/app_theme.dart';
import 'add_extra_service_sheet.dart';

/// The bill at the counter: what the customer owes, how they paid, done.
///
/// Collecting the balance and finishing the appointment are one action — the
/// salon does not run a tab, so there is no state where the job is closed but
/// the money is not in.
///
/// Returns true when payment was taken.
class CollectPaymentSheet extends StatefulWidget {
  final String salonId;
  final String appointmentId;

  const CollectPaymentSheet({
    super.key,
    required this.salonId,
    required this.appointmentId,
  });

  static Future<bool> show(
    BuildContext context, {
    required String salonId,
    required String appointmentId,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CollectPaymentSheet(
        salonId: salonId,
        appointmentId: appointmentId,
      ),
    );

    return result == true;
  }

  @override
  State<CollectPaymentSheet> createState() => _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends State<CollectPaymentSheet> {
  static const _modes = <String, ({String label, IconData icon})>{
    'cash': (label: 'Cash', icon: Icons.payments_outlined),
    'upi': (label: 'UPI', icon: Icons.qr_code_2),
    'card': (label: 'Card', icon: Icons.credit_card),
  };

  CheckInTarget? _target;
  String _mode = 'cash';
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final target = await CheckInApi.bill(widget.salonId, widget.appointmentId);
      if (!mounted) return;
      setState(() {
        _target = target;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  /// Extras agreed in the chair. Each becomes its own line rather than
  /// inflating what was originally booked.
  Future<void> _addExtra() async {
    final apt = _target!.appointment;

    final updated = await AddExtraServiceSheet.show(
      context,
      salonId: widget.salonId,
      appointmentId: widget.appointmentId,
      servingProviderId: apt.servingProviderId,
      servingProviderName: apt.servingProviderName,
    );

    if (updated == null || !mounted) return;

    setState(() => _target = updated);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to the bill.')),
    );
  }

  Future<void> _removeExtra(BillLine line) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from bill?'),
        content: Text(
          '${line.name} (₹${line.price.toStringAsFixed(0)}) will come off the total. '
          'It stays on the record as removed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: AppTheme.lightDanger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      final updated = await CheckInApi.removeExtraService(
        widget.salonId,
        widget.appointmentId,
        line.id,
      );
      if (!mounted) return;
      setState(() {
        _target = updated;
        _isSubmitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _collect() async {
    final bill = _target!.bill;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm payment'),
        content: Text(
          bill.balanceDue > 0
              ? 'Collect ₹${bill.balanceDue.toStringAsFixed(2)} by '
                  '${_modes[_mode]!.label.toLowerCase()} and close this appointment?'
              : 'Nothing left to collect. Close this appointment?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final result = await CheckInApi.collectPayment(
        widget.salonId,
        widget.appointmentId,
        paymentMode: _mode,
      );

      if (!mounted) return;
      Navigator.pop(context, true);

      final coins = result['coins_earned'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(coins > 0
            ? 'Payment collected. The salon earned $coins coins.'
            : 'Payment collected. Appointment completed.'),
        backgroundColor: Colors.green.shade700,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _target == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error ?? 'Could not load the bill.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
                          ),
                        )
                      : _buildBody(scrollController),
            ),
            if (_target != null && !_isLoading) _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController controller) {
    final apt = _target!.appointment;
    final bill = _target!.bill;
    final settled = apt.status == 'completed';

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      children: [
        Text('Bill summary', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          '${apt.customerName} · ${apt.startTime}'
          '${apt.servingProviderName != null ? ' · served by ${apt.servingProviderName}' : ''}',
          style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),

        // Booked and added are shown as separate, clearly itemised groups so
        // the customer can see exactly what changed while they were in the chair.
        ...bill.lines.where((l) => !l.addedMidAppointment).map(_buildLine),

        if (bill.lines.any((l) => l.addedMidAppointment)) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.add_circle_outline, size: 15, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              Text('ADDED DURING THE APPOINTMENT',
                  style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: AppTheme.accentColor)),
            ],
          ),
          const SizedBox(height: 10),
          ...bill.lines.where((l) => l.addedMidAppointment).map(_buildLine),
        ],

        if (!settled) ...[
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _isSubmitting || apt.status != 'in_progress' ? null : _addExtra,
            icon: const Icon(Icons.add, size: 18),
            label: Text('Add extra service',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentColor,
              side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)),
              minimumSize: const Size(double.infinity, 46),
            ),
          ),
        ],

        const Divider(height: 28),
        if (bill.lines.any((l) => l.addedMidAppointment)) ...[
          _amountRow('Booked services',
              bill.lines.where((l) => !l.addedMidAppointment).fold(0.0, (t, l) => t + l.price)),
          const SizedBox(height: 4),
          _amountRow('Added during the appointment',
              bill.lines.where((l) => l.addedMidAppointment).fold(0.0, (t, l) => t + l.price),
              color: AppTheme.accentColor),
          const SizedBox(height: 8),
        ],
        _amountRow('Total', bill.total, size: 16, bold: true),
        const SizedBox(height: 6),
        _amountRow('Advance already paid', -bill.advancePaid, color: Colors.green.shade700),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(settled ? 'Collected' : 'Balance to collect',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
              Text('₹${bill.balanceDue.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                      fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
            ],
          ),
        ),

        if (settled) ...[
          const SizedBox(height: 16),
          _buildNotice(
            'Already settled${apt.paymentMode != null ? ' by ${apt.paymentMode}' : ''}.',
            Colors.green.shade700,
          ),
        ] else ...[
          const SizedBox(height: 24),
          Text('Payment method',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: _modes.entries.map((entry) {
              final selected = _mode == entry.key;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _isSubmitting ? null : () => setState(() => _mode = entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.accentColor.withValues(alpha: 0.10)
                            : Colors.transparent,
                        border: Border.all(
                          color: selected ? AppTheme.accentColor : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(entry.value.icon,
                              size: 22,
                              color: selected ? AppTheme.accentColor : Colors.grey.shade600),
                          const SizedBox(height: 6),
                          Text(entry.value.label,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                                color: selected ? AppTheme.accentColor : Colors.grey.shade700,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],

        if (_error != null) ...[
          const SizedBox(height: 16),
          _buildNotice(_error!, AppTheme.lightDanger),
        ],
      ],
    );
  }

  Widget _buildLine(BillLine line) {
    final settled = _target?.appointment.status == 'completed';
    final canRemove = line.addedMidAppointment &&
        !settled &&
        _target?.appointment.status == 'in_progress' &&
        !_isSubmitting;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name,
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [
                    '${line.durationMinutes} min',
                    if (line.providerName != null) 'by ${line.providerName}',
                  ].join(' · '),
                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
                ),
                // Who put an extra on the bill and when — the record should
                // answer that without anyone having to remember.
                if (line.addedMidAppointment && line.addedByName != null)
                  Text(
                    'added by ${line.addedByName}'
                    '${line.addedAt != null ? ' at ${DateFormat('h:mm a').format(line.addedAt!.toLocal())}' : ''}',
                    style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('₹${line.price.toStringAsFixed(0)}',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
          if (canRemove)
            IconButton(
              tooltip: 'Remove from bill',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: AppTheme.lightDanger),
              onPressed: () => _removeExtra(line),
            ),
        ],
      ),
    );
  }

  Widget _amountRow(String label, double amount,
          {double size = 14, bool bold = false, Color? color}) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade700)),
          Text(
            '${amount < 0 ? '− ' : ''}₹${amount.abs().toStringAsFixed(2)}',
            style: GoogleFonts.outfit(
              fontSize: size,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      );

  Widget _buildNotice(String text, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: GoogleFonts.outfit(fontSize: 12.5, color: color)),
      );

  Widget _buildFooter() {
    final apt = _target!.appointment;
    final settled = apt.status == 'completed';
    final canCollect = apt.status == 'in_progress' && !_isSubmitting;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: settled
                ? () => Navigator.pop(context, false)
                : canCollect
                    ? _collect
                    : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: settled ? Colors.grey.shade600 : Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              disabledBackgroundColor: Colors.grey.shade300,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    settled
                        ? 'Done'
                        : apt.status == 'in_progress'
                            ? 'Mark payment collected'
                            : 'Start the appointment first',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    );
  }
}
