import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../phone_screen.dart';
import 'settings/salon_timings_screen.dart';
import 'package:partner_app/theme/app_theme.dart';

class MoreTab extends StatelessWidget {
  final String salonId;
  const MoreTab({super.key, required this.salonId});

  void _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
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
        title: const Text('More', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
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
                      color: isDark ? Colors.grey[800] : Colors.grey[300],
                      // Placeholder for actual salon image
                      child: Icon(Icons.image, size: 50, color: isDark ? Colors.grey[600] : Colors.grey),
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
                              const Text('Luxe Studio Salon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Shop 4, Royal Avenue, Koregaon Park, Pune - 411001', style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Edit', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
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
                  const Divider(height: 1, indent: 56),
                  _buildOptionTile(context, 
                    icon: Icons.access_time,
                    iconColor: Colors.orange,
                    title: 'Change Salon Timings',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SalonTimingsScreen(salonId: salonId)),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildOptionTile(context, 
                    icon: Icons.manage_accounts,
                    iconColor: Colors.blue,
                    title: 'Switch Account',
                    onTap: () => _logout(context),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildOptionTile(context, 
                    icon: Icons.help_outline,
                    iconColor: Colors.green,
                    title: 'Help & Support',
                    onTap: () {},
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
                  color: isDark ? Colors.red.withOpacity(0.15) : const Color(0xFFFDECEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
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
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      trailing: Icon(Icons.arrow_forward_ios, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
