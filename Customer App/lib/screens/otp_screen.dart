import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'main_screen.dart';
import 'profile_screen.dart';
import '../utils/app_haptics.dart';
import '../utils/auth_motion.dart';
import '../widgets/auth/otp_boxes.dart';
import '../theme/app_colors.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final bool isModal;
  final int returnIndex;

  const OtpScreen(
      {Key? key,
      required this.phone,
      this.isModal = false,
      this.returnIndex = 0})
      : super(key: key);

  @override
  _OtpScreenState createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  /// Inline status instead of a SnackBar, so nothing covers the boxes the user
  /// is looking at while the keyboard is still up.
  String? _error;
  String? _info;
  bool _hasError = false;
  int _shakeToken = 0;
  bool _verified = false;

  int? _resendIn;
  Timer? _resendTimer;

  /// Single cancellable periodic timer rather than a chain of awaits, so
  /// leaving the screen cannot leave a pending timer behind.
  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = (_resendIn ?? 1) - 1;
      if (next <= 0) {
        timer.cancel();
        setState(() => _resendIn = null);
      } else {
        setState(() => _resendIn = next);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _startResendCountdown(30);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _fail(String message) {
    AppHaptics.error();
    SystemSound.play(SystemSoundType.click);
    setState(() {
      _error = message;
      _hasError = true;
      _shakeToken++;
    });
  }

  Future<void> _resend() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _hasError = false;
      _isLoading = true;
      _info = 'Sending a new code…';
    });

    final result = await _authService.sendOtp(widget.phone);
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _info = null;
    });

    if (result == 'success') {
      AppHaptics.success();
      setState(() {
        _error = null;
        _hasError = false;
        _info = 'A new code is on its way.';
      });
      _otpController.clear();
      _startResendCountdown(30);
    } else {
      _fail('Could not resend right now. Please try again.');
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _fail('Enter all 6 digits to continue.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
      _hasError = false;
    });

    try {
      final result = await _authService.verifyOtp(widget.phone, otp);

      if (!mounted) return;

      if (result == true) {
        AppHaptics.success();
        setState(() => _verified = true);
        // Hold the success state briefly so it registers, then hand off.
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        if (widget.isModal) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            authRoute(
              builder: (context) =>
                  MainScreen(initialIndex: widget.returnIndex),
            ),
            (route) => false,
          );
        }
      } else if (result == 'requires_registration') {
        final loggedIn = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileScreen(
              phone: widget.phone,
              isModal: widget.isModal,
              returnIndex: widget.returnIndex,
            ),
          ),
        );
        if (loggedIn == true && widget.isModal && mounted) {
          Navigator.pop(context, true);
        }
      } else {
        _fail('That code is not right. Check the digits and try again.');
        _otpController.clear();
      }
    } catch (e) {
      _fail('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = context.colors.textSecondary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: AuthShell(
        child: SafeArea(
          child: GestureDetector(
            // Tapping the backdrop dismisses the keyboard so a mis-typed code is
            // not stuck behind a covering sheet.
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: _verified
                    ? _buildVerified(theme, muted)
                    : _buildForm(theme, muted),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerified(ThemeData theme, Color muted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SuccessTick(),
        const SizedBox(height: 24),
        Text(
          'Verified',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Taking you to BookALook…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: muted),
        ),
      ],
    );
  }

  Widget _buildForm(ThemeData theme, Color muted) {
    return StaggeredReveal(
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.accentSoft,
              ),
              child: Icon(Icons.sms_rounded,
                  size: 26, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              'Enter the OTP',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'We sent a 6-digit code to\n+91 ${widget.phone}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.45, color: muted),
            ),
          ],
        ),
        const SizedBox(height: 30),

        Shake(
          token: _shakeToken,
          child: OtpBoxes(
            controller: _otpController,
            autofocus: true,
            hasError: _hasError,
            shakeToken: _shakeToken,
            onCompleted: () {
              AppHaptics.mediumImpact();
              _verifyOtp();
            },
            onChanged: (text) {
              if (_error != null && text.isNotEmpty) {
                setState(() {
                  _error = null;
                  _hasError = false;
                });
              }
            },
          ),
        ),
        const SizedBox(height: 14),

        // Inline status row, animated in and out of the layout.
        AnimatedSize(
          duration: AuthMotion.base,
          curve: AuthMotion.curveInOut,
          alignment: Alignment.topCenter,
          child: (_error == null && _info == null)
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _error != null
                      ? StatusNote(
                          text: _error!,
                          tone: theme.colorScheme.error,
                          icon: Icons.error_outline_rounded,
                        )
                      : StatusNote(
                          text: _info!,
                          tone: theme.colorScheme.primary,
                          icon: Icons.check_circle_outline_rounded,
                        ),
                ),
        ),
        const SizedBox(height: 10),

        SweepButton(
          label: 'Verify & Login',
          loading: _isLoading,
          onPressed: _isLoading
              ? null
              : () {
                  AppHaptics.lightImpact();
                  _verifyOtp();
                },
        ),
        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ResendCountdown(
              seconds: _resendIn,
              onResend: _isLoading ? null : _resend,
            ),
            Text(
              '·',
              style: TextStyle(color: muted),
            ),
            TextButton(
              onPressed: () {
                AppHaptics.selectionClick();
                Navigator.pop(context);
              },
              child: Text(
                'Change number',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
