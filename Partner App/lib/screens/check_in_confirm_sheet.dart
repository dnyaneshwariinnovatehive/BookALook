import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/check_in_api.dart';
import '../theme/app_theme.dart';
import 'collect_payment_sheet.dart';

/// Confirms who walked in and who will serve them, then starts the session.
///
/// The staff member the customer booked is preselected, but an admin can hand
/// the job to whoever is actually free — the reassignment follows through to
/// the service lines, so commission is paid to the person who did the work.
///
/// Returns true when a session was started (or the appointment was already
/// running and the caller moved on to billing).
class CheckInConfirmSheet extends StatefulWidget {
  final String salonId;
  final CheckInTarget target;
  final String? qrToken;

  const CheckInConfirmSheet({
    super.key,
    required this.salonId,
    required this.target,
    this.qrToken,
  });

  static Future<bool> show(
    BuildContext context, {
    required String salonId,
    required CheckInTarget target,
    String? qrToken,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CheckInConfirmSheet(
        salonId: salonId,
        target: target,
        qrToken: qrToken,
      ),
    );

    return result == true;
  }

  @override
  State<CheckInConfirmSheet> createState() => _CheckInConfirmSheetState();
}

class _CheckInConfirmSheetState extends State<CheckInConfirmSheet> {
  String? _servingProviderId;
  bool _isSubmitting = false;
  String? _error;

  CheckInAppointment get _apt => widget.target.appointment;
  Bill get _bill => widget.target.bill;

  @override
  void initState() {
    super.initState();
    _servingProviderId = widget.target.defaultServingProviderId ??
        (widget.target.providers.isNotEmpty ? widget.target.providers.first.id : null);
  }

  bool get _isReassigned =>
      _servingProviderId != null && _servingProviderId != _apt.bookedProviderId;

  Future<void> _start() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await CheckInApi.start(
        widget.salonId,
        _apt.id,
        qrToken: widget.qrToken,
        servingProviderId: _servingProviderId,
        manual: widget.qrToken == null,
        reason: widget.qrToken == null ? 'Started from the appointment list' : null,
      );

      if (!mounted) return;
      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Session started for ${_apt.customerName}.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Already running — the only thing left to do is take the money.
  Future<void> _goToBilling() async {
    Navigator.pop(context, true);
    await CollectPaymentSheet.show(
      context,
      salonId: widget.salonId,
      appointmentId: _apt.id,
    );
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
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  _buildCustomer(),
                  const SizedBox(height: 20),
                  _buildServices(),
                  const SizedBox(height: 20),
                  if (_apt.isInProgress)
                    _buildAlreadyRunning()
                  else ...[
                    _buildProviderPicker(),
                    if (!widget.target.canStart && widget.target.blockedReason != null) ...[
                      const SizedBox(height: 16),
                      _buildNotice(widget.target.blockedReason!, AppTheme.lightWarning),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildNotice(_error!, AppTheme.lightDanger),
                  ],
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomer() => Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.accentColor.withValues(alpha: 0.12),
            child: Text(
              _apt.customerName.isNotEmpty ? _apt.customerName[0].toUpperCase() : '?',
              style: GoogleFonts.outfit(
                  fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_apt.customerName,
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  [
                    '${_apt.startTime} – ${_apt.endTime}',
                    if (_apt.customerPhone != null && _apt.customerPhone!.isNotEmpty)
                      _apt.customerPhone!,
                  ].join(' · '),
                  style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildServices() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            ..._bill.lines.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.addedMidAppointment ? '${line.name}  (added)' : line.name,
                          style: GoogleFonts.outfit(fontSize: 14),
                        ),
                      ),
                      Text('₹${line.price.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            const Divider(height: 16),
            _amountRow('Total', _bill.total, bold: true),
            const SizedBox(height: 4),
            _amountRow('Advance already paid', _bill.advancePaid, color: Colors.green.shade700),
            const SizedBox(height: 4),
            _amountRow('To collect at the counter', _bill.balanceDue,
                bold: true, color: AppTheme.accentColor),
          ],
        ),
      );

  Widget _amountRow(String label, double amount, {bool bold = false, Color? color}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade700)),
          Text('₹${amount.toStringAsFixed(2)}',
              style: GoogleFonts.outfit(
                fontSize: bold ? 16 : 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color,
              )),
        ],
      );

  Widget _buildProviderPicker() {
    final providers = widget.target.providers;

    if (providers.isEmpty) {
      return _buildNotice('This salon has no active staff to assign.', AppTheme.lightWarning);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who is serving?', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'Booked with ${_apt.bookedProviderName}. Change it if someone else is taking over — '
          'their commission follows the change.',
          style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _servingProviderId,
              isExpanded: true,
              onChanged: _isSubmitting
                  ? null
                  : (value) => setState(() => _servingProviderId = value),
              items: providers
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (p.isBookedProvider)
                              _tag('Booked', AppTheme.accentColor)
                            else if (!p.canPerformAll)
                              _tag('Not trained', AppTheme.lightWarning),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        if (_isReassigned) ...[
          const SizedBox(height: 10),
          _buildNotice(
            'This job will be credited to the staff member you picked, not '
            '${_apt.bookedProviderName}.',
            AppTheme.lightWarning,
          ),
        ],
      ],
    );
  }

  Widget _tag(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );

  Widget _buildAlreadyRunning() => _buildNotice(
        'This appointment is already in progress with '
        '${_apt.servingProviderName ?? _apt.bookedProviderName}. '
        'Continue to the bill when they are finished.',
        AppTheme.accentColor,
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
    final canStart = widget.target.canStart && !_isSubmitting && _servingProviderId != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _apt.isInProgress
                    ? _goToBilling
                    : canStart
                        ? _start
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _apt.isInProgress ? 'Go to bill' : 'Start appointment',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
