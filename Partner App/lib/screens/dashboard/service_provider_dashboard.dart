import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../phone_screen.dart';

class ServiceProviderDashboard extends StatelessWidget {
  final Map<String, dynamic> salon;
  const ServiceProviderDashboard({super.key, required this.salon});

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
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('My Workspace', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppTheme.lightBorder,
              backgroundImage: salon['cover_photo_url'] != null
                  ? NetworkImage(salon['cover_photo_url'])
                  : null,
              child: salon['cover_photo_url'] == null
                  ? Text(
                      salon['name']?.substring(0, 1).toUpperCase() ?? 'S',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: AppTheme.lightTextHeading),
                    )
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              'Working at ${salon['name'] ?? 'Salon'}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
            ),
            const SizedBox(height: 8),
            Text(
              salon['city'] ?? '',
              style: const TextStyle(fontSize: 14, color: AppTheme.lightTextBody),
            ),
            const SizedBox(height: 32),
            const Text(
              'Service Provider Dashboard',
              style: TextStyle(fontSize: 16, color: AppTheme.accentColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'This space will contain your upcoming appointments, schedule, and earnings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.lightTextBody),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
