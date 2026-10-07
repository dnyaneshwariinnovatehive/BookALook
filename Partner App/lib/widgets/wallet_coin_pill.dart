import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

import '../screens/dashboard/more/wallet_screen.dart';
import '../services/wallet_balance.dart';
import '../theme/app_theme.dart';

/// The coin balance, as a tappable pill for a screen header.
///
/// Gold rather than the app's purple, because a balance has to read as money
/// at a glance and every app that carries one — rewards, games, wallets — uses
/// the same colour for it. Against a mostly-purple app it also separates
/// cleanly from the navigation around it.
///
/// Deliberately quiet until there is something to say: with no reading yet it
/// occupies no space at all, so a header never jumps as the balance arrives.
class WalletCoinPill extends StatelessWidget {
  final String salonId;

  /// Compact drops the word "coins" for headers that are already crowded.
  final bool compact;

  const WalletCoinPill({super.key, required this.salonId, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<WalletSnapshot?>(
      valueListenable: WalletBalance.snapshot,
      builder: (context, snapshot, _) {
        if (snapshot == null) return const SizedBox.shrink();

        final foreground = dark ? AppTheme.darkWarning : const Color(0xFFB26A00);
        final background = dark ? AppTheme.darkWarningBg : const Color(0xFFFFF4DA);

        return Semantics(
          button: true,
          label: '${snapshot.coins} reward coins, worth '
              '₹${snapshot.valueInr.toStringAsFixed(0)}. Opens your wallet.',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => WalletScreen(salonId: salonId)),
                );
                // Coins can be spent in there, so the number is re-read rather
                // than left showing what it was before.
                await WalletBalance.refresh(salonId);
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 9 : 11, vertical: compact ? 5 : 6),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: foreground.withValues(alpha: 0.22)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A filled circle reads as a coin at 15px where a detailed
                    // icon just reads as noise.
                    // The AnimatedCoinIcon handles a continuous premium 3D rotation
                    _AnimatedCoinIcon(compact: compact),
                    SizedBox(width: compact ? 5 : 6),
                    Text(snapshot.formatted,
                        style: GoogleFonts.outfit(
                            fontSize: compact ? 13 : 14,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            color: foreground)),
                    if (!compact) ...[
                      const SizedBox(width: 3),
                      Text('coins',
                          style: GoogleFonts.outfit(
                              fontSize: 11,
                              height: 1,
                              fontWeight: FontWeight.w500,
                              color: foreground.withValues(alpha: 0.75))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedCoinIcon extends StatefulWidget {
  final bool compact;
  const _AnimatedCoinIcon({required this.compact});

  @override
  State<_AnimatedCoinIcon> createState() => _AnimatedCoinIconState();
}

class _AnimatedCoinIconState extends State<_AnimatedCoinIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    // The rotation loops seamlessly. 
    // We add a subtle easing curve so it holds slightly on the front faces 
    // and turns smoothly.
    _rotationAnimation = Tween<double>(begin: 0.0, end: math.pi * 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rotationAnimation,
      builder: (context, child) {
        final angle = _rotationAnimation.value;
        final cosAngle = math.cos(angle);
        
        final isFront = cosAngle >= 0;
        final absCos = cosAngle.abs();
        
        // Darken the coin dynamically as it turns away (giving 3D depth lighting)
        final brightness = 0.75 + (absCos * 0.25);
        final shadowColor = const Color(0xFF8B5A00); // Deep gold shadow
        
        final color1 = Color.lerp(shadowColor, const Color(0xFFFFC94D), brightness)!;
        final color2 = Color.lerp(shadowColor, const Color(0xFFF59E0B), brightness)!;
        
        // Add a subtle bright edge reflection when nearly edge-on
        final edgeHighlight = absCos < 0.15 ? 1.0 - (absCos / 0.15) : 0.0;
        final finalColor1 = Color.lerp(color1, Colors.white, edgeHighlight * 0.4)!;
        final finalColor2 = Color.lerp(color2, Colors.white, edgeHighlight * 0.4)!;

        // Apply a realistic 3D perspective rotation around the Y axis
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.002) // Perspective depth
          ..rotateY(angle);

        return Transform(
          transform: transform,
          alignment: Alignment.center,
          child: Container(
            width: widget.compact ? 15 : 17,
            height: widget.compact ? 15 : 17,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [finalColor1, finalColor2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            // Keep the '₹' readable by un-flipping it when on the back face.
            // If we didn't un-flip, the back face would show a mirrored '₹'.
            child: isFront 
              ? _buildText()
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _buildText(),
                ),
          ),
        );
      },
    );
  }

  Widget _buildText() {
    return Text(
      '₹',
      style: GoogleFonts.outfit(
        fontSize: widget.compact ? 8.5 : 9.5,
        height: 1,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    );
  }
}
