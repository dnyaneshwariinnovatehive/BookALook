import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/services/api_config.dart';

class SubscriptionBillingScreen extends StatefulWidget {
  const SubscriptionBillingScreen({super.key});

  @override
  State<SubscriptionBillingScreen> createState() => _SubscriptionBillingScreenState();
}

class _SubscriptionBillingScreenState extends State<SubscriptionBillingScreen> {
  bool _isLoading = true;
  bool _hasSubscription = false;
  Map<String, dynamic>? _subscription;
  int _daysRemaining = 0;
  int _warningThresholdDays = 3;
  Map<String, dynamic>? _pendingRequest;
  List<dynamic> _history = [];
  final String _baseUrl = ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _fetchSubscription();
  }

  Future<void> _fetchSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse('$_baseUrl/partner/subscription'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _hasSubscription = data['has_subscription'];
          if (_hasSubscription) {
            _subscription = data['subscription'];
            _daysRemaining = data['days_remaining'];
            _warningThresholdDays = data['warning_threshold_days'] ?? 3;
          } else {
            _subscription = null;
          }
          _pendingRequest = data['pending_request'];
          _history = data['history'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching subscription: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _renewSubscription() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse('$_baseUrl/partner/subscription/renew'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'])),
        );
        _fetchSubscription();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Renewal failed')),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error renewing subscription: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Subscription & Billing'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hasSubscription && _daysRemaining <= _warningThresholdDays && _daysRemaining >= 0)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  border: Border.all(color: colorScheme.error),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: colorScheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your subscription expires in $_daysRemaining days! Renew now to avoid service interruption.',
                        style: TextStyle(color: colorScheme.onErrorContainer, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),

            if (_hasSubscription && _daysRemaining < 0)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Theme.of(context).dividerColor : Theme.of(context).dividerColor,
                  border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your subscription has expired. Online booking is currently disabled for your salon.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),

            if (_hasSubscription && _subscription != null) ...[
              Text(
                'Current Plan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                color: theme.cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _subscription!['plan']['name'] + ' Plan',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                          Chip(
                            label: Text(
                              _subscription!['status'].toString().toUpperCase(),
                              style: TextStyle(color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: _subscription!['status'] == 'active' ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess) : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          )
                        ],
                      ),
                      Divider(height: 32),
                      _buildDetailRow('Feature Level', _subscription!['feature_level'].toString().toUpperCase(), colorScheme),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        'Billing Type', 
                        _subscription!['billing_type'] == 'commission' 
                            ? 'Commission (${_subscription!['commission_percentage']}%)' 
                            : 'Flat Fee',
                        colorScheme
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow('Start Date', _subscription!['start_date'], colorScheme),
                      const SizedBox(height: 12),
                      _buildDetailRow('Expiry Date', _subscription!['end_date'], colorScheme),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _renewSubscription,
                icon: const Icon(Icons.autorenew),
                label: const Text('Renew Subscription (Mock)'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final submitted = await Navigator.pushNamed(context, '/upgrade_plan');
                  if (submitted == true && mounted) {
                    _fetchSubscription();
                  }
                },
                icon: const Icon(Icons.workspace_premium),
                label: const Text('Upgrade Plan & Redeem Coins'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ] else ...[
              Icon(Icons.receipt_long, size: 80, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 24),
              if (_pendingRequest != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.hourglass_top, color: colorScheme.onSecondaryContainer, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'Payment Under Verification',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSecondaryContainer),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your payment screenshot is currently being reviewed by the SuperAdmin. Your subscription will be activated soon.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.onSecondaryContainer),
                      )
                    ]
                  )
                )
              ] else ...[
                Text(
                  'No Active Subscription',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'You currently do not have an active subscription assigned to your salon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () async {
                    final submitted = await Navigator.pushNamed(context, '/upgrade_plan');
                    if (submitted == true && mounted) {
                      _fetchSubscription();
                    }
                  },
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: const Text('Purchase Subscription'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ]
            ],
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),
              const Text(
                'Subscription History',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ..._history.map((item) => _buildHistoryCard(item, colorScheme, theme)).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildHistoryCard(dynamic item, ColorScheme colorScheme, ThemeData theme) {
    final String status = item['status'] ?? 'unknown';
    final String planName = item['plan'] != null ? item['plan']['name'] : 'Unknown';
    final String startDate = item['start_date'] ?? 'N/A';
    final String endDate = item['end_date'] ?? 'N/A';

    Color statusColor;
    if (status == 'active') {
      statusColor = Colors.green;
    } else if (status == 'expired' || status == 'cancelled') {
      statusColor = Colors.redAccent;
    } else {
      statusColor = Colors.orange;
    }

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$planName Plan',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '$startDate to $endDate',
                  style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
