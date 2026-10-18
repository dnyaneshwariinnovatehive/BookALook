import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:partner_app/services/api_config.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:partner_app/models/subscription_plan.dart';
import 'package:partner_app/widgets/subscription/subscription_plan_card.dart';
import 'package:partner_app/theme/app_colors.dart';
import 'package:partner_app/widgets/subscription/subscription_bill_summary_sheet.dart';
import 'package:partner_app/widgets/subscription/payment_proof_viewer.dart';

class UpgradePlanScreen extends StatefulWidget {
  final String salonId;

  /// A salon buying its very first plan is not "upgrading" anything, so the
  /// screen introduces itself differently when it is reached from the welcome
  /// lock screen.
  final bool isFirstPlan;

  const UpgradePlanScreen({
    super.key,
    required this.salonId,
    this.isFirstPlan = false,
  });

  @override
  State<UpgradePlanScreen> createState() => _UpgradePlanScreenState();
}

class _UpgradePlanScreenState extends State<UpgradePlanScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  List<dynamic> _plans = [];
  List<SubscriptionPlan> _parsedPlans = [];
  String? _currentPlanId;
  double _walletBalance = 0;

  /// What one coin is worth in rupees, as the server says. Read rather than
  /// assumed, so the discount shown here matches what the server would work
  /// out if SuperAdmin ever changes the rate.
  double _coinValue = 1;
  bool _applyCoins = true;
  String? _selectedPlanId;
  XFile? _screenshot;

  /// What the owner can type alongside the screenshot to help SuperAdmin match
  /// it to a bank line. Both optional and both sent only when there is something
  /// to send — plenty of owners pay by card and have no UTR to quote, and the
  /// screenshot alone is accepted as proof.
  final TextEditingController _transactionController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  final String _baseUrl = ApiConfig.baseUrl;

  @override
  void dispose() {
    _transactionController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

      final plansRes = await http.get(
        Uri.parse('$_baseUrl/partner/subscription/plans'),
        headers: headers,
      );
      final walletRes = await http.get(
        Uri.parse('$_baseUrl/partner/salons/${widget.salonId}/wallet'),
        headers: headers,
      );
      final subRes = await http.get(
        Uri.parse('$_baseUrl/partner/salons/${widget.salonId}/subscription'),
        headers: headers,
      );

      final plansData = jsonDecode(plansRes.body);
      final walletData = jsonDecode(walletRes.body);
      final subData = subRes.statusCode == 200 ? jsonDecode(subRes.body) : null;

      setState(() {
        if (plansData != null && plansData['success'] == true) {
          _plans = plansData['plans'] as List<dynamic>? ?? [];
          _parsedPlans = _plans
              .map(
                (p) => SubscriptionPlan.fromJson(Map<String, dynamic>.from(p)),
              )
              .toList();
          if (_plans.isNotEmpty && _selectedPlanId == null) {
            _selectedPlanId = _plans.first['id'].toString();
          }
        }
        if (walletData != null && walletData['success'] == true) {
          final balance = walletData['balance'] ?? 0;
          _walletBalance = balance is num
              ? balance.toDouble()
              : (double.tryParse(balance.toString()) ?? 0.0);
          final rate = walletData['coin_value_inr'];
          if (rate is num && rate > 0) _coinValue = rate.toDouble();
        }
        if (subData != null &&
            subData['success'] == true &&
            subData['has_subscription'] == true) {
          _currentPlanId =
              subData['subscription']?['plan_id']?.toString() ??
              subData['subscription']?['plan']?['id']?.toString();
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
        _screenshot = pickedFile;
      });
    }
  }

  /// Coins the owner has chosen to put towards the selected plan.
  int get _coinsApplied =>
      _applyCoins ? _usableCoinsFor(_selectedPlanPrice) : 0;

  double get _selectedPlanPrice {
    final plan = _plans.firstWhere(
      (p) => p['id'].toString() == _selectedPlanId,
      orElse: () => null,
    );
    if (plan == null) return 0;
    final price = plan['price'];
    return price is num
        ? price.toDouble()
        : (double.tryParse(price.toString()) ?? 0);
  }

  /// Mirrors the server's own quote: whole coins only, and never more than the
  /// bill is worth, because coins spent beyond the price would just be burnt.
  int _usableCoinsFor(double price) {
    if (_coinValue <= 0 || price <= 0) return 0;
    final affordable = (price / _coinValue).floor();
    return _walletBalance < affordable ? _walletBalance.floor() : affordable;
  }

  /// True when the coins cover the whole plan, so there is nothing to transfer
  /// and therefore no receipt to upload.
  bool get _fullyPaidByCoins =>
      _selectedPlanPrice > 0 &&
      _coinsApplied * _coinValue >= _selectedPlanPrice;

  /// Name of the plan currently picked, for the confirmation to name.
  String get _selectedPlanName {
    final plan = _plans.firstWhere(
      (p) => p['id'].toString() == _selectedPlanId,
      orElse: () => null,
    );
    return plan?['name']?.toString() ?? 'this plan';
  }

  /// A plan purchase spends wallet coins and, usually, real money, and the
  /// coins are gone the moment the request goes out. The button shows the
  /// summary already; this is the point of no return.
  Future<void> _confirmUpgrade() async {
    if (_selectedPlanId == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heading = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;
    final body = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final textLight = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;
    final accent = AppTheme.accentColor;
    final softBg = isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

    final coins = _coinsApplied;
    final price = _selectedPlanPrice;
    final discount = coins * _coinValue;
    final remaining = (price - discount).clamp(0, price);
    final coveredByCoins = _fullyPaidByCoins;

    Widget row(String label, String value, Color valueColor) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: body)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ),
      ],
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          coveredByCoins
              ? 'Activate $_selectedPlanName?'
              : 'Confirm your $_selectedPlanName payment?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 19,
            color: heading,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Plan', _selectedPlanName, heading),
            const SizedBox(height: 6),
            row('Plan price', '₹${price.toStringAsFixed(0)}', heading),
            if (coins > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Coins applied',
                    style: TextStyle(fontSize: 14, color: body),
                  ),
                  Flexible(
                    child: Text(
                      '$coins coins (−₹${discount.toStringAsFixed(0)})',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            if (coins > 0) const SizedBox(height: 6),
            row(
              coveredByCoins ? 'Still to pay' : 'Paying now',
              coveredByCoins
                  ? '₹0 — fully covered'
                  : '₹${remaining.toStringAsFixed(0)}',
              coveredByCoins ? body : heading,
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: softBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                coveredByCoins
                    ? 'Your $coins coins are spent the moment this is activated, and coins cannot be refunded.'
                    : 'Your $coins coins are spent as soon as this request is sent, and coins cannot be refunded. BookALook verifies the proof before the plan goes live.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: body),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Check the plan name and amount before continuing.',
              style: TextStyle(fontSize: 12, color: textLight),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Go back', style: TextStyle(color: body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              coveredByCoins ? 'Activate plan' : 'Submit payment proof',
              style: TextStyle(color: accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _processUpgrade();
  }

  Future<void> _processUpgrade() async {
    if (_selectedPlanId == null) return;
    if (_isProcessing) return;

    // A plan the coins cover outright is activated on the spot, so the only
    // time a screenshot is needed is when real money changed hands.
    if (!_fullyPaidByCoins && _screenshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text('Please upload a screenshot of your transaction'),
        ),
      );
      return;
    }
    setState(() => _isProcessing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '$_baseUrl/partner/salons/${widget.salonId}/subscription/payment-request',
        ),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      // This screen only ever buys a plan. Moving to the Commission Model is a
      // request SuperAdmin approves, not a purchase — it lives on the billing
      // screen, and sending a billing type from here used to overwrite a
      // commission salon's arrangement.
      request.fields['plan_id'] = _selectedPlanId!;
      // The server clamps this to what the wallet actually holds, so it is a
      // request rather than an instruction.
      request.fields['coins_to_redeem'] = _coinsApplied.toString();

      // Trimmed here as well as on the server, so an untouched field is not sent
      // as an empty string — the two are the same thing everywhere else, and
      // they are both optional.
      final transactionId = _transactionController.text.trim();
      if (transactionId.isNotEmpty)
        request.fields['transaction_id'] = transactionId;

      final note = _noteController.text.trim();
      if (note.isNotEmpty) request.fields['note'] = note;

      if (_screenshot != null) {
        final bytes = await _screenshot!.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'screenshot',
            bytes,
            filename: _screenshot!.name,
          ),
        );
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final bool paidWithCoins =
            data['paid_with_coins'] == true || _fullyPaidByCoins;
        if (paidWithCoins) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(milliseconds: 2500),
                content: Text(
                  data['message'] ?? 'Plan activated successfully with coins!',
                ),
              ),
            );
            Navigator.pop(context, true);
          }
          return;
        }

        final Map<String, dynamic> requestMap =
            (data['payment_request'] is Map<String, dynamic>)
            ? Map<String, dynamic>.from(data['payment_request'])
            : (data['data'] is Map<String, dynamic>
                  ? Map<String, dynamic>.from(data['data'])
                  : <String, dynamic>{
                      'plan_name': _selectedPlanName,
                      'validity_days': 30,
                      'amount_payable_inr':
                          _selectedPlanPrice - (_coinsApplied * _coinValue),
                      'coins_to_redeem': _coinsApplied,
                      'coin_discount_inr': _coinsApplied * _coinValue,
                      'base_price': _selectedPlanPrice,
                      'transaction_id': transactionId,
                      'note': note,
                      'status': 'pending',
                      'created_at': DateTime.now().toIso8601String(),
                    });

        if (mounted) {
          await _showSubmissionConfirmation(requestMap);
          if (mounted) {
            Navigator.pop(context, true);
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(milliseconds: 2500),
              content: Text(data['message'] ?? 'Failed'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error upgrading: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _showSubmissionConfirmation(
    Map<String, dynamic> requestMap,
  ) async {
    final colors = context.colors;
    final planName = requestMap['plan_name']?.toString() ?? _selectedPlanName;
    final payable =
        double.tryParse((requestMap['amount_payable_inr'] ?? 0).toString()) ??
        0.0;
    final screenshotUrl = requestMap['screenshot_url']?.toString();
    final transactionId = requestMap['transaction_id']?.toString();
    final note = requestMap['note']?.toString();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 34,
                color: AppTheme.accentColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Payment Submitted for Verification',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your payment submission of ₹${payable.toStringAsFixed(2)} for the $planName Plan has been received and is awaiting SuperAdmin review.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                height: 1.45,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Status',
                        style: GoogleFonts.outfit(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (Theme.of(context).brightness == Brightness.dark
                                      ? AppTheme.darkWarning
                                      : AppTheme.lightWarning)
                                  .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'UNDER REVIEW',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? AppTheme.darkWarning
                                : AppTheme.lightWarning,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (transactionId != null && transactionId.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Reference',
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            color: colors.textSecondary,
                          ),
                        ),
                        Text(
                          transactionId,
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      SubscriptionBillSummarySheet.show(dialogCtx, requestMap);
                    },
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text('Bill Summary'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                if (screenshotUrl != null && screenshotUrl.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        PaymentProofViewer.show(
                          dialogCtx,
                          imageUrl: screenshotUrl,
                          title: 'Payment Proof',
                          transactionId: transactionId,
                          note: note,
                        );
                      },
                      icon: const Icon(Icons.image_outlined, size: 16),
                      label: const Text('Proof'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Done / Back to Billing',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final price = _selectedPlanPrice;
    final coinsUsable = _usableCoinsFor(price);
    final discountApplied = _applyCoins ? coinsUsable * _coinValue : 0;
    final finalPrice = price - discountApplied;
    final coversEverything = _fullyPaidByCoins;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFirstPlan ? 'Choose Your Plan' : 'Upgrade Plan'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select a Plan',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a plan tier that fits your salon\'s client base and marketing goals.',
              style: GoogleFonts.outfit(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_parsedPlans.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No active subscription plans available.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _parsedPlans.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final plan = _parsedPlans[index];
                  return SubscriptionPlanCard(
                    plan: plan,
                    isSelected: plan.id == _selectedPlanId,
                    isCurrentPlan: plan.id == _currentPlanId,
                    onSelect: () {
                      setState(() => _selectedPlanId = plan.id);
                    },
                  );
                },
              ),
            const Divider(height: 48),

            Text(
              'Payment Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
                title: Text(
                  'Apply wallet coins (${_walletBalance.toStringAsFixed(0)} available)',
                ),
                subtitle: Text(
                  '1 coin = ₹${_coinValue.toStringAsFixed(_coinValue % 1 == 0 ? 0 : 2)}'
                  ' · ${coinsUsable.toString()} usable here',
                ),
                value: _applyCoins,
                onChanged: (val) {
                  setState(() => _applyCoins = val ?? false);
                },
              ),

            if (_applyCoins && discountApplied > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Discount:',
                    style: TextStyle(
                      color: (Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkSuccess
                          : AppTheme.lightSuccess),
                    ),
                  ),
                  Text(
                    '- ₹$discountApplied',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: (Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkSuccess
                          : AppTheme.lightSuccess),
                    ),
                  ),
                ],
              ),

            Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total to Pay:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '₹$finalPrice',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: (Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.darkInfo
                        : AppTheme.lightInfo),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Nothing left to transfer means nothing to photograph. Showing a
            // payment QR for ₹0 would just be confusing.
            if (coversEverything)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.lightSuccessBg,
                  border: Border.all(
                    color: AppTheme.lightSuccess.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 26,
                      color: AppTheme.lightSuccess,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your coins cover this plan',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.lightSuccess,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Nothing to pay and nothing to upload. '
                            '${coinsUsable.toString()} coins will be spent and the plan '
                            'starts straight away.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Scan QR to Pay',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Icon(
                      Icons.qr_code_2,
                      size: 120,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pay ₹${finalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'After payment, please upload a screenshot for verification.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _pickScreenshot,
                      icon: Icon(Icons.upload_file),
                      label: Text(
                        _screenshot != null
                            ? 'Screenshot Selected'
                            : 'Upload Screenshot',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      'Optional — helps us match your transfer faster',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _transactionController,
                      textInputAction: TextInputAction.next,
                      maxLength: 150,
                      decoration: const InputDecoration(
                        labelText: 'Transaction ID / UTR',
                        hintText: 'e.g. 421873654321',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.tag),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Note for BookALook',
                        hintText: 'e.g. Paid from my business account',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _isProcessing ? null : _confirmUpgrade,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator()
                  : Text(
                      coversEverything
                          ? 'Activate with coins'
                          : 'Submit Payment Proof',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
