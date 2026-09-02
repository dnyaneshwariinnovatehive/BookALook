import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'screens/phone_screen.dart';

void main() {
  runApp(const PartnerApp());
}

class PartnerApp extends StatelessWidget {
  const PartnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BookALook Partner',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const PhoneScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DummyDashboardScreen extends StatelessWidget {
  const DummyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner Dashboard'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront, size: 80, color: Theme.of(context).primaryColor),
            const SizedBox(height: 16),
            Text(
              'Welcome, Admin!',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'Ready to register your Salon?',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
