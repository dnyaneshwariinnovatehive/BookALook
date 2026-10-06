import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/auth_service.dart';
import 'main_screen.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String? _cachedToken;
  bool _authCheckComplete = false;

  @override
  void initState() {
    super.initState();
    
    // Target duration: 2.4 seconds for a premium paced brand motion
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigate();
      }
    });

    // Start auth check immediately so we don't wait for disk I/O after animation completes
    _preloadAuth();
  }

  void _preloadAuth() async {
    _cachedToken = await AuthService.getToken();
    _authCheckComplete = true;
    
    // In the rare case auth took longer than 2.4s, navigate as soon as it's ready.
    if (_controller.isCompleted) {
      _navigate();
    }
  }

  void _navigate() {
    if (!mounted || !_authCheckComplete) return;

    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MainScreen(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MainScreen(isGuest: true),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Elegant background: Base color from theme, subtle radial glow in the center.
    final baseColor = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: baseColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.85,
            colors: [
              AppTheme.accentColor.withValues(alpha: isDark ? 0.15 : 0.08),
              Colors.transparent,
            ],
            stops: const [0.0, 1.0],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Timeline logic:
              // 0.00 -> 0.18: Logo fades in
              // 0.00 -> 0.30: Logo scales gently
              // 0.20 -> 0.70: Secondary motion draws/morphs
              // 0.70 -> 1.00: Hold & Transition
              
              final logoOpacity = Curves.easeOut.transform((_controller.value / 0.18).clamp(0.0, 1.0));
              final logoScale = 0.95 + 0.05 * Curves.easeOutCubic.transform((_controller.value / 0.30).clamp(0.0, 1.0));
              
              final secondaryProgress = ((_controller.value - 0.20) / 0.50).clamp(0.0, 1.0);
              
              return Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: logoOpacity,
                    child: Transform.scale(
                      scale: logoScale,
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 220,
                        errorBuilder: (context, error, stackTrace) => Text(
                          'BookALook',
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Secondary Animation Area (Subtle beauty/salon motion)
                  SizedBox(
                    width: 70,
                    height: 40,
                    child: CustomPaint(
                      painter: _BrandMotionPainter(
                        progress: secondaryProgress,
                        color: AppTheme.accentColor,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BrandMotionPainter extends CustomPainter {
  final double progress;
  final Color color;

  _BrandMotionPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final w = size.width;
    final h = size.height;

    // Timeline phases within the secondary animation (progress 0.0 to 1.0)
    final lineProgress = Curves.easeInOutCubic.transform((progress / 0.4).clamp(0.0, 1.0));
    final leafProgress = Curves.easeOutBack.transform(((progress - 0.3) / 0.4).clamp(0.0, 1.0));
    final sparkleProgress = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);

    // 1. Flowing beauty line (hair/wellness motif)
    if (lineProgress > 0) {
      final linePaint = Paint()
        ..color = color.withValues(alpha: lineProgress * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      final path = Path();
      path.moveTo(w * 0.2, h * 0.8);
      path.quadraticBezierTo(w * 0.4, h * 0.9, w * 0.6, h * 0.5);
      
      final metric = path.computeMetrics().first;
      final extractPath = metric.extractPath(0.0, metric.length * lineProgress);
      canvas.drawPath(extractPath, linePaint);
    }

    // 2. Leaf/Wellness Symbol
    if (leafProgress > 0) {
      final leafPaint = Paint()
        ..color = color.withValues(alpha: leafProgress.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(w * 0.6, h * 0.5);
      canvas.scale(leafProgress);
      // Subtle rotation to make it feel natural as it grows
      canvas.rotate(-0.2 * (1.0 - leafProgress.clamp(0.0, 1.0)));

      final leaf = Path();
      leaf.moveTo(0, 0);
      leaf.quadraticBezierTo(8, -10, 14, -6);
      leaf.quadraticBezierTo(10, 4, 0, 0);
      
      canvas.drawPath(leaf, leafPaint);
      canvas.restore();
    }

    // 3. Premium Sparkle
    if (sparkleProgress > 0) {
      // Pop effect: scales past 1.0 then settles
      double sparkleScale = 0.0;
      if (sparkleProgress < 0.5) {
        sparkleScale = Curves.easeOut.transform(sparkleProgress / 0.5) * 1.2;
      } else {
        final settleProgress = (sparkleProgress - 0.5) / 0.5;
        sparkleScale = 1.2 - Curves.easeInOut.transform(settleProgress) * 0.3;
      }

      final sparkleAlpha = sparkleProgress < 0.2 
          ? (sparkleProgress / 0.2) 
          : 1.0;

      final sparklePaint = Paint()
        ..color = color.withValues(alpha: sparkleAlpha)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(w * 0.8, h * 0.2); // Positioned elegantly near the leaf tip
      canvas.rotate(sparkleProgress * math.pi / 2); // Gentle continuous rotation
      canvas.scale(sparkleScale);

      final sparkle = Path();
      sparkle.moveTo(0, -7);
      sparkle.quadraticBezierTo(1.5, -1.5, 7, 0);
      sparkle.quadraticBezierTo(1.5, 1.5, 0, 7);
      sparkle.quadraticBezierTo(-1.5, 1.5, -7, 0);
      sparkle.quadraticBezierTo(-1.5, -1.5, 0, -7);
      sparkle.close();

      canvas.drawPath(sparkle, sparklePaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BrandMotionPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
