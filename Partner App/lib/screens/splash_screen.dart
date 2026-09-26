import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'phone_screen.dart';
import '../theme/app_theme.dart';
import 'dashboard/salon_selection_screen.dart';
import 'dashboard/service_provider_dashboard.dart';
import 'dashboard/collaborator_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    _navigateToNext();
  }

  void _navigateToNext() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final authStateStr = prefs.getString('auth_state');

    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      if (token != null && token.isNotEmpty && authStateStr != null) {
        final response = jsonDecode(authStateStr);
        if (response['role'] == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => SalonSelectionScreen(salons: response['salons'] ?? []),
            ),
          );
        } else if (response['role'] == 'service_provider') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ServiceProviderDashboard(
                salon: response['salon'] ?? {},
                provider: response['provider'] ?? {},
                user: response['user'] ?? {},
              ),
            ),
          );
        } else if (response['role'] == 'collaborator') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const CollaboratorDashboardScreen(),
            ),
          );
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PhoneScreen()));
        }
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PhoneScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Image.asset(
              'assets/images/logo.png',
              height: 120,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
