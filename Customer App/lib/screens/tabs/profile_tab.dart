import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_restricted_view.dart';
import '../../services/auth_service.dart';
import '../phone_screen.dart';

class ProfileTab extends StatelessWidget {
  final bool isGuest;

  const ProfileTab({Key? key, required this.isGuest}) : super(key: key);

  void _logout(BuildContext context) async {
    final authService = AuthService();
    await authService.logout();
    
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => PhoneScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return GuestRestrictedView(
        title: 'Sign In Required',
        message: 'Please sign in to access your profile settings and history.',
        icon: Icons.person_outline,
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Header
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    child: Icon(Icons.person, size: 50, color: Theme.of(context).colorScheme.primary),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'My Profile',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 40),
            
            // Settings Placeholder
            ListTile(
              leading: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
              title: Text('Account Settings'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {},
            ),
            Divider(color: Theme.of(context).dividerColor),
            ListTile(
              leading: Icon(Icons.payment, color: Theme.of(context).colorScheme.primary),
              title: Text('Payment Methods'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {},
            ),
            Divider(color: Theme.of(context).dividerColor),
            ListTile(
              leading: Icon(Icons.help_outline, color: Theme.of(context).colorScheme.primary),
              title: Text('Help & Support'),
              trailing: Icon(Icons.chevron_right),
              onTap: () {},
            ),
            
            SizedBox(height: 48),
            
            // Logout Button
            OutlinedButton.icon(
              onPressed: () => _logout(context),
              icon: Icon(Icons.logout, color: Colors.red),
              label: Text(
                'Log Out',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: Colors.red.shade200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
