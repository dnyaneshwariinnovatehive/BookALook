import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../phone_screen.dart';
import 'settings/salon_timings_screen.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('More Options'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.storefront, color: Colors.black87),
            title: const Text('Switch Salon'),
            subtitle: const Text('Manage a different salon under this account'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // TODO: Fetch salons and navigate to SalonSelectionScreen
              // For now, logging out works similarly for testing
              _logout(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.access_time, color: Colors.black87),
            title: const Text('Change Salon Timings'),
            subtitle: const Text('Update operating hours and closed days'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SalonTimingsScreen(salonId: salonId)),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.manage_accounts, color: Colors.black87),
            title: const Text('Switch Account / Logout'),
            subtitle: const Text('Log in with a different phone number'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _logout(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline, color: Colors.black87),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
