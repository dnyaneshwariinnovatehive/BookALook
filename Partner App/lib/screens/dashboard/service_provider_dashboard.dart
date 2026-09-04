import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../phone_screen.dart';
import 'tabs/provider_profile_tab.dart';
import '../provider_dashboard_screen.dart';

class ServiceProviderDashboard extends StatefulWidget {
  final Map<String, dynamic> salon;
  final Map<String, dynamic> provider;
  final Map<String, dynamic> user;
  
  const ServiceProviderDashboard({
    super.key, 
    required this.salon,
    required this.provider,
    required this.user,
  });

  @override
  State<ServiceProviderDashboard> createState() => _ServiceProviderDashboardState();
}

class _ServiceProviderDashboardState extends State<ServiceProviderDashboard> {
  int _currentIndex = 0; // Default to home tab as requested

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
    final List<Widget> pages = [
      const Center(child: Text('Home')),
      ProviderDashboardScreen(salonId: widget.salon['id'].toString()),
      const Center(child: Text('Add Walk-in')),
      ProviderProfileTab(
        salon: widget.salon,
        provider: widget.provider,
        user: widget.user,
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedItemColor: AppTheme.accentColor,
          unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today),
              label: 'Schedule',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_add_alt_1_outlined),
              activeIcon: Icon(Icons.person_add_alt_1),
              label: 'Add Walk-in',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
