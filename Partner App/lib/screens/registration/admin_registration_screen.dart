import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'steps/step1_owner_details.dart';
import 'steps/step2_salon_details.dart';
import 'steps/step3_terms.dart';
import '../../services/api_service.dart';

class AdminRegistrationScreen extends StatefulWidget {
  const AdminRegistrationScreen({super.key});

  @override
  State<AdminRegistrationScreen> createState() => _AdminRegistrationScreenState();
}

class _AdminRegistrationScreenState extends State<AdminRegistrationScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;

  // Form Data
  final Map<String, dynamic> _formData = {};

  void _nextStep(Map<String, dynamic> stepData) {
    _formData.addAll(stepData);
    if (_currentStep < 2) {
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

    if (result['success']) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Registration Successful'),
            content: const Text('Your salon has been registered and is pending SuperAdmin approval. You can log in once approved.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close Dialog
                  Navigator.pop(context); // Go back to login
                },
                child: const Text('OK'),
              )
            ],
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Registration failed')),
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
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Register Your Salon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                  ],
                ),
                const SizedBox(height: 8),
                Text('Step ${_currentStep + 1} of 3', style: const TextStyle(fontSize: 12, color: AppTheme.lightTextBody)),
              ],
            ),
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Disable swipe to navigate
        children: [
          Step1OwnerDetails(onNext: _nextStep, onCancel: _previousStep),
          Step2SalonDetails(onNext: _nextStep, onBack: _previousStep),
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
