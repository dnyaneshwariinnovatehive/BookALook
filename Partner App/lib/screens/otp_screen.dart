import 'dart:convert';
import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'dashboard/dashboard_screen.dart';
import 'registration/admin_registration_screen.dart';
import 'dashboard/salon_selection_screen.dart';
import 'dashboard/service_provider_dashboard.dart';
import 'dashboard/collaborator_dashboard.dart';
import '../services/push_notification_service.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());
  final _authService = AuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 6; i++) {
      _focusNodes[i].onKeyEvent = (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
          if (_controllers[i].text.isEmpty && i > 0) {
            _focusNodes[i - 1].requestFocus();
            _controllers[i - 1].clear();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      };
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _verifyOtp() async {
    String otp = _controllers.map((c) => c.text).join();
    if (otp.length < 6) return;

    setState(() => _isLoading = true);
    final response = await _authService.verifyOtp(widget.phone, otp);
    if (mounted) setState(() => _isLoading = false);

    if (response['success'] == true) {
      if (!mounted) return;

      if (response['status'] == 'new_user') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => AdminRegistrationScreen(phone: widget.phone, initialData: response['enquiry'])),
        );
      } else if (response['status'] == 'existing_user') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', response['token'] ?? '');
        await prefs.setString('role', response['role'] ?? '');
        await prefs.setString('auth_state', jsonEncode(response));
        
        PushNotificationService().registerDevice();

        if (!mounted) return;

        if (response['role'] == 'admin') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => SalonSelectionScreen(salons: response['salons'] ?? []),
            ),
            (route) => false,
          );
        } else if (response['role'] == 'service_provider') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => ServiceProviderDashboard(
                salon: response['salon'] ?? {},
                provider: response['provider'] ?? {},
                user: response['user'] ?? {},
              ),
            ),
            (route) => false,
          );
        } else if (response['role'] == 'collaborator') {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => const CollaboratorDashboardScreen(),
            ),
            (route) => false,
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['message'] ?? 'Invalid OTP')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Verify Phone',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextBody : AppTheme.lightTextBody, fontSize: 16),
                  children: [
                    const TextSpan(text: 'Code sent to '),
                    TextSpan(
                      text: widget.phone,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  6,
                  (index) => SizedBox(
                    width: 48,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      maxLength: 1,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.accentColor, width: 2),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          if (index < 5) {
                            _focusNodes[index + 1].requestFocus();
                          } else {
                            _focusNodes[index].unfocus();
                            _verifyOtp();
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: _isLoading
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.surface, strokeWidth: 2))
                    : Text('Verify', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
