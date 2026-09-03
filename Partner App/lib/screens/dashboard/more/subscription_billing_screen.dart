import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
  final String _baseUrl = 'http://localhost:8000/api';

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
          }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription & Billing'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hasSubscription && _daysRemaining <= 3 && _daysRemaining >= 0)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your subscription expires in $_daysRemaining days! Renew now to avoid service interruption.',
                        style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w500),
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
                  color: Colors.grey.shade200,
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.black54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your subscription has expired. Online booking is currently disabled for your salon.',
                        style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),

            if (_hasSubscription && _subscription != null) ...[
              const Text(
                'Current Plan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
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
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                          Chip(
                            label: Text(
                              _subscription!['status'].toString().toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: _subscription!['status'] == 'active' ? Colors.green : Colors.grey,
                          )
                        ],
                      ),
                      const Divider(height: 32),
                      _buildDetailRow('Feature Level', _subscription!['feature_level'].toString().toUpperCase()),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        'Billing Type', 
                        _subscription!['billing_type'] == 'commission' 
                            ? 'Commission (${_subscription!['commission_percentage']}%)' 
                            : 'Flat Fee'
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow('Start Date', _subscription!['start_date']),
                      const SizedBox(height: 12),
                      _buildDetailRow('Expiry Date', _subscription!['end_date']),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _renewSubscription,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                child: const Text('Renew / Extend Subscription (Mock)'),
              ),
            ] else ...[
              const Icon(Icons.receipt_long, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              const Text(
                'No Active Subscription',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'You currently do not have an active subscription assigned to your salon.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 16)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}
