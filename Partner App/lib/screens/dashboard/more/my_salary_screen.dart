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

  Widget _buildCurrent(Payslip p) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.accentColor, AppTheme.accentColor.withValues(alpha: 0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.monthLabel.toUpperCase(),
                style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            const SizedBox(height: 6),
            Text('₹${p.totalPayable.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),

            _whiteRow('Base salary', p.baseSalary),
            if (p.unpaidLeaveDeduction > 0)
              _whiteRow('Unpaid leave (${p.unpaidLeaveDays} d)', -p.unpaidLeaveDeduction),
            if (p.commissionEarned > 0) _whiteRow('Commission', p.commissionEarned),

            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(p.isPaid ? 'PAID' : 'NOT PAID YET',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => PayslipSheet.show(
                    context,
                    payslip: p,
                    month: DateFormat('yyyy-MM').format(DateTime.now()),
                  ),
                  child: Text('See breakdown',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _whiteRow(String label, double amount) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12.5)),
            Text('${amount < 0 ? '− ' : ''}₹${amount.abs().toStringAsFixed(2)}',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
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
            ),
            child: Row(
              children: [
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
              ],
            ),
          ),
        ),
      );
}
