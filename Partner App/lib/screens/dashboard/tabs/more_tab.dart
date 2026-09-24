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
import '../more/marketing_screen.dart';
import '../more/insights_screen.dart';
import '../more/payroll_screen.dart';
import '../more/salon_payouts_screen.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../notifications_screen.dart';
import '../../../widgets/wallet_coin_pill.dart';

class MoreTab extends StatelessWidget {
  final Map<String, dynamic> salonData;
  const MoreTab({super.key, required this.salonData});

  void _logout(BuildContext context) async {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('More', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
        actions: [
          WalletCoinPill(salonId: salonData['id'].toString(), compact: true),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Card
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Container(
                      height: 120,
                      color: isDark ? Theme.of(context).dividerColor : Theme.of(context).dividerColor,
                      // Placeholder for actual salon image
                      child: Icon(Icons.image, size: 50, color: isDark ? Theme.of(context).dividerColor : Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
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
                              Text(salonData['name']?.toString() ?? 'Salon Name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(salonData['city']?['name']?.toString() ?? 'City not specified', style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            // Link to Location screen as it's the only editable salon info right now
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => SalonLocationScreen(salonId: salonData['id'].toString())),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Edit', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Options List
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  _buildOptionTile(context, 
                    icon: Icons.storefront,
                    iconColor: Colors.purple,
                    title: 'Switch Salon',
                    onTap: () => _logout(context), // Using logout as placeholder per old logic
                  ),
                  Divider(height: 1, indent: 56),
                  _buildOptionTile(context, 
                    icon: Icons.access_time,
                    iconColor: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkWarning : AppTheme.lightWarning),
                    title: 'Change Salon Timings',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SalonTimingsScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  // SuperAdmin's warnings and suspensions are the messages an
                  // owner most needs to see, so the inbox sits at the top.
                  _buildOptionTile(context,
                    icon: Icons.notifications_outlined,
                    iconColor: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkWarning : AppTheme.lightWarning),
                    title: 'Notifications',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  // Customers browse nearest-first, so an unpinned salon sorts
                  // below every salon on the same street that has pinned itself.
                  _buildOptionTile(context,
                    icon: Icons.place_outlined,
                    iconColor: AppTheme.accentColor,
                    title: 'Salon Location',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SalonLocationScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  // What customers said. High up the list on purpose — it is
                  // the only page here that tells an owner how the business is
                  // actually doing.
                  _buildOptionTile(context,
                    icon: Icons.star_outline_rounded,
                    iconColor: const Color(0xFFF5A623),
                    title: 'Customer Reviews',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SalonReviewsScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  // Directly above Marketing, because it is where the reason to
                  // send a campaign comes from — who has stopped coming in,
                  // which hours are empty, what customers already buy together.
                  _buildOptionTile(context,
                    icon: Icons.insights_outlined,
                    iconColor: Colors.deepPurple,
                    title: 'Business Insights',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => InsightsScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  // Sits next to Reviews because the two answer the same
                  // question from opposite ends: what customers think, and what
                  // the salon can say back to them.
                  _buildOptionTile(context,
                    icon: Icons.campaign_outlined,
                    iconColor: const Color(0xFF25D366),
                    title: 'WhatsApp Marketing',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => MarketingScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  // The poster that goes in the window. Prints to a real PNG.
                  _buildOptionTile(context,
                    icon: Icons.qr_code_2,
                    iconColor: AppTheme.accentColor,
                    title: 'Your QR Code',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SalonQrScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  _buildOptionTile(context, 
                    icon: Icons.receipt_long,
                    iconColor: Colors.teal,
                    title: 'Subscription & Billing',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SubscriptionBillingScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  _buildOptionTile(context,
                    icon: Icons.groups,
                    iconColor: Colors.indigo,
                    title: 'Staff Payroll',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => PayrollScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  _buildOptionTile(context,
                    icon: Icons.account_balance,
                    iconColor: Colors.blueGrey,
                    title: 'Payouts from BookALook',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SalonPayoutsScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  _buildOptionTile(context, 
                    icon: Icons.account_balance_wallet,
                    iconColor: Colors.amber,
                    title: 'My Wallet',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => WalletScreen(salonId: salonData['id'].toString())),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56),
                  _buildOptionTile(context, 
                    icon: Icons.manage_accounts,
                    iconColor: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkInfo : AppTheme.lightInfo),
                    title: 'Switch Account',
                    onTap: () => _logout(context),
                  ),
                  Divider(height: 1, indent: 56),
                  _buildOptionTile(context, 
                    icon: Icons.help_outline,
                    iconColor: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess),
                    title: 'Help & Support',
                    onTap: () {},
                  ),
                  Divider(height: 1, indent: 56),
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
                        ),
                        title: Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Logout Button
            GestureDetector(
              onTap: () => _logout(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger).withOpacity(0.15) : const Color(0xFFFDECEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Logout',
                  style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger), fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(BuildContext context, {required IconData icon, required Color iconColor, required String title, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      trailing: Icon(Icons.arrow_forward_ios, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
