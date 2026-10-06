import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/salon_access_api.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/auth_motion.dart';
import '../../widgets/auth/otp_boxes.dart';

class WelcomeSuccessScreen extends StatefulWidget {
  final SalonAccess access;
  final VoidCallback onContinue;

  const WelcomeSuccessScreen({
    super.key,
    required this.access,
    required this.onContinue,
  });

  @override
  State<WelcomeSuccessScreen> createState() => _WelcomeSuccessScreenState();
}

class _WelcomeSuccessScreenState extends State<WelcomeSuccessScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      body: Stack(
        children: [
          const AmbientBackdrop(intensity: 0.22), // 0.1s glow
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(flex: 2),
                        StaggeredReveal(
                          duration: const Duration(milliseconds: 1000), // Slower premium reveal
                          startDelay: 0.15, // Wait for ambient
                          step: 0.15,
                          children: [
                            const Center(
                              child: _PurpleSuccessIcon(
                                child: SuccessTick(size: 72),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              'Salon Unlocked!',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Welcome to BookALook',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.lightTextHeading,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${widget.access.salonName} has been approved and is now officially part of the BookALook network.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                color: AppTheme.lightTextBody,
                                height: 1.5,
                              ),
                            ),
                            if (widget.access.walletCoins > 0) ...[
                              const SizedBox(height: 48),
                              _RewardParticles(
                                delay: const Duration(milliseconds: 1000),
                                child: _buildRewardCard(),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Your welcome credits have been added to your wallet.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  color: AppTheme.lightTextBody,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Spacer(flex: 3),
                        StaggeredReveal(
                          startDelay: 0.9, // Shows up later
                          children: [
                            SweepButton(
                              label: 'Continue',
                              onPressed: widget.onContinue,
                              loading: false,
                              height: 56,
                              textSize: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: AppTheme.accentColor.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.stars_rounded,
                color: AppTheme.starRating,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'WELCOME CREDIT',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppTheme.lightTextBody,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _AnimatedCoinCounter(
            targetValue: widget.access.walletCoins,
            delay: const Duration(milliseconds: 900),
          ),
          const SizedBox(height: 6),
          Text(
            'BOOKALOOK COINS',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppTheme.accentColor,
            ),
          ),
          if (widget.access.walletValueInr > 0) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.lightAccentSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Worth ₹${widget.access.walletValueInr.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A wrapper to recolor the success tick to BookALook purple.
class _PurpleSuccessIcon extends StatelessWidget {
  final Widget child;
  const _PurpleSuccessIcon({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // We override the success color so the internal tick renders purple.
    final overrideColors = AppColors(
      surface: colors.surface,
      surfaceMuted: colors.surfaceMuted,
      accentSoft: colors.accentSoft,
      border: colors.border,
      textPrimary: colors.textPrimary,
      textSecondary: colors.textSecondary,
      textTertiary: colors.textTertiary,
      onAccent: colors.onAccent,
      success: AppTheme.accentColor, // Override to purple
      successBg: AppTheme.lightAccentSoft,
      warning: colors.warning,
      warningBg: colors.warningBg,
      danger: colors.danger,
      dangerBg: colors.dangerBg,
      info: colors.info,
      infoBg: colors.infoBg,
      notesBg: colors.notesBg,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.lightAccentSoft,
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withValues(alpha: 0.15),
            blurRadius: 32,
            spreadRadius: 8,
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          extensions: [overrideColors],
        ),
        child: child,
      ),
    );
  }
}

/// A subtle counting animation for the reward amount.
class _AnimatedCoinCounter extends StatefulWidget {
  final int targetValue;
  final Duration delay;

  const _AnimatedCoinCounter({required this.targetValue, required this.delay});

  @override
  State<_AnimatedCoinCounter> createState() => _AnimatedCoinCounterState();
}

class _AnimatedCoinCounterState extends State<_AnimatedCoinCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<int> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _animation = IntTween(begin: 0, end: widget.targetValue).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AuthMotion.reduceMotion(context)) {
      return _buildText(widget.targetValue);
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return _buildText(_animation.value);
      },
    );
  }

  Widget _buildText(int value) {
    return Text(
      '+$value',
      style: GoogleFonts.outfit(
        fontSize: 54,
        fontWeight: FontWeight.bold,
        color: AppTheme.accentColor,
        height: 1,
      ),
    );
  }
}

/// Draws elegant, slow-moving particles around the reward card.
class _RewardParticles extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _RewardParticles({required this.child, required this.delay});

  @override
  State<_RewardParticles> createState() => _RewardParticlesState();
}

class _RewardParticlesState extends State<_RewardParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500));
    Future.delayed(widget.delay, () {
      if (mounted && !AuthMotion.reduceMotion(context)) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AuthMotion.reduceMotion(context)) {
      return widget.child;
    }
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ParticlePainter(_controller.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double progress;
  _ParticlePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0 || progress == 1) return;

    // Use a custom easing for the opacity so it fades out gracefully.
    final opacity = progress < 0.2
        ? progress / 0.2
        : (progress > 0.8 ? (1 - progress) / 0.2 : 1.0);

    final paint = Paint()
      ..color = AppTheme.accentColor.withValues(alpha: opacity * 0.4)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    // Radiate outwards from the center.
    final radius = (size.width * 0.4) + (size.width * 0.3 * Curves.easeOutCubic.transform(progress));

    // 8 elegant dots
    for (int i = 0; i < 8; i++) {
      final angle = i * (math.pi * 2 / 8) + (progress * 0.5); // Slight rotation
      final offset = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      // Shrink slightly as they move out
      final dotRadius = 4.0 * (1 - (progress * 0.5));
      canvas.drawCircle(offset, dotRadius, paint);
    }
    
    // Add 4 smaller inner dots moving in opposite direction
    final innerPaint = Paint()
      ..color = AppTheme.starRating.withValues(alpha: opacity * 0.6)
      ..style = PaintingStyle.fill;
      
    final innerRadius = (size.width * 0.3) + (size.width * 0.2 * Curves.easeOutCubic.transform(progress));
    
    for (int i = 0; i < 4; i++) {
      final angle = i * (math.pi * 2 / 4) - (progress * 0.8) + (math.pi / 4);
      final offset = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle),
      );
      canvas.drawCircle(offset, 2.5, innerPaint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) => oldDelegate.progress != progress;
}
