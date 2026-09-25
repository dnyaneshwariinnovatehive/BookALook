import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'main_screen.dart';
import 'profile_screen.dart';
import '../utils/app_haptics.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final bool isModal;
  final int returnIndex;

  const OtpScreen({Key? key, required this.phone, this.isModal = false, this.returnIndex = 0}) : super(key: key);

  @override
  _OtpScreenState createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  void _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      AppHaptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OTP must be exactly 6 characters')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.verifyOtp(widget.phone, otp);

      if (result == true) {
        AppHaptics.success();
        if (widget.isModal) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => MainScreen(initialIndex: widget.returnIndex)),
            (route) => false,
          );
        }
      } else if (result == 'requires_registration') {
        final loggedIn = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (context) => ProfileScreen(phone: widget.phone, isModal: widget.isModal, returnIndex: widget.returnIndex)),
        );
        if (loggedIn == true && widget.isModal) {
          if (mounted) Navigator.pop(context, true);
        }
      } else {
        AppHaptics.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid OTP. Please try again.')),
        );
      }
    } catch (e) {
      AppHaptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Verify OTP')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the OTP sent to\n${widget.phone}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              '(For testing, use 123456)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
            ),
            SizedBox(height: 32),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'OTP',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.security),
              ),
            ),
            
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : () {
                AppHaptics.lightImpact();
                _verifyOtp();
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading 
                ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.surface, strokeWidth: 2))
                : Text('Verify & Login', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
