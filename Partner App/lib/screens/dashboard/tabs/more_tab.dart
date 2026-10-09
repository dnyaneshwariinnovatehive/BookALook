import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../phone_screen.dart';
import '../../../main.dart';
import 'settings/salon_timings_screen.dart';
import '../more/subscription_billing_screen.dart';
import '../more/wallet_screen.dart';
import '../more/salon_location_screen.dart';
import '../more/salon_qr_screen.dart';
import '../more/salon_reviews_screen.dart';
import '../more/insights_screen.dart';
import '../more/payroll_screen.dart';
import '../more/salon_payouts_screen.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../notifications_screen.dart';
import '../../help_support_screen.dart';
import '../../../widgets/wallet_coin_pill.dart';
import '../more/edit_salon_profile_screen.dart';
import '../../../services/push_notification_service.dart';
import '../../../widgets/push_notification_toggle.dart';
import '../more/automated_messaging_screen.dart';

class MoreTab extends StatefulWidget {
  final Map<String, dynamic> salonData;
  final Function(Map<String, dynamic>)? onSalonUpdated;
  final String? planName;
  final int? daysRemaining;
  
  const MoreTab({
    super.key, 
    required this.salonData, 
    this.onSalonUpdated,
    this.planName,
    this.daysRemaining,
  });

  @override
  State<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<MoreTab> {
  late Map<String, dynamic> salonData;

  @override
  void initState() {
    super.initState();
    salonData = Map.from(widget.salonData);
  }

  /// `Switch Salon` and `Switch Account` are still standing in for this one
  /// method, so the dialog says plainly what the tap actually does instead of
  /// guessing at an intent the code does not implement yet.
  Future<void> _logout(BuildContext context, {required String action}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heading = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final body = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final danger = isDark ? AppTheme.darkDanger : AppTheme.lightDanger;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final salonName = (salonData['name'] ?? 'this salon').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Log out of $salonName?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: heading),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$action ends your session and returns you to the sign-in screen.',
                style: TextStyle(fontSize: 14, color: body, height: 1.4)),
            const SizedBox(height: 10),
            Text('Your bookings, staff and payouts for $salonName stay exactly as they are.',
                style: TextStyle(fontSize: 13, color: body, height: 1.4)),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Stay signed in', style: TextStyle(color: body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Log out',
                style: TextStyle(color: danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await PushNotificationService().unregisterDevice();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (context.mounted) {
      // Logging out has to replace the whole shell, not just this tab's stack.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const PhoneScreen()),
        (route) => false,
      );
    }
  }

  Widget _buildPlanBadge() {
    final name = widget.planName ?? 'Starter';
    final isGrowth = name.toLowerCase() == 'growth';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isGrowth ? Colors.purple.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
        border: Border.all(
          color: isGrowth ? Colors.purple.withValues(alpha: 0.5) : Colors.blue.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        name.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isGrowth ? Colors.purple : Colors.blue,
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('More', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
        actions: [
          WalletCoinPill(salonId: salonData['id'].toString(), compact: true),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 100), // padding for bottom nav
        children: [
          // Top Card (Salon Profile)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Container(
                      height: 120,
                      color: theme.dividerColor,
                      child: salonData['cover_photo_url'] != null
                          ? Image.network(
                              salonData['cover_photo_url'],
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Icon(Icons.image, size: 50, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                            )
                          : Icon(Icons.image, size: 50, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(salonData['name']?.toString() ?? 'Salon Name', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildPlanBadge(),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(salonData['city']?['name']?.toString() ?? 'City not specified', style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => EditSalonProfileScreen(salonData: salonData)),
                            ).then((updatedData) {
                              if (updatedData != null && updatedData is Map<String, dynamic>) {
                                setState(() {
                                  salonData.addAll(updatedData);
                                });
                                if (widget.onSalonUpdated != null) {
                                  widget.onSalonUpdated!(updatedData);
                                }
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Edit', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          _buildSectionHeading('Salon management'),
          _buildOptionTile(
            icon: Icons.storefront,
            iconColor: Colors.purple,
            title: 'Switch Salon',
            onTap: () => _logout(context, action: 'Switch Salon'),
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.place_outlined,
            iconColor: AppTheme.accentColor,
            title: 'Salon Location',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalonLocationScreen(salonId: salonData['id'].toString()))),
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.access_time,
            iconColor: isDark ? AppTheme.darkWarning : AppTheme.lightWarning,
            title: 'Change Salon Timings',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalonTimingsScreen(salonId: salonData['id'].toString()))),
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.qr_code_2,
            iconColor: AppTheme.accentColor,
            title: 'Your QR Code',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalonQrScreen(salonId: salonData['id'].toString()))),
          ),

          _buildSectionHeading('Insights & communication'),
          _buildOptionTile(
            icon: Icons.insights_outlined,
            iconColor: Colors.deepPurple,
            title: 'Business Insights',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InsightsScreen(salonId: salonData['id'].toString()))),
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.star_outline_rounded,
            iconColor: const Color(0xFFF5A623),
            title: 'Customer Reviews',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalonReviewsScreen(salonId: salonData['id'].toString()))),
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.notifications_outlined,
            iconColor: isDark ? AppTheme.darkWarning : AppTheme.lightWarning,
            title: 'Notifications',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.mark_chat_read,
            iconColor: Colors.green,
            title: 'Automated Messaging',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AutomatedMessagingScreen(salonId: salonData['id'].toString()))),
          ),

          _buildSectionHeading('Payments & payroll'),
          _buildOptionTile(
            icon: Icons.account_balance_wallet,
            iconColor: Colors.amber,
            title: 'My Wallet',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WalletScreen(salonId: salonData['id'].toString()))),
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.account_balance,
            iconColor: Colors.blueGrey,
            title: 'Payouts from BookALook',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalonPayoutsScreen(salonId: salonData['id'].toString()))),
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.groups,
            iconColor: Colors.indigo,
            title: 'Staff Payroll',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PayrollScreen(salonId: salonData['id'].toString()))),
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.receipt_long,
            iconColor: Colors.teal,
            title: 'Subscription & Billing',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubscriptionBillingScreen(salonId: salonData['id'].toString()))),
          ),

          _buildSectionHeading('Account & app settings'),
          _buildOptionTile(
            icon: Icons.manage_accounts,
            iconColor: isDark ? AppTheme.darkInfo : AppTheme.lightInfo,
            title: 'Switch Account',
            onTap: () => _logout(context, action: 'Switch Account'),
          ),
          _buildDivider(),
          const PushNotificationToggle(),
          _buildDivider(),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, _) {
              final isDark = currentMode == ThemeMode.dark;
              return SwitchListTile(
                value: isDark,
                onChanged: (val) async {
                  themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('isDarkMode', val);
                },
                secondary: Icon(
                  isDark ? Icons.dark_mode : Icons.light_mode,
                  color: isDark ? Colors.yellow : Colors.orange,
                  size: 26,
                ),
                title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.normal, fontSize: 16)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              );
            },
          ),
          _buildDivider(),
          _buildOptionTile(
            icon: Icons.help_outline,
            iconColor: isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess,
            title: 'Help & Support',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen())),
          ),

          const SizedBox(height: 16),
          
          // Logout Button
          InkWell(
            onTap: () => _logout(context, action: 'Logging out'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Text(
                'Log out',
                style: TextStyle(
                  color: isDark ? AppTheme.darkDanger : AppTheme.lightDanger, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeading(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 66,
      color: isDark ? Colors.white24 : Colors.black12,
    );
  }

  Widget _buildOptionTile({
    required IconData icon, 
    required Color iconColor, 
    required String title, 
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title, 
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios, 
              size: 14, 
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
