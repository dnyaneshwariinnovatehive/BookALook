import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/payroll_api.dart';
import '../../../theme/app_theme.dart';
import 'payslip_sheet.dart';

/// A staff member's own pay — this month and the months before it.
///
/// Deliberately the same numbers and the same payslip the admin sees, so there
/// is one version of the truth rather than two.
class MySalaryScreen extends StatefulWidget {
  final String salonId;

  const MySalaryScreen({super.key, required this.salonId});

  @override
  State<MySalaryScreen> createState() => _MySalaryScreenState();
}

class _MySalaryScreenState extends State<MySalaryScreen> {
  MyPayroll? _payroll;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final month = DateFormat('yyyy-MM').format(DateTime.now());
      final payroll = await PayrollApi.mine(month);
      if (!mounted) return;
      setState(() {
        _payroll = payroll;
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text('My salary',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _payroll == null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildCurrent(_payroll!.current),
                      const SizedBox(height: 20),
                      if (_payroll!.history.isNotEmpty) ...[
                        Text('EARLIER MONTHS',
                            style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.6,
                                color: Colors.grey.shade500)),
                        const SizedBox(height: 10),
                        ..._payroll!.history.map(_buildHistoryRow),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(_error ?? 'Could not load your salary.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _buildCurrent(Payslip p) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeroCard(p),
          const SizedBox(height: 16),
          _buildSummaryRow(p),
          const SizedBox(height: 16),
          _buildBreakdownCard(p),
        ],
      );

  Widget _buildHeroCard(Payslip p) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.accentColor, AppTheme.accentGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(p.monthLabel.toUpperCase(),
                    style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    p.isPaid ? 'PAID ✓' : 'NOT PAID YET',
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Take-home pay',
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 2),
            Text('₹${p.totalPayable.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              p.isPaid
                  ? 'This amount has been paid to you.'
                  : 'Expected payment for this month.',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => PayslipSheet.show(
                    context,
                    payslip: p,
                    month: DateFormat('yyyy-MM').format(DateTime.now()),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text('See breakdown',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildSummaryRow(Payslip p) => Row(
        children: [
          _summaryItem(Icons.calendar_today_outlined, '${p.workingDays}', 'working days'),
          _summaryItem(Icons.currency_rupee, '₹${p.dailyRate.toStringAsFixed(0)}', 'per day'),
          _summaryItem(Icons.percent, '${p.commissionPercentage.toStringAsFixed(0)}%', 'on services'),
        ],
      );

  Widget _summaryItem(IconData icon, String value, String label) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Column(
            children: [
              Icon(icon, size: 17, color: AppTheme.accentColor),
              const SizedBox(height: 6),
              Text(value,
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800)),
              Text(label,
                  style: GoogleFonts.outfit(fontSize: 10.5, color: Colors.grey.shade600)),
            ],
          ),
        ),
      );

  Widget _buildBreakdownCard(Payslip p) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HOW YOUR PAY IS CALCULATED',
                style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: Colors.grey.shade500)),
            const SizedBox(height: 16),

            // Earnings
            _subHeader(Icons.add_circle_outline, 'EARNINGS', Colors.green.shade700),
            const SizedBox(height: 8),
            _breakdownRow(context, 'Base salary', p.baseSalary, positive: true),
            if (p.commissionEarned > 0)
              _breakdownRow(context,
                  'Commission (${p.commissionPercentage.toStringAsFixed(0)}%)',
                  p.commissionEarned,
                  positive: true),
            if (p.otherAdjustments > 0)
              _breakdownRow(context, 'Other adjustments', p.otherAdjustments, positive: true),

            if (p.unpaidLeaveDeduction > 0 || p.otherAdjustments < 0) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              _subHeader(Icons.remove_circle_outline, 'DEDUCTIONS', AppTheme.lightDanger),
              const SizedBox(height: 8),
              if (p.unpaidLeaveDeduction > 0)
                _breakdownRow(context,
                    'Unpaid leave (${p.unpaidLeaveDays == p.unpaidLeaveDays.roundToDouble() ? p.unpaidLeaveDays.toInt() : p.unpaidLeaveDays} d)',
                    p.unpaidLeaveDeduction,
                    positive: false),
              if (p.otherAdjustments < 0)
                _breakdownRow(context, 'Other adjustments', p.otherAdjustments.abs(),
                    positive: false),
            ],

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),

            // Net
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.currency_rupee, size: 17, color: AppTheme.accentColor),
                    const SizedBox(width: 6),
                    Text('Total payable',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
                Text('₹${p.totalPayable.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.accentColor)),
              ],
            ),
          ],
        ),
      );

  Widget _subHeader(IconData icon, String title, Color color) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(title,
              style: GoogleFonts.outfit(
                  fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: color)),
        ],
      );

  Widget _breakdownRow(BuildContext context, String label, double amount, {required bool positive}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  style: GoogleFonts.outfit(fontSize: 13.5, color: Colors.grey.shade800)),
            ),
            Text(
              '${positive ? '+' : '−'} ₹${amount.toStringAsFixed(2)}',
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: positive ? Colors.green.shade700 : AppTheme.lightDanger,
              ),
            ),
          ],
        ),
      );

  Widget _buildHistoryRow(Payslip p) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => PayslipSheet.show(context, payslip: p, month: p.monthLabel),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.lightBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.calendar_month_outlined,
                      size: 20, color: AppTheme.accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.monthLabel,
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(
                        'base ₹${p.baseSalary.toStringAsFixed(0)}'
                        '${p.commissionEarned > 0 ? ' · commission ₹${p.commissionEarned.toStringAsFixed(0)}' : ''}',
                        style: GoogleFonts.outfit(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${p.totalPayable.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
                    Text(p.isPaid ? 'Paid' : 'Pending',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: p.isPaid ? Colors.green.shade700 : AppTheme.lightWarning,
                        )),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      );
}
