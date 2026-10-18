import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:partner_app/services/api_config.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partner_app/models/subscription_plan.dart';
import 'package:partner_app/widgets/subscription/plan_feature_item.dart';
import 'package:partner_app/widgets/subscription/subscription_bill_summary_sheet.dart';
import 'package:partner_app/widgets/subscription/payment_proof_viewer.dart';
import 'upgrade_plan_screen.dart';

class SubscriptionBillingScreen extends StatefulWidget {
  final String salonId;
  const SubscriptionBillingScreen({super.key, required this.salonId});

  @override
  State<SubscriptionBillingScreen> createState() =>
      _SubscriptionBillingScreenState();
}

class _SubscriptionBillingScreenState extends State<SubscriptionBillingScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _hasSubscription = false;
  bool _isPlanFeaturesExpanded = false;
  Map<String, dynamic>? _subscription;
  int _daysRemaining = 0;
  Map<String, dynamic>? _pendingRequest;
  List<dynamic> _history = [];

  /// Every payment this salon has raised, decided or not. Kept apart from
  /// `_history` above, which is a different thing: that lists the plan periods
  /// the salon ended up with, this lists the transfers that paid for them. An
  /// owner who uploaded proof and cannot find it again has no way to tell
  /// BookALook it was theirs.
  List<dynamic> _paymentRequests = [];

  /// Which arrangement the salon trades under. Postpaid salons have nothing to
  /// renew, so the whole screen reads differently for them.
  String _billingModel = 'subscription';
  String _billingLabel = 'Subscription Plan';
  double? _commissionPercentage;
  bool _canRenew = true;
  String? _nextSettlementDate;
  bool _isRequestingCommission = false;

  bool get _onCommissionModel => _billingModel == 'commission';

  final String _baseUrl = ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchSubscription();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _fetchSubscription();
    }
  }

  Future<void> _fetchSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse('$_baseUrl/partner/salons/${widget.salonId}/subscription'),
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
          } else {
            _subscription = null;
          }
          _pendingRequest = data['pending_request'];
          _history = data['history'] ?? [];
          _paymentRequests = data['payment_requests'] ?? [];
          _billingModel = data['billing_model'] ?? 'subscription';
          _billingLabel = data['billing_label'] ?? 'Subscription Plan';
          _commissionPercentage = data['commission_percentage'] == null
              ? null
              : double.tryParse(data['commission_percentage'].toString());
          _canRenew = data['can_renew'] ?? true;
          _nextSettlementDate = data['next_settlement_date'];
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

  /// Renewing commits the salon to another billing period, so the plan and
  /// the run-out date it replaces are both named first. This sits next to
  /// `_requestCommissionModel`, which already gates itself the same way.
  Future<void> _confirmRenewal() async {
    final planName = _subscription?['plan']?['name']?.toString() ?? 'your plan';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heading = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;
    final body = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final accent = AppTheme.accentColor;
    final softBg = isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Renew $planName?',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Plan', style: TextStyle(fontSize: 14, color: body)),
                Text(
                  '$planName Plan',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: heading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Runs out in',
                  style: TextStyle(fontSize: 14, color: body),
                ),
                Text(
                  '$_daysRemaining days',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: heading,
                  ),
                ),
              ],
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
                'Renewing starts a fresh billing period from today and commits you to it. It cannot be cancelled from the app.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: body),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Not now', style: TextStyle(color: body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Renew',
              style: TextStyle(color: accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _renewSubscription();
  }

  Future<void> _renewSubscription() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse(
          '$_baseUrl/partner/salons/${widget.salonId}/subscription/renew',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 2500),
            content: Text(data['message']),
          ),
        );
        _fetchSubscription();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 2500),
            content: Text(data['message'] ?? 'Renewal failed'),
          ),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error renewing subscription: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Ask SuperAdmin to move this salon onto the Commission Model.
  ///
  /// Nothing is paid here, so there is no receipt to upload — and the salon
  /// does not name its own percentage. SuperAdmin agrees that when approving.
  Future<void> _requestCommissionModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch to the Commission Model?'),
        content: const Text(
          'You would stop paying up front and instead pay a percentage of '
          'everything you bill, settled on the 1st of each month for the month '
          'just finished.\n\n'
          'BookALook will confirm your percentage before switching you over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRequestingCommission = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse(
          '$_baseUrl/partner/salons/${widget.salonId}/subscription/commission-request',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text(data['message'] ?? 'Could not send the request.'),
        ),
      );

      if (data['success'] == true) _fetchSubscription();
    } catch (e) {
      debugPrint('Error requesting the commission model: $e');
    } finally {
      if (mounted) setState(() => _isRequestingCommission = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hasSubscription && !_onCommissionModel && _daysRemaining < 0)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Theme.of(context).dividerColor
                      : Theme.of(context).dividerColor,
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your subscription plan has expired. Online booking is currently disabled for your salon.',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            _buildPendingApprovalBanner(colorScheme, theme, isDark),

            if (_hasSubscription && _subscription != null) ...[
              Text(
                _onCommissionModel ? 'Your arrangement' : 'Current Plan',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          Chip(
                            label: Text(
                              _subscription!['status'].toString().toUpperCase(),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.surface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor:
                                _subscription!['status'] == 'active'
                                ? (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? AppTheme.darkSuccess
                                      : AppTheme.lightSuccess)
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ],
                      ),
                      Divider(height: 32),
                      _buildDetailRow(
                        'Feature Level',
                        _subscription!['plan']['has_priority_visibility'] ==
                                true
                            ? 'PREMIUM'
                            : 'STANDARD',
                        colorScheme,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        'Billing Model',
                        _billingLabel,
                        colorScheme,
                      ),
                      if (_onCommissionModel) ...[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          'Commission',
                          _commissionPercentage == null
                              ? '—'
                              : '${_commissionPercentage!.toStringAsFixed(_commissionPercentage! % 1 == 0 ? 0 : 2)}% of everything you bill',
                          colorScheme,
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          'Next settlement',
                          _nextSettlementDate == null
                              ? 'The 1st of next month'
                              : _formatDate(_nextSettlementDate),
                          colorScheme,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        'Start Date',
                        _formatDate(_subscription!['start_date']),
                        colorScheme,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        _onCommissionModel ? 'Access until' : 'Expiry Date',
                        _formatDate(_subscription!['end_date'], relative: true),
                        colorScheme,
                      ),
                      if (_subscription!['plan'] != null) ...[
                        const SizedBox(height: 16),
                        Divider(height: 1, color: theme.dividerColor),
                        const SizedBox(height: 16),
                        _buildCurrentPlanFeatures(
                          SubscriptionPlan.fromJson(
                            Map<String, dynamic>.from(_subscription!['plan']),
                          ),
                          colorScheme,
                          isDark,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Nothing was bought on the Commission Model, so there is nothing
              // to renew — access extends when the month is settled.
              if (_onCommissionModel)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'There is nothing to renew. Your access extends each time '
                          'BookALook settles your month\u2019s commission.',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _canRenew ? _confirmRenewal : null,
                  icon: const Icon(Icons.autorenew),
                  label: const Text('Renew Subscription (Mock)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              if (!_onCommissionModel && _pendingRequest == null) ...[
                OutlinedButton.icon(
                  onPressed: _isRequestingCommission
                      ? null
                      : _requestCommissionModel,
                  icon: const Icon(Icons.percent_rounded),
                  label: Text(
                    _isRequestingCommission
                        ? 'Sending…'
                        : 'Switch to the Commission Model',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pay nothing up front. Instead BookALook keeps an agreed percentage '
                  'of what you bill, settled monthly.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                onPressed: () async {
                  final submitted = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UpgradePlanScreen(salonId: widget.salonId),
                    ),
                  );
                  if (submitted == true && mounted) {
                    _fetchSubscription();
                  }
                },
                icon: const Icon(Icons.workspace_premium),
                label: const Text('Upgrade Plan & Redeem Coins'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ] else ...[
              if (_pendingRequest == null) ...[
                Icon(
                  Icons.receipt_long,
                  size: 80,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 24),
                const Text(
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
                    final submitted = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            UpgradePlanScreen(salonId: widget.salonId),
                      ),
                    );
                    if (submitted == true && mounted) {
                      _fetchSubscription();
                    }
                  },
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: const Text('Purchase Subscription'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    final submitted = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            UpgradePlanScreen(salonId: widget.salonId),
                      ),
                    );
                    if (submitted == true && mounted) {
                      _fetchSubscription();
                    }
                  },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Replace or Re-submit Payment Proof'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
            if (_paymentRequests.isNotEmpty) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),
              const Text(
                'Payment History',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Every plan payment you have sent us, and what became of it.',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ..._paymentRequests
                  .map(
                    (item) =>
                        _buildPaymentRequestCard(item, colorScheme, theme),
                  )
                  .toList(),
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
              ..._history
                  .map((item) => _buildHistoryCard(item, colorScheme, theme))
                  .toList(),
            ],
          ],
        ),
      ),
    );
  }

  /// Formats a raw date string from the API into a readable form.
  ///
  /// - When a time component is present it is shown as `HH:mm dd/MM/yy`.
  /// - When only a date is present it is shown as `dd/MM/yy`.
  /// - When [relative] is true and the date falls today or tomorrow, a human
  ///   friendly "Today" / "Tomorrow" label is used instead.
  String _formatDate(Object? raw, {bool relative = false}) {
    final String text = raw?.toString() ?? '';
    if (text.isEmpty) return '—';

    final DateTime? dt = DateTime.tryParse(text);
    if (dt == null) return text;

    final bool hasTime = dt.hour != 0 || dt.minute != 0 || dt.second != 0;

    if (relative) {
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      final DateTime target = DateTime(dt.year, dt.month, dt.day);
      final int diff = target.difference(today).inDays;

      if (diff == 1) {
        return hasTime
            ? 'Tomorrow at ${DateFormat('HH:mm').format(dt)}'
            : 'Tomorrow';
      }
      if (diff == 0) {
        return hasTime ? 'Today at ${DateFormat('HH:mm').format(dt)}' : 'Today';
      }
    }

    if (hasTime) {
      return DateFormat('HH:mm dd/MM/yy').format(dt);
    }
    return DateFormat('dd/MM/yy').format(dt);
  }

  Widget _buildPendingApprovalBanner(
    ColorScheme colorScheme,
    ThemeData theme,
    bool isDark,
  ) {
    if (_pendingRequest == null) return const SizedBox.shrink();

    final String planName =
        _pendingRequest!['plan_name']?.toString() ??
        _pendingRequest!['plan']?['name']?.toString() ??
        'Subscription Plan';
    final int validityDays =
        int.tryParse(
          (_pendingRequest!['validity_days'] ??
                  _pendingRequest!['plan']?['validity_days'] ??
                  30)
              .toString(),
        ) ??
        30;
    final double payable =
        double.tryParse(
          (_pendingRequest!['amount_payable_inr'] ??
                  _pendingRequest!['amount_submitted'] ??
                  0)
              .toString(),
        ) ??
        0.0;
    final int coins =
        int.tryParse((_pendingRequest!['coins_to_redeem'] ?? 0).toString()) ??
        0;
    final String? transactionId = _pendingRequest!['transaction_id']
        ?.toString();
    final String? screenshotUrl = _pendingRequest!['screenshot_url']
        ?.toString();
    final String? note = _pendingRequest!['note']?.toString();
    final String? raisedAt =
        _pendingRequest!['raised_at']?.toString() ??
        _pendingRequest!['created_at']?.toString();

    final Color warningColor = isDark
        ? AppTheme.darkWarning
        : AppTheme.lightWarning;
    final Color warningBg = warningColor.withValues(
      alpha: isDark ? 0.16 : 0.08,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: warningBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: warningColor.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: warningColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.pending_actions_rounded,
                  color: warningColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Payment Received — Under Review',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : Colors.grey.shade900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: warningColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: warningColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            'PENDING REVIEW',
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: warningColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _hasSubscription && _subscription != null
                          ? 'Your subscription payment submission has been received and is awaiting SuperAdmin verification. Your current plan remains active while under review.'
                          : 'Your subscription payment submission has been received and is awaiting SuperAdmin verification. Your subscription status will update once the review is complete.',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        height: 1.4,
                        color: isDark
                            ? Colors.grey.shade300
                            : Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: warningColor.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          _summaryRow('Plan', '$planName ($validityDays days)', colorScheme),
          const SizedBox(height: 6),
          _summaryRow(
            'Amount submitted',
            '₹${payable.toStringAsFixed(2)}${coins > 0 ? ' (+$coins coins applied)' : ''}',
            colorScheme,
          ),
          const SizedBox(height: 6),
          _summaryRow(
            'Reference / UTR',
            (transactionId != null && transactionId.isNotEmpty)
                ? transactionId
                : 'Not provided',
            colorScheme,
          ),
          const SizedBox(height: 6),
          _summaryRow('Submitted on', _formatDate(raisedAt), colorScheme),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  SubscriptionBillSummarySheet.show(
                    context,
                    Map<String, dynamic>.from(_pendingRequest!),
                  );
                },
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('View Bill Summary'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (screenshotUrl != null && screenshotUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    PaymentProofViewer.show(
                      context,
                      imageUrl: screenshotUrl,
                      title: 'Payment Proof',
                      transactionId: transactionId,
                      note: note,
                    );
                  },
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: const Text('View Payment Proof'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              IconButton(
                onPressed: _fetchSubscription,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Check review status',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildCurrentPlanFeatures(
    SubscriptionPlan plan,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final included = plan.includedFeatures;
    final isExpired = _daysRemaining < 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Features included in this plan',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            if (included.length > 2)
              InkWell(
                onTap: () {
                  setState(() {
                    _isPlanFeaturesExpanded = !_isPlanFeaturesExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isPlanFeaturesExpanded
                            ? 'Collapse'
                            : 'View all (${included.length})',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accentColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isPlanFeaturesExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: AppTheme.accentColor,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (included.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Standard salon booking, catalog, staff, and wallet features included.',
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          // When collapsed show top 2 features, when expanded show all features
          ...((_isPlanFeaturesExpanded ? included : included.take(2)).map(
            (f) => PlanFeatureItem(feature: f, isCompact: true),
          )),
        ],
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isExpired
                ? 'Features configured for this plan. Renewal is required to restore active access to campaigns, booking, and insights.'
                : 'Features configured for this plan. Active for your salon while this subscription is valid.',
            style: GoogleFonts.outfit(
              fontSize: 11.5,
              height: 1.35,
              color: isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody,
            ),
          ),
        ),
      ],
    );
  }

  /// One payment the owner sent us, whether it is still being looked at or has
  /// already been decided.
  ///
  /// Shows the transaction id and note back because those are the owner's own
  /// words about the transfer — if BookALook cannot find it, or the owner
  /// cannot remember what they wrote, the reference is the only thing either
  /// side can go on.
  Widget _buildPaymentRequestCard(
    dynamic item,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final String status = (item['status'] ?? 'unknown').toString();
    final String? planName = item['plan_name']?.toString();
    final String? transactionId = item['transaction_id']?.toString();
    final String? note = item['note']?.toString();
    final String? screenshotUrl = item['screenshot_url']?.toString();

    final double payable =
        double.tryParse((item['amount_payable_inr'] ?? 0).toString()) ?? 0;
    final int coins =
        int.tryParse((item['coins_to_redeem'] ?? 0).toString()) ?? 0;

    Color statusColor;
    String statusLabel;
    if (status == 'approved') {
      statusColor = Colors.green;
      statusLabel = 'APPROVED';
    } else if (status == 'rejected') {
      statusColor = Colors.redAccent;
      statusLabel = 'NOT ACCEPTED';
    } else {
      statusColor = Colors.orange;
      statusLabel = 'UNDER REVIEW';
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
                Expanded(
                  child: Text(
                    planName ??
                        item['billing_label']?.toString() ??
                        'Plan payment',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _paymentLine(
              'Sent on',
              _formatDate(item['raised_at']),
              colorScheme,
            ),
            _paymentLine(
              'Amount paid',
              '₹${payable.toStringAsFixed(2)}',
              colorScheme,
            ),
            if (coins > 0)
              _paymentLine(
                'Coins used',
                '$coins (₹ discount applied on approval)',
                colorScheme,
              ),
            if (transactionId != null && transactionId.isNotEmpty)
              _paymentLine('Transaction ID', transactionId, colorScheme),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Note',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(note, style: TextStyle(fontSize: 14, height: 1.35)),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    SubscriptionBillSummarySheet.show(
                      context,
                      Map<String, dynamic>.from(item),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('View Bill Summary'),
                ),
                if (screenshotUrl != null && screenshotUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      PaymentProofViewer.show(
                        context,
                        imageUrl: screenshotUrl,
                        title: 'Payment Proof',
                        transactionId: transactionId,
                        note: note,
                      );
                    },
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text('View Payment Proof'),
                  ),
              ],
            ),
            if (status == 'rejected')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Not accepted. This is usually because a newer payment replaced it.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _paymentLine(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// Open a receipt in the phone's browser or gallery.
  ///
  /// Only http(s) is allowed through. The URL comes from our own storage, but
  /// handing an arbitrary string to the platform's URL handler is not something
  /// to do on trust — `javascript:` and `file://` both open with the app's own
  /// permissions.
  Future<void> _openExternal(String rawUrl, String failureMessage) async {
    final uri = Uri.tryParse(rawUrl.trim());
    final allowed =
        uri != null && (uri.scheme == 'https' || uri.scheme == 'http');

    // `allowed` being true is what proves uri is non-null, so no bang needed.
    if (!allowed ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text(failureMessage),
        ),
      );
    }
  }

  Widget _buildHistoryCard(
    dynamic item,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final String status = item['status'] ?? 'unknown';
    final String planName = item['plan'] != null
        ? item['plan']['name']
        : 'Unknown';
    final String startDate = _formatDate(item['start_date']);
    final String endDate = _formatDate(item['end_date']);

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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  '$startDate to $endDate',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
