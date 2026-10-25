import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/profile_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Move the account to a new phone number. The number is the login, so it
/// is changed only after an OTP sent to the new number is entered.
///
/// Pops with the new number when it is saved. [sendCode] and [confirm] are
/// injectable for tests; they default to the real API.
class ChangePhoneScreen extends StatefulWidget {
  final String? currentPhone;
  final Future<String> Function(String phone)? sendCode;
  final Future<String> Function(String phone, String otp)? confirm;

  const ChangePhoneScreen({super.key, this.currentPhone, this.sendCode, this.confirm});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _info;
  int _resendIn = 0;
  Timer? _timer;

  Future<String> _send(String phone) =>
      (widget.sendCode ?? ProfileService().sendPhoneChangeOtp)(phone);
  Future<String> _confirm(String phone, String otp) =>
      (widget.confirm ?? ProfileService().confirmPhoneChange)(phone, otp);

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  String _clean(String s) => s.replaceAll(RegExp(r'[\s\-()]'), '');

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    final phone = _clean(_phone.text);
    if (!RegExp(r'^\+?[0-9]{10,14}$').hasMatch(phone)) {
      setState(() => _error = 'Enter a valid phone number.');
      return;
    }
    if (phone == widget.currentPhone) {
      setState(() => _error = 'This is already your phone number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await _send(phone);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _info = message;
        _otp.clear();
      });
      _startResendTimer();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final otp = _otp.text.trim();
    if (otp.length < 4) {
      setState(() => _error = 'Enter the code we sent.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await _confirm(_clean(_phone.text), otp);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number updated.')),
      );
      Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    InputDecoration field(String label, {String? hint}) => InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: GoogleFonts.outfit(color: colors.textSecondary),
          filled: true,
          fillColor: colors.surface,
          counterText: '',
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.accentColor, width: 2),
          ),
        );

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: AppBar(
        title: Text('Change phone number',
            style: GoogleFonts.outfit(color: colors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((widget.currentPhone ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('Current number: ${widget.currentPhone}',
                    style: GoogleFonts.outfit(color: colors.textSecondary)),
              ),
            Text(
              'You sign in with this number, so we will send an OTP to the new one before changing it.',
              style: GoogleFonts.outfit(color: colors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('change_phone_number'),
              controller: _phone,
              enabled: !_codeSent && !_busy,
              keyboardType: TextInputType.phone,
              maxLength: 16,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]'))],
              style: GoogleFonts.outfit(color: colors.textPrimary),
              decoration: field('New phone number'),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              if (_info != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_info!, style: GoogleFonts.outfit(color: colors.textSecondary, fontSize: 13)),
                ),
              TextField(
                key: const ValueKey('change_phone_otp'),
                controller: _otp,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.outfit(color: colors.textPrimary, letterSpacing: 6, fontSize: 18),
                decoration: field('OTP', hint: '6-digit code'),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _info = null;
                              _error = null;
                            }),
                    child: const Text('Change number'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: (_busy || _resendIn > 0) ? null : _sendCode,
                    child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend OTP'),
                  ),
                ],
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    key: const ValueKey('change_phone_error'),
                    style: GoogleFonts.outfit(color: colors.danger, fontSize: 13)),
              ),
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                key: const ValueKey('change_phone_submit'),
                onPressed: _busy ? null : (_codeSent ? _verify : _sendCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_codeSent ? 'Verify and save' : 'Send OTP',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
