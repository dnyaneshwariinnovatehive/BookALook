import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/payroll_api.dart';
import '../../../theme/app_theme.dart';

/// What BookALook settled with this salon, week by week.
///
/// The salon's side of the same record SuperAdmin works from — most importantly
/// the commission that was deducted, so the net figure that arrives in the bank
/// can be checked rather than taken on trust.
class SalonPayoutsScreen extends StatefulWidget {
  final String salonId;

  const SalonPayoutsScreen({super.key, required this.salonId});

  @override
  State<SalonPayoutsScreen> createState() => _SalonPayoutsScreenState();
}

class _SalonPayoutsScreenState extends State<SalonPayoutsScreen> {
  SalonPayouts? _data;
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
      final data = await PayrollApi.salonPayouts(widget.salonId);
      if (!mounted) return;
      setState(() {
        _data = data;
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
        title: Text('Payouts',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildTotals(),
                      const SizedBox(height: 12),
                      _buildBillingBanner(),
                      const SizedBox(height: 16),
                      if (_data!.payouts.isEmpty)
                        _card(
                          child: Text(
                            _data!.onCommissionModel
                                ? 'No settlements yet. A month appears here once '
                                    'BookALook settles it, on the 1st.'
                                : 'No payouts yet. A cycle appears once BookALook settles '
                                    'a week of completed appointments.',
                            style: GoogleFonts.outfit(color: Colors.grey.shade700),
                          ),
                        )
                      else
                        ..._data!.payouts.map(_buildCycle),
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
              Text(_error ?? 'Could not load payouts.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _buildTotals() => _card(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RECEIVED SO FAR',
                      style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: Colors.grey.shade500)),
                  const SizedBox(height: 4),
                  Text('₹${_data!.receivedLifetime.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('COMMISSION PAID',
                      style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: Colors.grey.shade500)),
                  const SizedBox(height: 4),
                  Text('₹${_data!.commissionLifetime.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.lightDanger)),
                ],
              ),
            ),
          ],
        ),
      );

  /// Which arrangement the salon is on, and what that means for its money.
  ///
  /// Without this the two rhythms look like a bug: a commission salon sees one
  /// row a month where its neighbour sees four.
  Widget _buildBillingBanner() {
    final commission = _data!.onCommissionModel;
    final rate = _data!.commissionPercentage;

    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            commission ? Icons.percent_rounded : Icons.verified_rounded,
            size: 20,
            color: commission ? AppTheme.lightWarning : Colors.green.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _data!.billingLabel,
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  commission
                      ? 'You pay ${rate == null ? '' : '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}% of '}'
                          'everything you bill. Settled on the 1st of each month for the '
                          'month just finished.'
                      : 'Your plan is already paid for, so nothing is deducted. Each week '
                          'BookALook returns the advances it collected for you.',
                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycle(SalonPayoutRecord p) {
    final distributed = p.status == 'distributed';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.cycleLabel.isNotEmpty
                        ? p.cycleLabel
                        : '${_formatDate(p.cycleStart)} – ${_formatDate(p.cycleEnd)}',
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: distributed
                        ? Colors.green.withValues(alpha: 0.12)
                        : AppTheme.lightWarning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    p.status.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: distributed ? Colors.green.shade700 : AppTheme.lightWarning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            _line('${p.appointments} completed appointment${p.appointments == 1 ? '' : 's'}',
                p.revenue, muted: true),
            _line('Advance collected online by BookALook', p.advancesHeld),

            if (p.commissionDeducted > 0)
              _line(
                'Commission at ${p.commissionPercentage.toStringAsFixed(0)}%',
                -p.commissionDeducted,
                color: AppTheme.lightDanger,
              ),

            if (p.walletRedeemed > 0)
              _line('Coins settled against commission', p.walletRedeemed,
                  color: Colors.green.shade700),

            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(distributed ? 'Paid to you' : 'Due to you',
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('₹${p.netAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900)),
              ],
            ),

            if (p.reference != null && p.reference!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Reference ${p.reference}',
                  style: GoogleFonts.outfit(fontSize: 11.5, color: Colors.grey.shade600)),
            ],

            if (p.billingType != 'commission') ...[
              const SizedBox(height: 6),
              // Nothing is deducted because access was already paid for.
              Text('Subscription Plan — no commission is deducted.',
                  style: GoogleFonts.outfit(fontSize: 11.5, color: Colors.grey.shade600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(String label, double amount, {Color? color, bool muted = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      color: muted ? Colors.grey.shade500 : Colors.grey.shade700)),
            ),
            Text(
              '${amount < 0 ? '− ' : ''}₹${amount.abs().toStringAsFixed(2)}',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: muted ? FontWeight.normal : FontWeight.w600,
                color: color ?? (muted ? Colors.grey.shade500 : null),
              ),
            ),
          ],
        ),
      );

  String _formatDate(String iso) {
    final parsed = DateTime.tryParse(iso);
    return parsed == null ? iso : DateFormat('d MMM').format(parsed);
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
