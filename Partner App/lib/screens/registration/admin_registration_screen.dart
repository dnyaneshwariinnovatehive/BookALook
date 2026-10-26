import 'dart:convert';
import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'steps/step1_owner_details.dart';
import 'steps/step2_salon_details.dart';
import 'steps/step3_terms.dart';
import 'steps/step_bank_details.dart';
import '../../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../dashboard/salon_selection_screen.dart';

class AdminRegistrationScreen extends StatefulWidget {
  final String? phone;
  final Map<String, dynamic>? initialData;
  final bool isExistingAdmin;
  const AdminRegistrationScreen({super.key, this.phone, this.initialData, this.isExistingAdmin = false});

  @override
  State<AdminRegistrationScreen> createState() => _AdminRegistrationScreenState();
}

class _AdminRegistrationScreenState extends State<AdminRegistrationScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;

  // Form Data
  final Map<String, dynamic> _formData = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _formData.addAll(widget.initialData!);
    }
  }

  void _nextStep(Map<String, dynamic> stepData) {
    _formData.addAll(stepData);
    if (_currentStep < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    } else {
      _submitRegistration();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _submitRegistration() async {
    setState(() => _isLoading = true);
    
    final result = await ApiService.registerSalon(_formData);
    
    if (mounted) setState(() => _isLoading = false);

    if (result['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isRegistered', true);
      
      final data = result['data'] ?? {};
      final newSalon = data['salon'];
      List<dynamic> allSalons = [];

      if (data['salons'] is List && (data['salons'] as List).isNotEmpty) {
        allSalons = List<dynamic>.from(data['salons']);
      } else {
        // Fallback: merge newly registered salon into existing salons list in auth_state
        final authStateStr = prefs.getString('auth_state');
        if (authStateStr != null) {
          try {
            final authState = jsonDecode(authStateStr);
            final existing = authState['salons'];
            if (existing is List) {
              allSalons = List<dynamic>.from(existing);
            }
          } catch (_) {}
        }
        if (newSalon != null) {
          final exists = allSalons.any((s) => s['id']?.toString() == newSalon['id']?.toString());
          if (!exists) {
            allSalons.insert(0, newSalon);
          }
        }
      }

      // Update auth_state so splash screen and future app launches have all salons
      final authStateStr = prefs.getString('auth_state');
      Map<String, dynamic> authState = {};
      if (authStateStr != null) {
        try {
          authState = Map<String, dynamic>.from(jsonDecode(authStateStr));
        } catch (_) {}
      }
      authState['salons'] = allSalons;
      if (data['user'] != null) {
        authState['user'] = data['user'];
      }
      if (data['token'] != null && (prefs.getString('auth_token') ?? '').isEmpty) {
        await prefs.setString('auth_token', data['token']);
        authState['token'] = data['token'];
      }
      authState['role'] = 'admin';
      await prefs.setString('auth_state', jsonEncode(authState));
      await prefs.setString('role', 'admin');

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => SalonSelectionScreen(
              salons: allSalons,
            ),
          ),
          (route) => false,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(milliseconds: 2500), content: Text(result['message'] ?? 'Registration failed')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Register Your Salon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildDot(0),
                    _buildLine(),
                    _buildDot(1),
                    _buildLine(),
                    _buildDot(2),
                    _buildLine(),
                    _buildDot(3),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Step ${_currentStep + 1} of 4', style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody)),
              ],
            ),
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Disable swipe to navigate
        children: [
          Step1OwnerDetails(onNext: _nextStep, onCancel: _previousStep, phone: widget.phone, initialData: widget.initialData, isExistingAdmin: widget.isExistingAdmin),
          Step2SalonDetails(onNext: _nextStep, onBack: _previousStep, initialData: widget.initialData),
          // Optional: a salon registers and goes live without it.
          StepBankDetails(onNext: _nextStep, onBack: _previousStep, offerSaved: widget.isExistingAdmin),
          Step3Terms(onSubmit: _nextStep, onBack: _previousStep, isLoading: _isLoading),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    bool isActive = index <= _currentStep;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? AppTheme.accentColor : AppTheme.lightBorder,
      ),
    );
  }

  Widget _buildLine() {
    return Container(
      width: 40,
      height: 2,
      color: AppTheme.lightBorder,
    );
  }
}
