import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import '../utils/auth_errors.dart';
import '../utils/auth_motion.dart';
import '../widgets/auth/otp_boxes.dart';
import 'otp_screen.dart';
import 'registration/admin_registration_screen.dart';

/// Entry to the Partner App: log in with a phone number, or start registering a
/// salon.
///
/// The two modes share one sliding control, and every way of asking to register
/// — the segment or the link under the form — lands in the same Register mode,
/// whose button opens the registration wizard. Registration does not verify the
/// phone first; the wizard collects it, as it always has.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, this.authService});

  /// Injected by tests. Null means the real [AuthService].
  final AuthService? authService;

  /// Keys for the Login / Register indicator.
  ///
  /// Public so tests can measure where the knob is actually painted rather
  /// than reading AnimatedAlign.alignment, which only reports the destination
  /// and would make a jump look identical to a real slide.
  ///
  /// modeKnobKey sits on the pill itself, not on the AnimatedAlign: an
  /// alignment widget fills its parent, so keying it would measure the rail.
  static const Key modeRailKey = Key('auth-mode-rail');
  static const Key modeKnobKey = Key('auth-mode-knob');

  /// The phone number field, for tests.
  static const Key phoneFieldKey = Key('auth-phone-field');

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phoneController = TextEditingController();
  late final AuthService _authService = widget.authService ?? AuthService();

  bool _isLogin = true;
  bool _isLoading = false;
  String? _error;
  String? _info;
  int _shakeToken = 0;

  /// Raised when a send is taking long enough that silence would read as a
  /// hang. Cancelled the moment the request returns.
  Timer? _slowTimer;

  static const _slowAfter = Duration(seconds: 6);

  @override
  void dispose() {
    _slowTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  void _setMode(bool login) {
    if (_isLogin == login) return;
    AppHaptics.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() {
      _isLogin = login;
      _error = null;
      _info = null;
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

  Future<void> _sendOtp() async {
    final phone = _phoneController.text;
    if (phone.length != 10) {
      _fail('Enter your 10-digit mobile number.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
      _info = null;
    });
    _slowTimer = Timer(_slowAfter, () {
      if (mounted && _isLoading) {
        setState(() => _info = 'Still sending your code. This is taking longer than usual…');
      }
    });

    final result = await _authService.sendOtp(phone);
    _slowTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _info = null;
    });

    if (result == 'success') {
      AppHaptics.success();
      await Navigator.push(
        context,
        authRoute<void>(
          builder: (context) => OtpScreen(phone: phone, authService: _authService),
        ),
      );
    } else {
      _fail(friendlyAuthError(result, fallback: 'We could not send a code right now. Please try again.'));
    }
  }

  void _startRegistration() {
    AppHaptics.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AdminRegistrationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuthShell(
        child: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: ConstrainedBox(
                  // Keeps the form a readable width on tablets and in landscape.
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: StaggeredReveal(
                    children: [
                      _header(colors),
                      const SizedBox(height: 32),
                      _modeSwitch(colors),
                      const SizedBox(height: 28),
                      AnimatedSize(
                        duration: AuthMotion.reduceMotion(context)
                            ? Duration.zero
                            : AuthMotion.base,
                        curve: AuthMotion.curveInOut,
                        alignment: Alignment.topCenter,
                        child: _isLogin ? _loginForm(colors) : _registerPanel(colors),
                      ),
                      const SizedBox(height: 20),
                      _switchLink(colors),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppColors colors) {
    return Column(
      children: [
        Semantics(
          label: 'BookALook Partner',
          image: true,
          child: Image.asset('assets/images/logo.png', height: 60, fit: BoxFit.contain),
        ),
        const SizedBox(height: 10),
        Text(
          'Manage your salon, services, and staff seamlessly',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// Sliding Login / Register control. The indicator sits behind both labels in
  /// a Stack and animates between them, so the switch reads as one piece
  /// moving rather than two colours swapping.
  Widget _modeSwitch(AppColors colors) {
    Widget tab(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          inMutuallyExclusiveGroup: true,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: AuthMotion.base,
                  curve: AuthMotion.curve,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    // The knob carries the selection; the label only needs to
                    // stay legible on it, so it takes the strongest text token.
                    color: selected ? colors.textPrimary : colors.textSecondary,
                  ),
                  child: Text(label),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(30),
      ),
      // Sized from the rail itself rather than the window, so the knob still
      // lines up in split-screen and on tablets.
      child: LayoutBuilder(
        builder: (context, rail) {
          return Stack(
            key: PhoneScreen.modeRailKey,
            children: [
              Positioned.fill(
                child: AnimatedAlign(
                  duration: AuthMotion.reduceMotion(context) ? Duration.zero : AuthMotion.base,
                  curve: AuthMotion.curve,
                  alignment: _isLogin ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    key: PhoneScreen.modeKnobKey,
                    width: rail.maxWidth / 2,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: colors.border),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentColor.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  tab('Login', _isLogin, () => _setMode(true)),
                  tab('Register', !_isLogin, () => _setMode(false)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _loginForm(AppColors colors) {
    return Column(
      key: const ValueKey('login-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Phone number',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Shake(
          token: _shakeToken,
          child: _phoneField(colors),
        ),
        AnimatedSize(
          duration: AuthMotion.reduceMotion(context) ? Duration.zero : AuthMotion.base,
          curve: AuthMotion.curveInOut,
          alignment: Alignment.topCenter,
          child: (_error == null && _info == null)
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
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
                          icon: Icons.hourglass_top_rounded,
                        ),
                ),
        ),
        const SizedBox(height: 20),
        SweepButton(
          label: 'Get OTP',
          leading: Icons.sms_outlined,
          loading: _isLoading,
          onPressed: _isLoading
              ? null
              : () {
                  AppHaptics.lightImpact();
                  _sendOtp();
                },
        ),
      ],
    );
  }

  Widget _phoneField(AppColors colors) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return TextField(
      key: PhoneScreen.phoneFieldKey,
      controller: _phoneController,
      enabled: !_isLoading,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.go,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [IndianMobileFormatter()],
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) {
        if (!_isLoading) _sendOtp();
      },
      style: TextStyle(fontSize: 17, color: colors.textPrimary, letterSpacing: 0.4),
      decoration: InputDecoration(
        hintText: '10-digit mobile number',
        hintStyle: TextStyle(color: colors.textTertiary, letterSpacing: 0),
        // Fixed, not editable: the backend matches the number exactly as it was
        // registered, which is the bare 10 digits. The chip says which country
        // those digits belong to without changing what is sent.
        prefixIcon: Semantics(
          label: 'Country code plus 91, India',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    '+91',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        filled: true,
        fillColor: colors.surface,
        border: border(colors.border),
        enabledBorder: border(colors.border),
        disabledBorder: border(colors.border),
        focusedBorder: border(AppTheme.accentColor, 2),
        errorBorder: border(colors.danger, 2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }

  Widget _registerPanel(AppColors colors) {
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, size: 20, color: AppTheme.accentColor)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 14, height: 1.4, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        );

    return Column(
      key: const ValueKey('register-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bring your salon to BookALook',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              point(Icons.storefront_outlined, 'Tell us about your salon and where it is.'),
              point(Icons.content_cut_rounded, 'Add your services, prices and staff.'),
              point(Icons.verified_outlined, 'We review it, then customers can book you.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SweepButton(
          label: 'Start registration',
          leading: Icons.arrow_forward_rounded,
          onPressed: _startRegistration,
        ),
      ],
    );
  }

  /// The secondary path, phrased for whichever mode is showing. Both point at
  /// the other segment rather than navigating, so the control and the link can
  /// never disagree about where "Register" goes.
  Widget _switchLink(AppColors colors) {
    final prompt = _isLogin ? 'New partner?' : 'Already a partner?';
    final action = _isLogin ? 'Register your salon' : 'Log in';

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$prompt ', style: TextStyle(color: colors.textSecondary)),
        TextButton(
          onPressed: () => _setMode(!_isLogin),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: Text(action, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

/// Keeps the phone field to the 10 digits the backend expects.
///
/// Strips spaces and dashes, and drops a pasted or autofilled `+91`, `91` or
/// leading `0` so "+91 98765 43210" becomes "9876543210" instead of being
/// truncated to the wrong ten digits.
class IndianMobileFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Fast path: if the new value is entirely digits and within the limit, accept it exactly as is.
    // This perfectly preserves all native cursor movements, deletions, and keyboard composition states.
    if (RegExp(r'^\d{0,10}$').hasMatch(newValue.text)) {
      return newValue;
    }
    
    // Strip non-digits
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Handle pasted prefixes
    if (digits.length > 10) {
      if (digits.startsWith('91')) {
        digits = digits.substring(2);
      } else if (digits.startsWith('0')) {
        digits = digits.substring(1);
      }
    }

    // If still over 10, reject if it was a normal type-in, or just truncate if pasted.
    if (digits.length > 10) {
      if (oldValue.text.length == 10 && (newValue.text.length - oldValue.text.length) == 1) {
        // They tried to type an 11th digit interactively. Reject it.
        return oldValue;
      }
      digits = digits.substring(0, 10);
    }

    // Calculate cursor position
    int cursorOffset = 0;
    if (newValue.selection.end > -1) {
      String textBeforeCursor = newValue.text.substring(0, newValue.selection.end);
      cursorOffset = textBeforeCursor.replaceAll(RegExp(r'\D'), '').length;
      
      // If we stripped a prefix, we should adjust the cursor offset.
      String originalDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
      if (originalDigits.length > 10) {
        if (originalDigits.startsWith('91')) {
          cursorOffset -= 2;
        } else if (originalDigits.startsWith('0')) {
          cursorOffset -= 1;
        }
      }
    }

    if (cursorOffset < 0) cursorOffset = 0;
    if (cursorOffset > digits.length) cursorOffset = digits.length;

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }
}

