import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../utils/auth_motion.dart';
import '../../theme/app_colors.dart';

/// OTP entry drawn as six boxes, driven by a single real [TextField].
///
/// Six independent fields would break paste, SMS autofill and backspace, so the
/// text field stays the only editable widget and the boxes are pure visuals fed
/// by [controller].
class OtpBoxes extends StatefulWidget {
  const OtpBoxes({
    super.key,
    required this.controller,
    this.length = 6,
    this.autofocus = true,
    this.hasError = false,
    this.shakeToken = 0,
    this.onCompleted,
    this.onChanged,
  });

  final TextEditingController controller;
  final int length;
  final bool autofocus;
  final bool hasError;
  final int shakeToken;
  final VoidCallback? onCompleted;
  final ValueChanged<String>? onChanged;

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
  )..repeat(reverse: true);

  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  final FocusNode _focus = FocusNode();
  int _lastFilled = 0;
  bool _justCompleted = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    if (widget.autofocus) {
      // Requested after the first frame so the field can take focus while the
      // entrance animation is still running.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
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
    _focus.dispose();
    _pop.dispose();
    _caret.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  void _onText() {
    final text = widget.controller.text;
    final filled = text.characters.length;

    // Pop the newest box whenever the count grows, and tick once per digit.
    if (filled > _lastFilled) {
      _pop.forward(from: 0);
      HapticFeedback.selectionClick();
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final error = theme.colorScheme.error;
    final borderIdle =
        context.colors.border;
    final label =
        context.colors.textPrimary;
    final surface = theme.colorScheme.surface;

    final text = widget.controller.text;
    final filled = text.characters.length;
    final caretAt = filled < widget.length ? filled : widget.length - 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final boxW =
            (constraints.maxWidth - gap * (widget.length - 1)) / widget.length;

        return Stack(
          children: [
            // The editable field sits on top, invisible, so tapping anywhere in
            // the row opens the keyboard and native autofill still applies.
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
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
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(widget.length, (i) {
                final hasDigit = i < filled;
                final isActive = i == caretAt && _focus.hasFocus;
                final isLastFilled = i == filled - 1;

                return AnimatedBuilder(
                  animation: Listenable.merge([
                    _pop,
                    _caret,
                    _shimmer,
                  ]),
                  builder: (context, child) {
                    // Only the newest box reacts to the pop, and the pop is
                    // rewound each keystroke so a fast typist still sees it.
                    final scale = isLastFilled
                        ? 1 + 0.10 * _popCurve.value
                        : 1.0;

                    final borderColor = widget.hasError
                        ? error
                        : hasDigit
                            ? accent.withValues(alpha: isDark ? 0.65 : 0.55)
                            : isActive
                                ? accent
                                : borderIdle;

                    return Transform.scale(
                      scale: scale,
                      child: GestureDetector(
                        onTap: () => _focus.requestFocus(),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: boxW,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hasDigit
                                ? (context.colors.accentSoft)
                                : surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: borderColor,
                              width: isActive || widget.hasError ? 2 : 1.4,
                            ),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: accent.withValues(
                                          alpha: isDark ? 0.26 : 0.18),
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
                              if (!hasDigit && isActive)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Opacity(
                                    opacity: 0.5,
                                    child: AnimatedBuilder(
                                      animation: _shimmer,
                                      builder: (context, _) => Container(
                                        width: 42,
                                        height: 58,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment(
                                                -1.6 + 3.2 * _shimmer.value, 0),
                                            end: Alignment(
                                                -0.9 + 3.2 * _shimmer.value, 0),
                                            colors: [
                                              Colors.transparent,
                                              accent.withValues(
                                                  alpha: isDark ? 0.24 : 0.16),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Text(
                                hasDigit ? text.characters.elementAt(i) : '',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                    color: hasDigit ? label : Colors.transparent,
                                ),
                              ),
                              // Caret stands in for the hidden field's cursor.
                              if (!hasDigit && isActive)
                                AnimatedBuilder(
                                  animation: _caret,
                                  builder: (context, _) => Opacity(
                                    opacity: _caret.value,
                                    child: Container(
                                      width: 2,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        borderRadius:
                                            BorderRadius.circular(2),
                                      ),
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
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Semantic success, not the accent: the tick means "verified", and a purple
    // ring would read as another step rather than a confirmed state.
    final success = context.colors.success;
    return ScaleTransition(
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
          child: Icon(
            Icons.check_rounded,
            size: widget.size * 0.55,
            // Dark mode's success green is light enough that white on top of it
            // loses contrast; onSuccess picks the readable one per theme.
            color: context.colors.onSuccess,
          ),
        ),
      ),
    );
  }
}

/// Inline message row that replaces the SnackBar for OTP errors, so nothing
/// covers the keyboard or the boxes the user is looking at.
class StatusNote extends StatelessWidget {
  const StatusNote({
    super.key,
    required this.text,
    required this.tone,
    this.icon,
  });

  final String text;
  final Color tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 6 * (1 - v)), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          // Dark needs a stronger wash: 0.08 of a pastel tone over a near-black
          // surface is invisible.
          color: tone.withValues(alpha: isDark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: tone.withValues(alpha: isDark ? 0.40 : 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: tone),
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
      ),
    );
  }
}

/// "Resend in 0:24" while [seconds] counts down, then a live "Resend OTP".
///
/// The countdown is plain text, so there is nothing to tap until it ends. This
/// used to render its own TextButton with an empty onPressed inside the
/// screen's TextButton: the inner one won every tap and did nothing, and the
/// outer one was live during the countdown, so resend was both broken and
/// unlocked. Pass a null [onResend] to keep it disabled, e.g. while a request
/// is in flight.
class ResendCountdown extends StatelessWidget {
  const ResendCountdown({super.key, this.seconds, this.onResend});

  final int? seconds;
  final VoidCallback? onResend;

  /// Key on the resend action, for tests.
  static const Key actionKey = ValueKey('resend');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = seconds;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: s == null
          ? TextButton(
              key: actionKey,
              onPressed: onResend,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                'Resend OTP',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : Text(
              'Resend in 0:${s.toString().padLeft(2, '0')}',
              key: ValueKey(s),
              style: TextStyle(
                color: context.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// Shared entrance used by the two auth screens: the drifting backdrop behind
/// whatever the screen wants to put on top.
///
/// Paints an opaque themed base before the washes. Without it the auth routes
/// are see-through, which lets the previous screen's text ghost underneath the
/// incoming screen for the length of the transition.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.child,
    this.accent,
  });

  final Widget child;

  /// Wash tint. Null resolves to the theme's primary.
  final Color? accent;

  @override
  Widget build(BuildContext context) {

    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: context.colors.surfaceMuted,
          ),
        ),
        Positioned.fill(child: AmbientBackdrop(color: accent)),
        child,
      ],
    );
  }
}
