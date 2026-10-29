import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../screens/contact_bookalook_screen.dart';
import '../screens/dashboard/more/salon_payouts_screen.dart';
import '../services/salon_support_api.dart';
import '../theme/app_theme.dart';

/// Settlements with BookALook, on the lock screen.
///
/// A locked salon can still be owed money (or owe it), and the owner had no
/// way to see that or ask about it without renewing first. This shows how
/// many settlements are open and which way the money goes, opens the full
/// Payouts screen, and lets them write to BookALook.
class SettlementsCard extends StatefulWidget {
  final String salonId;

  @visibleForTesting
  final Future<SettlementSummary> Function(String salonId)? loader;

  const SettlementsCard({super.key, required this.salonId, this.loader});

  @override
  State<SettlementsCard> createState() => _SettlementsCardState();
}

class _SettlementsCardState extends State<SettlementsCard> {
  SettlementSummary? _summary;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final summary = await (widget.loader ?? SalonSupportApi.summary)(widget.salonId);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _inr(double v) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v);

  Future<void> _openPayouts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SalonPayoutsScreen(salonId: widget.salonId)),
    );
    _load();
  }

  Future<void> _contact() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactBookALookScreen(
          salonId: widget.salonId,
          settlements: _summary?.settlements ?? const [],
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;

    return Container(
      key: const ValueKey('locked_settlements_card'),
      width: double.infinity,
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, size: 20, color: AppTheme.accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Settlements with BookALook',
                    style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.bold)),
              ),
              if (s != null)
                Container(
                  key: const ValueKey('settlements_pending_badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: s.pendingCount > 0 ? AppTheme.lightWarning.withValues(alpha: 0.15) : AppTheme.lightSuccessBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    s.pendingCount > 0 ? '${s.pendingCount} pending' : 'All settled',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: s.pendingCount > 0 ? AppTheme.lightWarning : AppTheme.lightSuccess,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (s == null && !_failed)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_failed)
            Row(
              children: [
                const Expanded(
                  child: Text('Could not load settlements.',
                      style: TextStyle(fontSize: 13, color: AppTheme.lightTextBody)),
                ),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            )
          else ...[
            if (s!.pendingCount == 0)
              Text('Nothing is pending either way.',
                  style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody)),
            if (s.owedToSalonCount > 0)
              _line(
                icon: Icons.south_west_rounded,
                color: AppTheme.lightSuccess,
                label: 'BookALook owes you',
                detail: '${s.owedToSalonCount} cycle${s.owedToSalonCount == 1 ? '' : 's'}',
                amount: _inr(s.owedToSalon),
              ),
            if (s.owedBySalonCount > 0)
              _line(
                icon: Icons.north_east_rounded,
                color: AppTheme.lightWarning,
                label: 'You owe BookALook',
                detail: s.underReview > 0
                    ? '${s.owedBySalonCount} cycle${s.owedBySalonCount == 1 ? '' : 's'} · ${s.underReview} payment under review'
                    : '${s.owedBySalonCount} cycle${s.owedBySalonCount == 1 ? '' : 's'}',
                amount: _inr(s.owedBySalon),
              ),
            if (s.openRequests > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${s.openRequests} message${s.openRequests == 1 ? '' : 's'} to BookALook awaiting a reply',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('locked_view_settlements'),
                  onPressed: _openPayouts,
                  icon: const Icon(Icons.receipt_long_outlined, size: 17),
                  label: const Text('View settlements'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('locked_contact_bookalook'),
                  onPressed: _contact,
                  icon: const Icon(Icons.chat_bubble_outline, size: 17),
                  label: const Text('Contact BookALook'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line({
    required IconData icon,
    required Color color,
    required String label,
    required String detail,
    required String amount,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(detail, style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextBody)),
              ],
            ),
          ),
          Text(amount, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
