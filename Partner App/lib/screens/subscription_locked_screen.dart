import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/salon_access_api.dart';
import '../theme/app_theme.dart';
import 'dashboard/more/upgrade_plan_screen.dart';
import 'phone_screen.dart';
import '../services/push_notification_service.dart';
import '../widgets/subscription/subscription_bill_summary_sheet.dart';
import '../widgets/subscription/payment_proof_viewer.dart';

/// Shown in place of the whole app when the salon has no usable plan.
///
/// The two roles need different things from this screen. The owner needs the
/// shortest possible path to paying. A staff member cannot pay and should not
/// be nagged as if they could — they need to know why nothing works and be able
/// to ring the owner in one tap.
///
/// It also has to tell apart a lapsed plan from a salon that has just been
/// approved and never had one. Greeting a brand new owner with "your plan has
/// ended" reads as a failure on their first ever sign-in, when in fact the only
/// thing left to do is pick a plan.
class SubscriptionLockedScreen extends StatelessWidget {
  final SalonAccess access;

  /// Re-checks after a renewal so the app can let them back in.
  final Future<void> Function() onRecheck;

  /// For an owner with other salons: leave this locked one for another
  /// branch without logging out. Null hides the button.
  final VoidCallback? onSwitchSalon;

  const SubscriptionLockedScreen({
    super.key,
    required this.access,
    required this.onRecheck,
    this.onSwitchSalon,
  });

  Future<void> _callAdmin(BuildContext context) async {
    final phone = access.adminPhone;

    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text('No phone number on file for the salon owner.'),
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);

    if (!await launchUrl(uri)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text('Could not start a call. The number is $phone.'),
        ),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    await PushNotificationService().unregisterDevice();
    final prefs = await SharedPreferences.getInstance();
    final welcomeKeys = prefs.getKeys().where((k) => k.startsWith('welcome_shown_')).toList();
    final welcomeBackup = {for (final k in welcomeKeys) k: prefs.getBool(k)};
    await prefs.clear();
    for (final entry in welcomeBackup.entries) {
      if (entry.value != null) {
        await prefs.setBool(entry.key, entry.value!);
      }
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneScreen()),
      (route) => false,
    );
  }

  String get _expiredLabel {
    final parsed = DateTime.tryParse(access.expiredOn ?? '');
    return parsed == null ? '' : DateFormat('d MMMM yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isWelcome
                        ? Icons.celebration_outlined
                        : Icons.lock_outline,
                    size: 44,
                    color: _accent,
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),

                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    height: 1.5,
                    color: Colors.grey.shade700,
                  ),
                ),

                if (access.isPendingApproval &&
                    access.pendingRequest != null) ...[
                  const SizedBox(height: 20),
                  _buildPendingCard(context),
                ],

                if (access.canRenew &&
                    access.hasCoins &&
                    !access.isPendingApproval) ...[
                  const SizedBox(height: 20),
                  _buildCoinsCard(),
                ],

                if (!access.isPendingApproval) ...[
                  const SizedBox(height: 24),
                  _buildImpactCard(),
                ],
                const SizedBox(height: 28),

                if (access.canRenew)
                  ..._ownerActions(context)
                else
                  ..._staffActions(context),

                if (onSwitchSalon != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const ValueKey('locked_switch_salon'),
                    onPressed: onSwitchSalon,
                    icon: const Icon(Icons.storefront, size: 18),
                    label: Text('Switch to another salon', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => _logout(context),
                  child: Text(
                    'Log out',
                    style: GoogleFonts.outfit(color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The salon has just been approved and is picking its very first plan, so
  /// the screen greets rather than warns.
  bool get _isWelcome =>
      access.hasNeverSubscribed &&
      !access.isPendingApproval &&
      !access.hasRejectedPayment;

  Color get _accent {
    if (access.isPendingApproval) return AppTheme.lightWarning;
    if (access.hasRejectedPayment) return Colors.red.shade600;
    return _isWelcome ? AppTheme.accentColor : AppTheme.lightWarning;
  }

  String get _title {
    if (access.isPendingApproval) return 'Payment Received — Under Review';
    if (access.hasRejectedPayment) return 'Payment Not Accepted';
    if (!access.canRenew) return 'This salon is offline';

    return _isWelcome ? 'Choose your plan' : 'Your plan has ended';
  }

  String get _message => access.canRenew ? _ownerMessage() : _staffMessage();

  String _ownerMessage() {
    if (access.isPendingApproval) {
      final planName =
          access.pendingRequest?['plan_name']?.toString() ?? 'your plan';
      return 'We received your payment submission for $planName. SuperAdmin is reviewing your transfer proof. Your subscription will activate as soon as it is approved.';
    }
    if (access.hasRejectedPayment) {
      final planName =
          access.latestRejectedRequest?['plan_name']?.toString() ?? 'your plan';
      return 'Your previous payment submission for $planName was not accepted. Please review and choose a plan to submit a new transfer.';
    }
    if (_isWelcome) {
      return '${access.salonName} is approved and ready to go. Pick a plan to '
          'put it in front of customers, open bookings and unlock the app for '
          'your team.';
    }

    final when = _expiredLabel.isEmpty ? '' : ' on $_expiredLabel';

    return 'Your subscription for ${access.salonName} ended$when. '
        'Renew it to put the salon back in front of customers and let your team '
        'use the app again.';
  }

  String _staffMessage() {
    if (access.isPendingApproval) {
      return 'A subscription payment for ${access.salonName} is currently under SuperAdmin review. The app will unlock as soon as the review is complete.';
    }
    if (access.hasRejectedPayment) {
      final owner = access.adminName ?? 'the salon owner';
      return 'The subscription payment for ${access.salonName} was not accepted. Only $owner can resubmit a plan payment.';
    }
    final owner = access.adminName ?? 'the salon owner';

    if (_isWelcome) {
      return '${access.salonName} has not started a plan yet, so the app is '
          'locked for everyone here. Only $owner can choose one.';
    }

    return '${access.salonName}\'s subscription has ended, so the app is locked '
        'for everyone here. Only $owner can renew it.';
  }

  /// The coins the salon already has against the price it is about to be shown.
  ///
  /// This is the whole point of the welcome bonus: an owner who reads "₹1999"
  /// cold is being asked to start paying, while an owner who reads "you already
  /// have ₹2300 towards it" is being asked to finish something.
  Widget _buildCoinsCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.lightSuccessBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.lightSuccess.withValues(alpha: 0.35)),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.lightSuccess.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.savings_outlined,
            size: 21,
            color: AppTheme.lightSuccess,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${access.walletCoins} coins ready to spend',
                style: GoogleFonts.outfit(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.lightSuccess,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _isWelcome
                    ? 'Worth ₹${access.walletValueInr.toStringAsFixed(0)} off your first plan.'
                    : 'Worth ₹${access.walletValueInr.toStringAsFixed(0)} off your renewal.',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppTheme.lightTextBody,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildImpactCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: _isWelcome
          ? [
              _impactRow(
                Icons.storefront_outlined,
                'The salon goes live for customers to find and book',
              ),
              const SizedBox(height: 10),
              _impactRow(
                Icons.groups_outlined,
                'The whole team gets into the app',
              ),
              const SizedBox(height: 10),
              _impactRow(
                Icons.point_of_sale_outlined,
                'Check-ins, walk-ins and billing all open up',
              ),
            ]
          : [
              _impactRow(
                Icons.visibility_off_outlined,
                'Customers cannot find or book this salon',
              ),
              const SizedBox(height: 10),
              _impactRow(
                Icons.block,
                'Check-ins, walk-ins and billing are closed',
              ),
              const SizedBox(height: 10),
              _impactRow(
                Icons.history_toggle_off,
                'Nothing is lost — your data is waiting when you renew',
              ),
            ],
    ),
  );

  Widget _impactRow(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: Colors.grey.shade500),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade700),
        ),
      ),
    ],
  );

  Widget _buildPendingCard(BuildContext context) {
    final req = access.pendingRequest!;
    final planName = req['plan_name']?.toString() ?? 'Subscription Plan';
    final payable =
        double.tryParse(
          (req['amount_payable_inr'] ?? req['amount_submitted'] ?? 0)
              .toString(),
        ) ??
        0.0;
    final transactionId = req['transaction_id']?.toString();
    final screenshotUrl = req['screenshot_url']?.toString();
    final note = req['note']?.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.lightWarningBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.lightWarning.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  planName,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.lightWarning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'UNDER REVIEW',
                  style: GoogleFonts.outfit(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.lightWarning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Amount submitted',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              Text(
                '₹${payable.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
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
                  'Reference / UTR',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  transactionId,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    SubscriptionBillSummarySheet.show(context, req);
                  },
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('Bill Summary'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                        context,
                        imageUrl: screenshotUrl,
                        title: 'Payment Proof',
                        transactionId: transactionId,
                        note: note,
                      );
                    },
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text('Proof'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _ownerActions(BuildContext context) {
    if (access.isPendingApproval) {
      return [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onRecheck,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              'Check Review Status',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UpgradePlanScreen(
                    salonId: _salonIdFrom(context),
                    isFirstPlan: _isWelcome,
                  ),
                ),
              );
              await onRecheck();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Re-submit or Change Plan'),
          ),
        ),
      ];
    }

    return [
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            // A renewal is the only thing that can unlock the app, so come
            // straight back and re-check when they return.
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UpgradePlanScreen(
                  salonId: _salonIdFrom(context),
                  isFirstPlan: _isWelcome,
                ),
              ),
            );
            await onRecheck();
          },
          icon: Icon(
            _isWelcome ? Icons.workspace_premium_outlined : Icons.autorenew,
          ),
          label: Text(
            access.hasRejectedPayment
                ? 'Choose a plan & re-submit'
                : (_isWelcome ? 'Choose a plan' : 'Renew now'),
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onRecheck,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            _isWelcome
                ? 'I have paid — check again'
                : 'I have renewed — check again',
          ),
        ),
      ),
    ];
  }

  List<Widget> _staffActions(BuildContext context) => [
    SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _callAdmin(context),
        icon: const Icon(Icons.call),
        label: Text(
          access.adminName != null
              ? 'Call ${access.adminName}'
              : 'Call the owner',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    ),
    if (access.adminPhone != null) ...[
      const SizedBox(height: 8),
      Text(
        access.adminPhone!,
        style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade600),
      ),
    ],
    const SizedBox(height: 10),
    SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onRecheck,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text('Check again'),
      ),
    ),
  ];

  /// The screen is only ever built with a salon in scope; the id travels on the
  /// inherited widget below so both dashboards can reuse this screen.
  String _salonIdFrom(BuildContext context) =>
      LockedSalonScope.of(context)?.salonId ?? '';
}

/// Carries the salon id down to the lock screen without every caller having to
/// thread it through.
class LockedSalonScope extends InheritedWidget {
  final String salonId;

  const LockedSalonScope({
    super.key,
    required this.salonId,
    required super.child,
  });

  static LockedSalonScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LockedSalonScope>();

  @override
  bool updateShouldNotify(LockedSalonScope oldWidget) =>
      oldWidget.salonId != salonId;
}
