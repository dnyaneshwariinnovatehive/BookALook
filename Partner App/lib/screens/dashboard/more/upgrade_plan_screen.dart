import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

class UpgradePlanScreen extends StatefulWidget {
  const UpgradePlanScreen({super.key});

  @override
  State<UpgradePlanScreen> createState() => _UpgradePlanScreenState();
}

class _UpgradePlanScreenState extends State<UpgradePlanScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  List<dynamic> _plans = [];
  double _walletBalance = 0;
  bool _applyCoins = true;
  String? _selectedPlanId;
  File? _screenshot;
  final String _baseUrl = 'http://localhost:8000/api';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      // Note: Ideal implementation would fetch everything in one API call for this screen, 
      // but we will fetch plans and wallet balance for the demo.
      final plansRes = await http.get(Uri.parse('$_baseUrl/superadmin/subscriptions/plans'), headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      final walletRes = await http.get(Uri.parse('$_baseUrl/partner/wallet'), headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      final plansData = jsonDecode(plansRes.body);
      final walletData = jsonDecode(walletRes.body);

      setState(() {
        if (plansData['success']) {
          _plans = plansData['plans'] ?? [];
          if (_plans.isNotEmpty) _selectedPlanId = _plans.first['id'].toString();
        }
        if (walletData['success']) {
          _walletBalance = (walletData['balance'] ?? 0).toDouble();
        }
      });
    } catch (e) {
      debugPrint('Error fetching upgrade data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _screenshot = File(pickedFile.path);
      });
    }
  }

  Future<void> _processUpgrade() async {
    if (_selectedPlanId == null) return;
    if (_screenshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload a screenshot of your transaction')));
      return;
    }
    setState(() => _isProcessing = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/partner/subscription/payment-request'));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
      
      request.fields['plan_id'] = _selectedPlanId!;
      request.fields['billing_type'] = 'flat';

      request.files.add(await http.MultipartFile.fromPath('screenshot', _screenshot!.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'])));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Failed')));
      }
    } catch (e) {
      debugPrint('Error upgrading: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedPlan = _plans.firstWhere((p) => p['id'].toString() == _selectedPlanId, orElse: () => null);
    final price = selectedPlan != null ? double.parse(selectedPlan['price'].toString()) : 0;
    
    // Simplification for UI calculation: assuming 1 coin = 1 INR discount for demo, 
    // although backend handles exact calculation based on WalletScheme.
    final maxDiscount = _walletBalance; 
    final discountApplied = _applyCoins ? (price > maxDiscount ? maxDiscount : price) : 0;
    final finalPrice = price - discountApplied;

    return Scaffold(
      appBar: AppBar(title: Text('Upgrade Plan')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Select a Master Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._plans.map((plan) {
              return RadioListTile<String>(
                title: Text('${plan['name']} - ₹${plan['price']}'),
                subtitle: Text('WhatsApp Limit: ${plan['whatsapp_campaign_limit']}'),
                value: plan['id'].toString(),
                groupValue: _selectedPlanId,
                onChanged: (val) {
                  setState(() => _selectedPlanId = val);
                },
              );
            }),
            Divider(height: 48),
            
            Text('Payment Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Plan Price:'),
                Text('₹$price', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_walletBalance > 0)
              CheckboxListTile(
                title: Text('Apply Wallet Coins ($_walletBalance available)'),
                subtitle: Text('Assume 1 coin = ₹1 discount'),
                value: _applyCoins,
                onChanged: (val) {
                  setState(() => _applyCoins = val ?? false);
                },
              ),
            
            if (_applyCoins && discountApplied > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Discount:', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess))),
                  Text('- ₹$discountApplied', style: TextStyle(fontWeight: FontWeight.bold, color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess))),
                ],
              ),
              
            Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total to Pay:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('₹$finalPrice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkInfo : AppTheme.lightInfo))),
              ],
            ),
            
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text('Scan QR to Pay', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Icon(Icons.qr_code_2, size: 120, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('After payment, please upload a screenshot for verification.', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _pickScreenshot,
                    icon: Icon(Icons.upload_file),
                    label: Text(_screenshot != null ? 'Screenshot Selected' : 'Upload Screenshot'),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _isProcessing ? null : _processUpgrade,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              child: _isProcessing 
                  ? const CircularProgressIndicator() 
                  : Text('Submit Payment Proof'),
            ),
          ],
        ),
      )
    );
  }
}
