import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_haptics.dart';
import '../../utils/auth_motion.dart';

/// OTP entry drawn as six boxes, driven by a single real [TextField].
///
/// Six independent fields would break paste, SMS autofill and backspace, so the
/// text field stays the only editable widget and the boxes are pure visuals fed
/// by [controller].
///
/// For screen readers it is the other way round: the boxes are hidden from the
/// semantics tree and the real field is what gets announced, so the code is
/// read once as "one-time code", not as six unlabelled digits.
class OtpBoxes extends StatefulWidget {
  const OtpBoxes({
    super.key,
    required this.controller,
    this.length = 6,
    this.autofocus = true,
    this.hasError = false,
    this.enabled = true,
    this.onCompleted,
    this.onChanged,
  });

  final TextEditingController controller;
  final int length;
  final bool autofocus;
  final bool hasError;

  /// False while a verify is in flight, so the code cannot change under it.
  final bool enabled;
  final VoidCallback? onCompleted;
  final ValueChanged<String>? onChanged;

  /// Key on the one real, editable field. Tests type and paste through it.
  static const Key fieldKey = Key('otp-boxes-field');

  @override
  State<OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<OtpBoxes> with TickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _popCurve = CurvedAnimation(
    parent: _pop,
    curve: Curves.easeOutBack,
  );

  late final AnimationController _caret = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  final FocusNode _focus = FocusNode();
  int _lastFilled = 0;
  bool _justCompleted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _focus.addListener(_onFocus);
    _lastFilled = widget.controller.text.characters.length;
    if (widget.autofocus) {
      // Requested after the first frame so the field can take focus while the
      // entrance animation is still running.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled) _focus.requestFocus();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AuthMotion.reduceMotion(context);
    // A blinking caret and a moving shimmer are decoration. Under reduced
    // motion the caret stays solid and the shimmer is not drawn.
    if (_reduceMotion) {
      _caret
        ..stop()
        ..value = 1;
      _shimmer.stop();
    } else {
      if (!_caret.isAnimating) _caret.repeat(reverse: true);
      if (!_shimmer.isAnimating) _shimmer.repeat();
    }
  }

  @override
  void didUpdateWidget(OtpBoxes old) {
    super.didUpdateWidget(old);
    if (widget.controller != old.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _pop.dispose();
    _caret.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  void _onFocus() {
    // The active box is drawn from focus, so gaining or losing it has to
    // repaint the row.
    if (mounted) setState(() {});
  }

  void _onText() {
    final text = widget.controller.text;
    final filled = text.characters.length;

    // Pop the newest box whenever the count grows, and tick once per digit.
    if (filled > _lastFilled) {
      if (!_reduceMotion) _pop.forward(from: 0);
      AppHaptics.selectionClick();
    }
    _lastFilled = filled;

    // The boxes are painted from the controller's text, so the listener has to
    // request a rebuild or typing would never move a digit.
    if (mounted) setState(() {});
    widget.onChanged?.call(text);

    final complete = filled == widget.length;
    if (complete && !_justCompleted) {
      _justCompleted = true;
      widget.onCompleted?.call();
    } else if (!complete) {
      _justCompleted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const accent = AppTheme.accentColor;
    final error = colors.danger;

    final text = widget.controller.text;
    final filled = text.characters.length;
    final caretAt = filled < widget.length ? filled : widget.length - 1;

    // The boxes are a fixed-size grid, so the digit inside one is capped
    // rather than allowed to overflow it at very large text sizes. The real
    // field still carries the full value for screen readers and magnifiers.
    final digitScaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final boxW =
            (constraints.maxWidth - gap * (widget.length - 1)) / widget.length;

        return Stack(
          children: [
            // The editable field sits on top, invisible, so tapping anywhere in
            // the row opens the keyboard and native autofill still applies.
            // alwaysIncludeSemantics keeps it in the semantics tree: a plain
            // zero-opacity Opacity would drop the only real input from
            // TalkBack and VoiceOver entirely.
            Positioned.fill(
              child: Semantics(
                label: 'One-time code, ${widget.length} digits',
                child: Opacity(
                  opacity: 0,
                  alwaysIncludeSemantics: true,
                  child: TextField(
                    key: OtpBoxes.fieldKey,
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: false,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: widget.length,
                    // Lets the platform offer the SMS one-time code above the
                    // keyboard, which is the whole point of keeping one real
                    // field behind the visual boxes.
                    autofillHints: const [AutofillHints.oneTimeCode],
                    enableSuggestions: false,
                    autocorrect: false,
                    // No selection handles or caret: the boxes draw their own,
                    // and the field itself is invisible. Paste and backspace
                    // still work because they go through the input formatter.
                    enableInteractiveSelection: false,
                    showCursor: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(widget.length),
                    ],
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(widget.length, (i) {
                  final hasDigit = i < filled;
                  final isActive = i == caretAt && _focus.hasFocus;
                  final isLastFilled = i == filled - 1;

                  return AnimatedBuilder(
                    animation: Listenable.merge([_pop, _caret, _shimmer]),
                    builder: (context, child) {
                      // Only the newest box reacts to the pop, and the pop is
                      // rewound each keystroke so a fast typist still sees it.
                      final scale =
                          isLastFilled ? 1 + 0.10 * _popCurve.value : 1.0;

                      final borderColor = widget.hasError
                          ? error
                          : hasDigit
                              ? accent.withValues(alpha: 0.6)
                              : isActive
                                  ? accent
                                  : colors.border;

                      return Transform.scale(
                        scale: scale,
                        child: GestureDetector(
                          onTap: widget.enabled ? _focus.requestFocus : null,
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedContainer(
                            duration: AuthMotion.fast,
                            width: boxW,
                            height: 58,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: hasDigit ? colors.accentSoft : colors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: borderColor,
                                width: isActive || widget.hasError ? 2 : 1.4,
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.22),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Shimmer sweeps only the box awaiting input.
                                if (!hasDigit && isActive && !_reduceMotion)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Opacity(
                                      opacity: 0.5,
                                      child: Container(
                                        width: 42,
                                        height: 58,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment(
                                                -1.6 + 3.2 * _shimmer.value, 0),
                                            end: Alignment(
                                                -0.9 + 3.2 * _shimmer.value, 0),
                                            colors: [
                                              accent.withValues(alpha: 0),
                                              accent.withValues(alpha: 0.2),
                                              accent.withValues(alpha: 0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Text(
                                  hasDigit ? text.characters.elementAt(i) : '',
                                  textScaler: digitScaler,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                // Caret stands in for the hidden field's cursor.
                                if (!hasDigit && isActive)
                                  Opacity(
                                    opacity: _caret.value,
                                    child: Container(
                                      width: 2,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Tick that springs in on a verified code.
class SuccessTick extends StatefulWidget {
  const SuccessTick({super.key, this.size = 84});

  final double size;

  @override
  State<SuccessTick> createState() => _SuccessTickState();
}

class _SuccessTickState extends State<SuccessTick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 620));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Arrives fully formed under reduced motion; it springs in otherwise.
    if (AuthMotion.reduceMotion(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Semantic success, not the accent: the tick means "verified", and a purple
    // ring would read as another step rather than a confirmed state.
    final success = colors.success;
    return Semantics(
      label: 'Verified',
      image: true,
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
        child: FadeTransition(
          opacity: CurvedAnimation(
              parent: _c, curve: const Interval(0, 0.4, curve: Curves.easeOut)),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  success,
                  Color.lerp(success, Colors.black, 0.18)!,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: success.withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            // The surface colour contrasts with both themes' success tone: white
            // on the deep light-mode green, near-black on the pale dark-mode one.
            child: Icon(
              Icons.check_rounded,
              size: widget.size * 0.55,
              color: colors.surface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline message row that replaces the SnackBar for auth errors, so nothing
/// covers the keyboard or the boxes the user is looking at.
///
/// A live region, so a screen reader announces the message when it appears
/// rather than leaving the user to discover it.
class StatusNote extends StatelessWidget {
  const StatusNote({
    super.key,
    required this.text,
    required this.tone,
    this.background,
    this.icon,
  });

  final String text;

  /// Text, icon and border colour, e.g. [AppColors.danger].
  final Color tone;

  /// Fill, e.g. [AppColors.dangerBg]. Defaults to a wash of [tone].
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final note = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background ?? tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            ExcludeSemantics(child: Icon(icon, size: 18, color: tone)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: tone,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );

    final announced = Semantics(liveRegion: true, child: note);

    if (AuthMotion.reduceMotion(context)) return announced;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AuthMotion.base,
      curve: AuthMotion.curve,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 6 * (1 - v)), child: child),
      ),
      child: announced,
    );
  }
}

/// "Resend in 0:24" while [seconds] counts down, then a live "Resend OTP".
///
/// The countdown is plain text, not a disabled button, and the action only
/// exists once it ends — so resending genuinely cannot happen early. Pass a
/// null [onResend] to keep it disabled after the countdown too, e.g. while a
/// request is already in flight.
class ResendCountdown extends StatelessWidget {
  const ResendCountdown({super.key, this.seconds, this.onResend});

  final int? seconds;
  final VoidCallback? onResend;

  /// Key on the resend action, for tests.
  static const Key actionKey = Key('otp-resend-action');

  @override
  Widget build(BuildContext context) {
    final s = seconds;
    return AnimatedSwitcher(
      duration: AuthMotion.reduceMotion(context) ? Duration.zero : AuthMotion.base,
      child: s == null
          ? TextButton(
              key: actionKey,
              onPressed: onResend,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(
                'Resend OTP',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : ConstrainedBox(
              key: const ValueKey('countdown'),
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Resend in 0:${s.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Shared base for the auth screens: an opaque themed fill with the drifting
/// backdrop over it, and the screen's content on top.
///
/// The opaque fill is what makes the auth routes non-see-through. Without it
/// the previous screen's text ghosts underneath the incoming one for the length
/// of the transition.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.child,
    this.accent,
  });

  final Widget child;

  /// Wash tint. Null means the brand accent.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: context.colors.surfaceMuted),
        ),
        Positioned.fill(child: AmbientBackdrop(color: accent)),
        child,
      ],
    );
  }
}
