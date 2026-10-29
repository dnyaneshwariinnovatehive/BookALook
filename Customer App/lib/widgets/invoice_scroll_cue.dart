import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// How far down the invoice page the customer is, as reported by the page.
class InvoiceScrollState {
  /// 0 at the top, 1 at the bottom.
  final double progress;

  /// Whether the page is taller than the screen at all.
  final bool scrollable;

  /// Whether they have scrolled since it opened.
  final bool moved;

  const InvoiceScrollState({
    this.progress = 0,
    this.scrollable = false,
    this.moved = false,
  });

  /// Reads the page's "y,max" message — the scroll offset and the furthest it
  /// can go, both in CSS pixels. Null for anything malformed.
  static InvoiceScrollState? parse(
    String message, {
    bool alreadyMoved = false,
  }) {
    final parts = message.split(',');
    if (parts.length != 2) return null;
    final y = double.tryParse(parts[0]);
    final max = double.tryParse(parts[1]);
    if (y == null || max == null) return null;

    // A few pixels of slack is rounding, not a page worth scrolling.
    final scrollable = max > 24;
    return InvoiceScrollState(
      progress: scrollable ? (y / max).clamp(0.0, 1.0) : 1.0,
      scrollable: scrollable,
      moved: alreadyMoved || y > 40,
    );
  }

  bool get atBottom => progress >= 0.98;
}

/// What tells the customer the invoice goes on below the screen.
///
/// The page is a white sheet whose first screenful looks complete — header,
/// who and when — so nothing suggested the services and totals were further
/// down. Three cues, all gone once they are not needed: a thin bar showing how
/// far through the document they are, a fade at the bottom edge while more is
/// below, and a "Scroll for more" pill until they first scroll (tapping it
/// scrolls for them).
class InvoiceScrollCue extends StatefulWidget {
  final InvoiceScrollState state;
  final VoidCallback onScrollForMe;

  /// Space to keep clear at the bottom (the system navigation bar).
  final double bottomInset;

  const InvoiceScrollCue({
    super.key,
    required this.state,
    required this.onScrollForMe,
    this.bottomInset = 0,
  });

  @override
  State<InvoiceScrollCue> createState() => _InvoiceScrollCueState();
}

class _InvoiceScrollCueState extends State<InvoiceScrollCue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _bob.stop();
    } else if (!_bob.isAnimating) {
      _bob.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (!s.scrollable) return const SizedBox.shrink();

    final showPill = !s.moved && !s.atBottom;
    final showFade = !s.atBottom;
    final bg = context.colors.documentBg;

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Semantics(
            label: 'Invoice ${(s.progress * 100).round()} percent scrolled',
            child: LinearProgressIndicator(
              key: const ValueKey('invoice-scroll-progress'),
              value: s.progress,
              minHeight: 3,
              backgroundColor: Colors.transparent,
              color: AppTheme.accentColor,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: widget.bottomInset,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: showFade ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                key: const ValueKey('invoice-scroll-fade'),
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      bg.withValues(alpha: 0),
                      bg.withValues(alpha: 0.95),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: widget.bottomInset + 14,
          child: IgnorePointer(
            ignoring: !showPill,
            child: AnimatedOpacity(
              opacity: showPill ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: AnimatedBuilder(
                    animation: _bob,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        0,
                        4 * Curves.easeInOut.transform(_bob.value),
                      ),
                      child: child,
                    ),
                    child: Material(
                      color: AppTheme.accentColor,
                      elevation: 4,
                      shadowColor: Colors.black26,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        key: const ValueKey('invoice-scroll-hint'),
                        customBorder: const StadiumBorder(),
                        onTap: widget.onScrollForMe,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Scroll for services & total',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.keyboard_double_arrow_down_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
