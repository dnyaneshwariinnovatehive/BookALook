import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/auth_session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import '../utils/auth_errors.dart';
import '../utils/auth_motion.dart';
import '../widgets/auth/otp_boxes.dart';
import 'partner_home.dart';
import 'registration/admin_registration_screen.dart';

/// Signature of [partnerHomeFor], injectable so tests can route without
/// building three dashboards that each start talking to the API.
typedef PartnerHomeBuilder = Widget? Function(Map<String, dynamic> response);

/// Second step of sign-in: enter the code, then land where the account belongs.
///
/// The screen only verifies and navigates. Saving the session lives in
/// [AuthSession] and deciding the destination in [partnerHomeFor], so this
/// file holds no SharedPreferences keys and no role rules of its own.
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phone,
    this.authService,
    this.session,
    this.homeFor = partnerHomeFor,
    this.registrationBuilder,
  });

  final String phone;

  /// Injected by tests. Null means the real [AuthService].
  final AuthService? authService;

  /// Injected by tests. Null means the real [AuthSession].
  final AuthSession? session;

  final PartnerHomeBuilder homeFor;

  /// Where a number with no partner account goes. Null means the registration
  /// wizard, prefilled with the phone and any enquiry the sales team logged.
  final Widget Function(String phone, Map<String, dynamic>? enquiry)? registrationBuilder;

  /// How long a resend stays locked after a code goes out.
  static const int resendSeconds = 30;

  /// How long the verified tick is held before handing off, so it registers.
  static const Duration verifiedHold = Duration(milliseconds: 900);

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  late final AuthService _authService = widget.authService ?? AuthService();
  late final AuthSession _session = widget.session ?? AuthSession();

  bool _isVerifying = false;
  bool _isResending = false;
  bool _verified = false;
  bool _newPartner = false;

  /// Inline status instead of a SnackBar, so nothing covers the boxes the user
  /// is looking at while the keyboard is still up.
  String? _error;
  String? _info;
  int _shakeToken = 0;

  int? _resendIn;
  Timer? _resendTimer;
  Timer? _slowTimer;

  static const _slowAfter = Duration(seconds: 6);

  bool get _busy => _isVerifying || _isResending;

  @override
  void initState() {
    super.initState();
    _startResendCountdown(OtpScreen.resendSeconds);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _slowTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

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

  /// Shows [message] if the request is still running after a few seconds.
  void _watchForSlowness(String message) {
    _slowTimer?.cancel();
    _slowTimer = Timer(_slowAfter, () {
      if (mounted && _busy) setState(() => _info = message);
    });
  }

  void _fail(String message) {
    AppHaptics.error();
    setState(() {
      _error = message;
      _info = null;
      _shakeToken++;
    });
  }

  Future<void> _resend() async {
    AppHaptics.lightImpact();
    setState(() {
      _isResending = true;
      _error = null;
      _info = 'Sending a new code…';
    });
    _watchForSlowness('Still sending your new code. This is taking longer than usual…');

    final result = await _authService.sendOtp(widget.phone);
    _slowTimer?.cancel();
    if (!mounted) return;
    setState(() => _isResending = false);

    if (result == 'success') {
      AppHaptics.success();
      _otpController.clear();
      setState(() {
        _error = null;
        _info = 'A new code is on its way.';
      });
      _startResendCountdown(OtpScreen.resendSeconds);
    } else {
      // The countdown is not restarted, so the partner can try again at once.
      _fail(friendlyAuthError(result, fallback: 'Could not resend the code. Please try again.'));
    }
  }

  Future<void> _verifyOtp() async {
    if (_busy || _verified) return;

    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _fail('Enter all 6 digits to continue.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isVerifying = true;
      _error = null;
      _info = null;
    });
    _watchForSlowness('Still checking your code. This is taking longer than usual…');

    final response = await _authService.verifyOtp(widget.phone, otp);
    _slowTimer?.cancel();
    if (!mounted) return;

    if (response['success'] != true) {
      setState(() => _isVerifying = false);
      _otpController.clear();
      _fail(_verifyError(response['message']));
      return;
    }

    switch (response['status']) {
      case 'new_user':
        final enquiry = response['enquiry'];
        await _handOff(
          newPartner: true,
          next: (widget.registrationBuilder ?? _registration)(
            widget.phone,
            enquiry is Map<String, dynamic> ? enquiry : null,
          ),
          replaceStack: false,
        );

      case 'existing_user':
        final home = widget.homeFor(response);
        if (home == null) {
          // A role this app has no home for. Saving the session would only
          // send the partner round in a circle via the splash screen.
          setState(() => _isVerifying = false);
          _fail('This account cannot sign in to the Partner App. '
              'Please contact BookALook support.');
          return;
        }
        try {
          await _session.save(response);
        } catch (_) {
          if (!mounted) return;
          setState(() => _isVerifying = false);
          _fail('Could not finish signing you in. Please try again.');
          return;
        }
        await _handOff(newPartner: false, next: home, replaceStack: true);

      default:
        setState(() => _isVerifying = false);
        _fail('Something went wrong. Please try again.');
    }
  }

  Widget _registration(String phone, Map<String, dynamic>? enquiry) =>
      AdminRegistrationScreen(phone: phone, initialData: enquiry);

  /// Shows the verified tick, holds it briefly, then moves on.
  ///
  /// A new partner replaces the OTP screen, so back from the wizard returns to
  /// the phone screen; a signed-in partner clears the auth stack entirely.
  Future<void> _handOff({
    required bool newPartner,
    required Widget next,
    required bool replaceStack,
  }) async {
    if (!mounted) return;
    AppHaptics.success();
    setState(() {
      _isVerifying = false;
      _verified = true;
      _newPartner = newPartner;
    });
    _resendTimer?.cancel();

    await Future<void>.delayed(OtpScreen.verifiedHold);
    if (!mounted) return;

    final route = authRoute<void>(builder: (_) => next);
    if (replaceStack) {
      Navigator.pushAndRemoveUntil(context, route, (route) => false);
    } else {
      Navigator.pushReplacement(context, route);
    }
  }

  String _verifyError(Object? message) {
    final text = message?.toString();
    // The backend's wording is terse; this is the message a partner sees most.
    if (text == null || text == 'Invalid OTP') {
      return 'That code is not right. Check the digits and try again.';
    }
    return friendlyAuthError(text, fallback: 'Something went wrong. Please try again.');
  }

  String get _displayPhone {
    final p = widget.phone;
    return p.length == 10 ? '+91 ${p.substring(0, 5)} ${p.substring(5)}' : '+91 $p';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: _verified
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: AuthShell(
        child: SafeArea(
          child: GestureDetector(
            // Tapping the backdrop dismisses the keyboard so a mis-typed code is
            // not stuck behind it.
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _verified ? _buildVerified(colors) : _buildForm(colors),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerified(AppColors colors) {
    final next = _newPartner ? 'Let’s set up your salon…' : 'Taking you to your dashboard…';
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SuccessTick(),
          const SizedBox(height: 24),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            next,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(AppColors colors) {
    return StaggeredReveal(
      children: [
        Column(
          children: [
            ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accentSoft),
                child: const Icon(Icons.sms_rounded, size: 26, color: AppTheme.accentColor),
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              header: true,
              child: Text(
                'Enter the code',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'We sent a 6-digit code to\n$_displayPhone',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.45, color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 30),

        Shake(
          token: _shakeToken,
          child: OtpBoxes(
            controller: _otpController,
            autofocus: true,
            enabled: !_isVerifying,
            hasError: _error != null,
            onCompleted: () {
              AppHaptics.mediumImpact();
              _verifyOtp();
            },
            onChanged: (text) {
              if (_error != null && text.isNotEmpty) {
                setState(() => _error = null);
              }
            },
          ),
        ),
        const SizedBox(height: 14),

        // Inline status row, animated in and out of the layout.
        AnimatedSize(
          duration: AuthMotion.reduceMotion(context) ? Duration.zero : AuthMotion.base,
          curve: AuthMotion.curveInOut,
          alignment: Alignment.topCenter,
          child: (_error == null && _info == null)
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _error != null
                      ? StatusNote(
                          text: _error!,
                          tone: colors.danger,
                          background: colors.dangerBg,
                          icon: Icons.error_outline_rounded,
                        )
                      : StatusNote(
                          text: _info!,
                          tone: colors.info,
                          background: colors.infoBg,
                          icon: Icons.info_outline_rounded,
                        ),
                ),
        ),
        const SizedBox(height: 10),

        SweepButton(
          label: 'Verify & continue',
          loading: _isVerifying,
          onPressed: _busy
              ? null
              : () {
                  AppHaptics.lightImpact();
                  _verifyOtp();
                },
        ),
        const SizedBox(height: 14),

        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ResendCountdown(
              seconds: _resendIn,
              onResend: _busy ? null : _resend,
            ),
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('·', style: TextStyle(color: colors.textSecondary)),
              ),
            ),
            TextButton(
              onPressed: _isVerifying
                  ? null
                  : () {
                      AppHaptics.selectionClick();
                      Navigator.pop(context);
                    },
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(
                'Change number',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
