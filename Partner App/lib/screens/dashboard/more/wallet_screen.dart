import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/services/api_config.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'upgrade_plan_screen.dart';

/// The salon's reward wallet: coins earned on completed online bookings, and
/// the two places they can be spent.
///
/// Coins are not cash and are never paid out — that is the separate payout
/// system. The screen says so plainly, because a balance shown in rupees
/// otherwise reads like money the salon can withdraw.
class WalletScreen extends StatefulWidget {
  final String salonId;
  const WalletScreen({super.key, required this.salonId});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  bool _isLoading = true;
  String? _error;

  int _balance = 0;
  double _coinValue = 0;
  double _balanceValue = 0;
  bool _canRedeemAgainstCommission = false;
  Map<String, dynamic> _progress = const {};
  List<dynamic> _earned = const [];
  List<dynamic> _redeemed = const [];

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/partner/salons/${widget.salonId}/wallet'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200 || data['success'] != true) {
        throw Exception(data['message'] ?? 'Could not load the wallet.');
      }

      if (!mounted) return;
      setState(() {
        _balance = (data['balance'] ?? 0) as int;
        _coinValue = double.tryParse('${data['coin_value_inr'] ?? 0}') ?? 0;
        _balanceValue = double.tryParse('${data['balance_value_inr'] ?? 0}') ?? 0;
        _canRedeemAgainstCommission = data['can_redeem_against_commission'] == true;
        _progress = (data['progress'] as Map<String, dynamic>?) ?? const {};
        _earned = data['earned'] ?? const [];
        _redeemed = data['redeemed'] ?? const [];
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
        title: Text('Rewards wallet',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildBalanceCard(),
                      const SizedBox(height: 16),
                      _buildProgressCard(),
                      const SizedBox(height: 16),
                      _buildRedeemCard(),
                      const SizedBox(height: 20),
                      _buildHistory(),
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
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetch, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _buildBalanceCard() => Container(
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
            Text('COIN BALANCE',
                style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$_balance',
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Text('coins',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Worth ₹${_balanceValue.toStringAsFixed(2)} at ₹$_coinValue per coin',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Coins are not cash. They can only be used on your next plan '
                'purchase or against commission owed.',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 11.5, height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _buildProgressCard() {
    final scheme = _progress['scheme'] as Map<String, dynamic>?;

    if (scheme == null) {
      return _card(
        child: Text(
          'No reward scheme is running right now. Completed online bookings will '
          'start earning as soon as one is published.',
          style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade700),
        ),
      );
    }

    final current = _progress['current_tier'] as Map<String, dynamic>?;
    final next = _progress['next_tier'] as Map<String, dynamic>?;
    final toNext = _progress['appointments_to_next_tier'];
    final completed = _progress['completed_online_appointments'] ?? 0;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(scheme['name'] ?? 'Reward scheme',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
          if (scheme['description'] != null) ...[
            const SizedBox(height: 2),
            Text(scheme['description'],
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat('$completed', 'online bookings\ncompleted'),
              ),
              if (current != null)
                Expanded(
                  child: _stat('${current['coins_awarded']}', 'coins per\nbooking now'),
                ),
            ],
          ),
          if (next != null && toNext != null) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: _progressFraction(current, completed as int),
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(AppTheme.accentColor),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              '$toNext more booking${toNext == 1 ? '' : 's'} to reach '
              '${next['coins_awarded']} coins each.',
              style: GoogleFonts.outfit(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }

  /// How far through the current band the salon is.
  double _progressFraction(Map<String, dynamic>? tier, int completed) {
    if (tier == null) return 0;
    final from = (tier['appointments_from'] ?? 1) as int;
    final to = tier['appointments_to'] as int?;
    if (to == null || to <= from) return 0;
    return ((completed - from + 1) / (to - from + 1)).clamp(0.0, 1.0);
  }

  Widget _buildRedeemCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where coins can be used',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.workspace_premium_outlined, color: AppTheme.accentColor),
              title: Text('Your next plan purchase',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text('Applied as a discount at checkout',
                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _balance <= 0
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UpgradePlanScreen(salonId: widget.salonId),
                        ),
                      ).then((_) => _fetch()),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.receipt_long_outlined,
                color: _canRedeemAgainstCommission ? AppTheme.accentColor : Colors.grey.shade400,
              ),
              title: Text('Commission you owe',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _canRedeemAgainstCommission ? null : Colors.grey.shade500,
                  )),
              subtitle: Text(
                _canRedeemAgainstCommission
                    ? 'Settle against a weekly payout’s commission'
                    : 'Only available on a Commission Plan',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      );

  Widget _buildHistory() => _card(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.accentColor,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: AppTheme.accentColor,
              labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: [
                Tab(text: 'Earned (${_earned.length})'),
                Tab(text: 'Redeemed (${_redeemed.length})'),
              ],
            ),
            SizedBox(
              height: 340,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_earned, emptyLabel: 'No coins earned yet.'),
                  _buildList(_redeemed, emptyLabel: 'No coins spent yet.'),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildList(List<dynamic> entries, {required String emptyLabel}) {
    if (entries.isEmpty) {
      return Center(
        child: Text(emptyLabel, style: GoogleFonts.outfit(color: Colors.grey.shade600)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index] as Map<String, dynamic>;
        final coins = (entry['coins'] ?? 0) as int;
        final earned = coins > 0;
        final value = entry['value_inr'];
        final createdAt = DateTime.tryParse('${entry['created_at']}');

        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: (earned ? Colors.green : AppTheme.accentColor).withValues(alpha: 0.12),
            child: Icon(
              earned ? Icons.add : Icons.remove,
              size: 18,
              color: earned ? Colors.green.shade700 : AppTheme.accentColor,
            ),
          ),
          title: Text(
            entry['note'] ?? (earned ? 'Coins earned' : 'Coins redeemed'),
            style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              // Which rung produced these coins — the milestone history.
              if (entry['tier_label'] != null) 'Band ${entry['tier_label']}',
              if (createdAt != null) DateFormat('d MMM yyyy, h:mm a').format(createdAt.toLocal()),
            ].join(' · '),
            style: GoogleFonts.outfit(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${earned ? '+' : ''}$coins',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: earned ? Colors.green.shade700 : AppTheme.accentColor)),
              if (value != null)
                Text('₹$value',
                    style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900)),
          Text(label,
              style: GoogleFonts.outfit(fontSize: 11.5, color: Colors.grey.shade600, height: 1.3)),
        ],
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(16),
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
