import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/salon_access_api.dart';
import '../theme/app_theme.dart';
import 'dashboard/more/upgrade_plan_screen.dart';
import 'phone_screen.dart';

/// Shown in place of the whole app when the salon's plan has lapsed.
///
/// The two roles need different things from this screen. The owner needs the
/// shortest possible path to paying. A staff member cannot pay and should not
/// be nagged as if they could — they need to know why nothing works and be able
/// to ring the owner in one tap.
class SubscriptionLockedScreen extends StatelessWidget {
  final SalonAccess access;

  /// Re-checks after a renewal so the app can let them back in.
  final Future<void> Function() onRecheck;

  const SubscriptionLockedScreen({
    super.key,
    required this.access,
    required this.onRecheck,
  });

  Future<void> _callAdmin(BuildContext context) async {
    final phone = access.adminPhone;

    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number on file for the salon owner.')),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);

    if (!await launchUrl(uri)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start a call. The number is $phone.')),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

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
                    color: AppTheme.lightWarning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline, size: 44, color: AppTheme.lightWarning),
                ),
                const SizedBox(height: 24),

                Text(
                  access.canRenew ? 'Your plan has ended' : 'This salon is offline',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                Text(
                  access.canRenew ? _ownerMessage() : _staffMessage(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                      fontSize: 14.5, height: 1.5, color: Colors.grey.shade700),
                ),

                const SizedBox(height: 24),
                _buildImpactCard(),
                const SizedBox(height: 28),

                if (access.canRenew) ..._ownerActions(context) else ..._staffActions(context),

                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => _logout(context),
                  child: Text('Log out',
                      style: GoogleFonts.outfit(color: Colors.grey.shade600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _ownerMessage() {
    final when = _expiredLabel.isEmpty ? '' : ' on $_expiredLabel';

    return 'Your subscription for ${access.salonName} ended$when. '
        'Renew it to put the salon back in front of customers and let your team '
        'use the app again.';
  }

  String _staffMessage() {
    final owner = access.adminName ?? 'the salon owner';

    return '${access.salonName}\'s subscription has ended, so the app is locked '
        'for everyone here. Only $owner can renew it.';
  }

  Widget _buildImpactCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _impactRow(Icons.visibility_off_outlined,
                'Customers cannot find or book this salon'),
            const SizedBox(height: 10),
            _impactRow(Icons.block, 'Check-ins, walk-ins and billing are closed'),
            const SizedBox(height: 10),
            _impactRow(Icons.history_toggle_off,
                'Nothing is lost — your data is waiting when you renew'),
          ],
        ),
      );

  Widget _impactRow(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade700)),
          ),
        ],
      );

  List<Widget> _ownerActions(BuildContext context) => [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              // A renewal is the only thing that can unlock the app, so come
              // straight back and re-check when they return.
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UpgradePlanScreen(salonId: _salonIdFrom(context)),
                ),
              );
              await onRecheck();
            },
            icon: const Icon(Icons.autorenew),
            label: Text('Renew now',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
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
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('I have renewed — check again'),
          ),
        ),
      ];

  List<Widget> _staffActions(BuildContext context) => [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _callAdmin(context),
            icon: const Icon(Icons.call),
            label: Text(
              access.adminName != null ? 'Call ${access.adminName}' : 'Call the owner',
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
          Text(access.adminPhone!,
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade600)),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onRecheck,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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
  bool updateShouldNotify(LockedSalonScope oldWidget) => oldWidget.salonId != salonId;
}
