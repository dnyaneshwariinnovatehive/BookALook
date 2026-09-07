import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/payroll_api.dart';
import '../../../theme/app_theme.dart';

/// One month's pay, opened up.
///
/// The same sheet serves an admin looking at a staff member and a staff member
/// looking at themselves — a payslip should read identically either way, so
/// there is nothing to argue about.
class PayslipSheet extends StatefulWidget {
  /// Admin route: fetch this staff member's payslip.
  final String? salonId;
  final String? providerId;

  /// Staff route: a payslip already loaded for the signed-in user.
  final Payslip? payslip;

  final String month;

  const PayslipSheet({
    super.key,
    this.salonId,
    this.providerId,
    this.payslip,
    required this.month,
  });

  static Future<void> show(
    BuildContext context, {
    String? salonId,
    String? providerId,
    Payslip? payslip,
    required String month,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PayslipSheet(
        salonId: salonId,
        providerId: providerId,
        payslip: payslip,
        month: month,
      ),
    );
  }

  @override
  State<PayslipSheet> createState() => _PayslipSheetState();
}

class _PayslipSheetState extends State<PayslipSheet> {
  Payslip? _payslip;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    if (widget.payslip != null) {
      _payslip = widget.payslip;
      _isLoading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final payslip = await PayrollApi.forStaff(
        widget.salonId!,
        widget.providerId!,
        widget.month,
      );
      if (!mounted) return;
      setState(() {
        _payslip = payslip;
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
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
                  : _payslip == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error ?? 'Could not load the payslip.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
                          ),
                        )
                      : _buildBody(controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController controller) {
    final p = _payslip!;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(p.providerName,
            style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(p.monthLabel, style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade600)),

        const SizedBox(height: 20),

        _section('Salary'),
        _row('Base salary', p.baseSalary),
        _note('${p.workingDays} working days this month · '
            '₹${p.dailyRate.toStringAsFixed(2)} a day'),

        const SizedBox(height: 16),
        _section('Leave'),
        if (p.paidLeaveDays > 0)
          _note('${_days(p.paidLeaveDays)} paid leave — no deduction'),
        if (p.unpaidLeaveDays > 0)
          _row('Unpaid leave (${_days(p.unpaidLeaveDays)})', -p.unpaidLeaveDeduction,
              color: AppTheme.lightDanger)
        else
          _note('No unpaid leave.'),

        const SizedBox(height: 16),
        _section('Commission'),
        _row('Earned at ${p.commissionPercentage.toStringAsFixed(0)}%', p.commissionEarned,
            color: Colors.green.shade700),

        if (p.commissionLines.isEmpty)
          _note('No commission-earning services this month.')
        else
          ...p.commissionLines.map(_buildCommissionLine),

        if (p.otherAdjustments != 0) ...[
          const SizedBox(height: 16),
          _section('Adjustments'),
          _row('Other adjustments', p.otherAdjustments),
        ],

        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total payable',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
              Text('₹${p.totalPayable.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                      fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.accentColor)),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              p.isPaid ? Icons.check_circle : Icons.schedule,
              size: 18,
              color: p.isPaid ? Colors.green.shade700 : AppTheme.lightWarning,
            ),
            const SizedBox(width: 8),
            Text(
              p.isPaid
                  ? 'Paid${p.paymentReference != null ? ' · ${p.paymentReference}' : ''}'
                  : 'Not paid yet',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: p.isPaid ? Colors.green.shade700 : AppTheme.lightWarning,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommissionLine(CommissionLine line) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.service, style: GoogleFonts.outfit(fontSize: 13.5)),
                  Text(
                    [
                      _formatDate(line.date),
                      '₹${line.charged.toStringAsFixed(0)} at ${line.rate.toStringAsFixed(0)}%',
                      if (line.addedMidAppointment) 'added mid-appointment',
                      if (line.source == 'walk_in') 'walk-in',
                    ].join(' · '),
                    style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Text('₹${line.commission.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  String _formatDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? iso : DateFormat('d MMM').format(parsed);
  }

  String _days(double value) =>
      value == value.roundToDouble() ? '${value.toInt()} day${value == 1 ? '' : 's'}' : '$value days';

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title.toUpperCase(),
            style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: Colors.grey.shade500)),
      );

  Widget _row(String label, double amount, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: GoogleFonts.outfit(fontSize: 14))),
            Text(
              '${amount < 0 ? '− ' : ''}₹${amount.abs().toStringAsFixed(2)}',
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Text(text, style: GoogleFonts.outfit(fontSize: 11.5, color: Colors.grey.shade600)),
      );
}
