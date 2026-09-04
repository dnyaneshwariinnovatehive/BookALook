import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/services/api_config.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _isLoading = true;
  double _balance = 0;
  List<dynamic> _transactions = [];
  final String _baseUrl = ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _fetchWalletData();
  }

  Future<void> _fetchWalletData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse('$_baseUrl/partner/wallet'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _balance = (data['balance'] ?? 0).toDouble();
          _transactions = data['transactions'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching wallet: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _redeemCommission() async {
    // In a real app, you would open a dialog to select the payout and amount.
    // For now, we mock the payout ID and amount.
    const String mockPayoutId = "00000000-0000-0000-0000-000000000000";
    final int coinsToRedeem = _balance.toInt(); // Mock: redeem everything
    
    if (coinsToRedeem <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No coins to redeem.')),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse('$_baseUrl/partner/wallet/redeem-commission'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'payout_id': mockPayoutId,
          'coins_to_redeem': coinsToRedeem
        }),
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Redeemed successfully')),
        );
        _fetchWalletData(); // Refresh data
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Failed to redeem')),
        );
      }
    } catch (e) {
      debugPrint('Error redeeming: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('My Wallet'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            width: double.infinity,
            color: colorScheme.primaryContainer,
            child: Column(
              children: [
                Icon(Icons.account_balance_wallet, size: 48, color: colorScheme.onPrimaryContainer),
                const SizedBox(height: 16),
                Text(
                  'Current Coin Balance',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  _balance.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/upgrade_plan');
                  },
                  child: Text('Redeem on Subscription Upgrade'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _redeemCommission,
                  child: Text('Redeem against Commission'),
                )
              ],
            ),
          ),
          Expanded(
            child: _transactions.isEmpty
                ? const Center(child: Text('No coin history yet.'))
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      final isEarned = tx['type'] == 'earned';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isEarned ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess).withValues(alpha: 0.1) : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger).withValues(alpha: 0.1),
                          child: Icon(
                            isEarned ? Icons.add : Icons.remove,
                            color: isEarned ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess) : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger),
                          ),
                        ),
                        title: Text(tx['description'] ?? 'Transaction'),
                        subtitle: Text(tx['created_at']?.toString().split('T')[0] ?? ''),
                        trailing: Text(
                          '${isEarned ? '+' : '-'}${tx['amount']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isEarned ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess) : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
