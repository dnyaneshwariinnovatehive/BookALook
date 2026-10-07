import 'main_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'otp_screen.dart';
import '../utils/app_haptics.dart';
import '../utils/auth_errors.dart';
import '../utils/auth_motion.dart';
import '../widgets/auth/otp_boxes.dart';
import '../theme/app_colors.dart';

class PhoneScreen extends StatefulWidget {
  final bool isModal;
  final int returnIndex;

  /// Keys for the Login / Sign-Up indicator.
  ///
  /// Public so tests can measure where the knob is actually painted rather
  /// than reading AnimatedAlign.alignment, which only reports the destination
  /// and would make a jump look identical to a real slide.
  ///
  /// modeKnobKey sits on the pill itself, not on the AnimatedAlign: an
  /// alignment widget fills its parent, so keying it would measure the rail.
  static const Key modeRailKey = Key('auth-mode-rail');
  static const Key modeKnobKey = Key('auth-mode-knob');

  /// The phone number field and the inline status under it, for tests.
  static const Key phoneFieldKey = Key('auth-phone-field');
  static const Key statusKey = Key('auth-phone-status');

  const PhoneScreen({Key? key, this.isModal = false, this.returnIndex = 0}) : super(key: key);

  @override
  _PhoneScreenState createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phoneController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  /// Inline, under the field, rather than a SnackBar: the keyboard is up while
  /// someone types a number, and a SnackBar would sit behind it or over it.
  String? _error;
  int _shakeToken = 0;

  void _fail(String message) {
    AppHaptics.error();
    setState(() {
      _error = message;
      _shakeToken++;
    });
  }

  void _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      _fail('Please enter a valid phone number (min 10 digits)');
      return;
    }
    if (phone.length > 10) {
      _fail('Please enter a valid 10-digit phone number');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _authService.sendOtp(phone);
    
    if (mounted) setState(() => _isLoading = false);

    if (!mounted) return;

    if (result == 'success') {
      AppHaptics.success();
      final loggedIn = await Navigator.push<bool>(
        context,
        authRoute<bool>(
          builder: (context) => OtpScreen(
            phone: phone,
            isModal: widget.isModal,
            returnIndex: widget.returnIndex,
          ),
        ),
      );
      if (loggedIn == true && widget.isModal && mounted) {
        Navigator.pop(context, true);
      }
    } else {
      // Never the raw result: it can carry a status code and a response body.
      _fail(friendlyAuthError(result));
    }
  }

  bool _isLogin = true;


  /// Sliding Login / Sign-Up control. The indicator sits behind both labels in
  /// a Stack and animates between them, so the switch reads as one piece
  /// moving rather than two colours swapping.
  Widget _modeSwitch(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Track and knob come from the theme tokens so the switch follows the app
    // palette rather than carrying its own hardcoded tints. isDark only tunes
    // the knob's shadow below, which is depth, not colour.
    final track = context.colors.accentSoft;
    final knob = context.colors.segmentKnob;
    final activeText = context.colors.segmentKnobLabel;
    final idleText =
        context.colors.textSecondary;

    Widget tab(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        // Announced as one of a pair with its selected state, so a screen
        // reader says which mode is active instead of two bare labels.
        child: Semantics(
          button: true,
          selected: selected,
          inMutuallyExclusiveGroup: true,
          child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 48,
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: AuthMotion.base,
                curve: AuthMotion.curve,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: selected ? activeText : idleText,
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
      height: 56,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(30),
      ),
      // Sized from the rail itself rather than the window, so the knob still
      // lines up in split-screen and on tablets.
      child: LayoutBuilder(
        builder: (context, rail) {
          return Stack(
            key: PhoneScreen.modeRailKey,
            children: [
              AnimatedAlign(
                duration: AuthMotion.base,
                curve: AuthMotion.curve,
                alignment:
                    _isLogin ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  key: PhoneScreen.modeKnobKey,
                  width: (rail.maxWidth - 8) / 2,
                  height: 48,
                  decoration: BoxDecoration(
                    color: knob,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        // Dark surfaces need a tighter, deeper shadow to read as
                        // a raised pill against an almost-black track.
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: isDark ? 0.22 : 0.10),
                        blurRadius: isDark ? 8 : 12,
                        offset: Offset(0, isDark ? 1 : 3),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  tab('Login', _isLogin, () {
                    AppHaptics.selectionClick();
                    if (!_isLogin) setState(() => _isLogin = true);
                  }),
                  tab('Sign Up', !_isLogin, () {
                    AppHaptics.selectionClick();
                    if (_isLogin) setState(() => _isLogin = false);
                  }),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = context.colors.textSecondary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuthShell(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: StaggeredReveal(
                children: [
                  // Logo Section
                  Column(
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        height: 60,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Premium Grooming & Beauty Discovery',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),

                  _modeSwitch(context),
                  const SizedBox(height: 30),

                  // Phone Number Input
                  Text(
                    'Phone Number',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Shake(
                    token: _shakeToken,
                    child: TextField(
                      key: PhoneScreen.phoneFieldKey,
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.go,
                      autofillHints: const [AutofillHints.telephoneNumberNational],
                      inputFormatters: [IndianMobileFormatter()],
                      style: const TextStyle(fontSize: 16),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: (_) {
                        if (!_isLoading) _sendOtp();
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter your mobile no.',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.dividerColor),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: AuthMotion.base,
                    curve: AuthMotion.curveInOut,
                    alignment: Alignment.topCenter,
                    child: _error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: StatusNote(
                              key: PhoneScreen.statusKey,
                              text: _error!,
                              tone: theme.colorScheme.error,
                              icon: Icons.error_outline_rounded,
                            ),
                          ),
                  ),
                  const SizedBox(height: 22),

                  // Continue Button
                  SweepButton(
                    label: _isLogin ? 'Continue' : 'Create account',
                    leading: Icons.arrow_forward,
                    loading: _isLoading,
                    onPressed: _isLoading
                        ? null
                        : () {
                            AppHaptics.lightImpact();
                            _sendOtp();
                          },
                  ),
                  const SizedBox(height: 20),

                  // Register Link (shown only in Login mode)
                  if (_isLogin)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'New to BookALook? ',
                          style: TextStyle(color: muted),
                        ),
                        GestureDetector(
                          onTap: () {
                            AppHaptics.selectionClick();
                            setState(() => _isLogin = false);
                          },
                          child: Text(
                            'Register',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 28),
                  Divider(color: theme.dividerColor),
                  const SizedBox(height: 18),

                  // Explore as Guest
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        AppHaptics.lightImpact();
                        if (widget.isModal) {
                          Navigator.pop(context, false);
                        } else {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MainScreen(
                                  isGuest: true,
                                  initialIndex: widget.returnIndex),
                            ),
                            (route) => false,
                          );
                        }
                      },
                      icon: Icon(Icons.visibility,
                          color: theme.colorScheme.primary, size: 20),
                      label: Text(
                        'Explore as Guest',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Register Your Salon (Outline Button)
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: Icon(Icons.storefront,
                        color: theme.colorScheme.primary, size: 20),
                    label: Text(
                      'Register Your Salon',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: theme.colorScheme.primary
                            .withValues(alpha: isDark ? 0.65 : 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the phone field to the 10 digits the backend expects.
///
/// Strips spaces, dashes, and other non-digits, and drops a pasted or autofilled
/// `+91`, `91` or leading `0` so "+91 98765 43210" becomes "9876543210" instead
/// of being truncated to the wrong digits. Restricts input to at most 10 digits.
class IndianMobileFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length > 10 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length > 10 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) digits = digits.substring(0, 10);

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
