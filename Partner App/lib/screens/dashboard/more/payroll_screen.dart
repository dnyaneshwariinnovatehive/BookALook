import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/payroll_api.dart';
import '../../../theme/app_theme.dart';
import 'payslip_sheet.dart';

/// Monthly staff pay for the whole salon.
///
///     payable = base salary − unpaid leave + commission earned
///
/// Every figure is opened up in the payslip sheet, because a staff member will
/// ask how it was worked out and the admin needs to be able to answer.
class PayrollScreen extends StatefulWidget {
  final String salonId;

  const PayrollScreen({super.key, required this.salonId});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  PayrollMonth? _payroll;
  bool _isLoading = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _monthParam => DateFormat('yyyy-MM').format(_month);

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final payroll = await PayrollApi.forSalon(widget.salonId, _monthParam);
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

  void _shiftMonth(int months) {
    final next = DateTime(_month.year, _month.month + months);
    final now = DateTime(DateTime.now().year, DateTime.now().month);

    // There is no payroll for a month that has not started.
    if (next.isAfter(now)) return;

    setState(() => _month = next);
    _load();
  }

  Future<void> _togglePaid(Payslip payslip) async {
    if (payslip.isPaid) {
      final undo = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mark as unpaid?'),
          content: Text('${payslip.providerName}\'s salary for ${payslip.monthLabel} '
              'will go back to pending.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark unpaid')),
          ],
        ),
      );

      if (undo != true) return;
      await _setPaid(payslip, paid: false);
      return;
    }

    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark salary paid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${payslip.providerName} · ${payslip.monthLabel}',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('₹${payslip.totalPayable.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Payment reference (optional)',
                hintText: 'e.g. UPI or NEFT number',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark paid')),
        ],
      ),
    );

    if (confirmed != true) return;
    await _setPaid(payslip, paid: true, reference: controller.text.trim());
  }

  Future<void> _setPaid(Payslip payslip, {required bool paid, String? reference}) async {
    setState(() => _busyId = payslip.id);

    try {
      await PayrollApi.setPaid(widget.salonId, payslip.id, paid: paid, reference: reference);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text('Payroll',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Column(
        children: [
          _buildMonthBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            _buildTotals(),
                            const SizedBox(height: 16),
                            if (_payroll!.payslips.isEmpty)
                              _card(
                                child: Text('No active staff this month.',
                                    style: GoogleFonts.outfit(color: Colors.grey.shade600)),
                              )
                            else
                              ..._payroll!.payslips.map(_buildRow),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthBar() => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              onPressed: () => _shiftMonth(-1),
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous month',
            ),
            Expanded(
              child: Text(
                DateFormat('MMMM yyyy').format(_month),
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: () => _shiftMonth(1),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next month',
            ),
          ],
        ),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _buildTotals() {
    final p = _payroll!;
    final outstanding = p.payable - p.paid;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${p.staff} staff',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
              Text('₹${p.payable.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900)),
            ],
          ),
          const Divider(height: 20),
          _totalRow('Base salaries', p.baseSalary),
          _totalRow('Unpaid leave', -p.deductions, color: AppTheme.lightDanger),
          _totalRow('Commission earned', p.commission, color: Colors.green.shade700),
          const Divider(height: 20),
          _totalRow('Already paid', p.paid, color: Colors.green.shade700),
          _totalRow('Still to pay', outstanding, bold: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double amount, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade700)),
            Text(
              '${amount < 0 ? '− ' : ''}₹${amount.abs().toStringAsFixed(2)}',
              style: GoogleFonts.outfit(
                fontSize: bold ? 15 : 13.5,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _buildRow(Payslip payslip) {
    final busy = _busyId == payslip.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(payslip.providerName,
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: payslip.isPaid
                        ? Colors.green.withValues(alpha: 0.12)
                        : AppTheme.lightWarning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    payslip.isPaid ? 'PAID' : 'PENDING',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: payslip.isPaid ? Colors.green.shade700 : AppTheme.lightWarning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // The arithmetic in one line, so nothing has to be taken on trust.
            Text(
              '₹${payslip.baseSalary.toStringAsFixed(0)} base'
              '${payslip.unpaidLeaveDeduction > 0 ? '  −  ₹${payslip.unpaidLeaveDeduction.toStringAsFixed(0)} leave' : ''}'
              '${payslip.commissionEarned > 0 ? '  +  ₹${payslip.commissionEarned.toStringAsFixed(0)} commission' : ''}',
              style: GoogleFonts.outfit(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text('₹${payslip.totalPayable.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900)),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => PayslipSheet.show(
                      context,
                      salonId: widget.salonId,
                      providerId: payslip.providerId,
                      month: _monthParam,
                    ),
                    child: const Text('Breakdown'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: busy ? null : () => _togglePaid(payslip),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          payslip.isPaid ? Colors.grey.shade400 : Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(payslip.isPaid ? 'Mark unpaid' : 'Mark paid'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}
