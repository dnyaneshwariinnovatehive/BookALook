import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'phone_screen.dart';
import 'dashboard/salon_selection_screen.dart';
import 'dashboard/service_provider_dashboard.dart';
import 'dashboard/collaborator_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String? _cachedToken;
  String? _cachedAuthStateStr;
  bool _authCheckComplete = false;

  @override
  void initState() {
    super.initState();
    
    // Target duration: 2.6 seconds for a premium paced brand motion
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigate();
      }
    });

    _preloadAuth();
  }

  void _preloadAuth() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString('auth_token');
    _cachedAuthStateStr = prefs.getString('auth_state');
    _authCheckComplete = true;
    
    if (_controller.isCompleted) {
      _navigate();
    }
  }

  void _navigate() {
    if (!mounted || !_authCheckComplete) return;

    if (_cachedToken != null && _cachedToken!.isNotEmpty && _cachedAuthStateStr != null) {
      final response = jsonDecode(_cachedAuthStateStr!);
      if (response['role'] == 'admin') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => SalonSelectionScreen(salons: response['salons'] ?? []),
            transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      } else if (response['role'] == 'service_provider') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => ServiceProviderDashboard(
              salon: response['salon'] ?? {},
              provider: response['provider'] ?? {},
              user: response['user'] ?? {},
            ),
            transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      } else if (response['role'] == 'collaborator') {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const CollaboratorDashboardScreen(),
            transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const PhoneScreen(),
            transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const PhoneScreen(),
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

  Widget _buildOrbitingElement({
    required CustomPainter painter,
    required double delay,
    required Offset startOffset,
    required Offset endOffset,
    required double startRot,
    required double endRot,
    required double t,
  }) {
    final progress = ((t - delay) / 0.40).clamp(0.0, 1.0);
    final opacity = Curves.easeOut.transform(((t - delay) / 0.20).clamp(0.0, 1.0));
    
    // Custom curved paths for organic entry
    final curveX = Curves.easeOutCubic.transform(progress);
    final curveY = Curves.easeOutSine.transform(progress);
    
    final x = startOffset.dx + (endOffset.dx - startOffset.dx) * curveX;
    final y = startOffset.dy + (endOffset.dy - startOffset.dy) * curveY;
    final rot = startRot + (endRot - startRot) * curveX;
    
    // Floating after settled
    final postProgress = ((t - delay - 0.40) / (1.0 - delay - 0.40)).clamp(0.0, 1.0);
    final floatY = math.sin(postProgress * math.pi * 2) * 4;
    final breatheScale = 1.0 + math.sin(postProgress * math.pi * 2) * 0.03;
    
    return Transform.translate(
      offset: Offset(x, y + floatY),
      child: Transform.rotate(
        angle: rot,
        child: Transform.scale(
          scale: breatheScale,
          child: Opacity(
            opacity: opacity,
            child: SizedBox(
              width: 72,
              height: 72,
              child: CustomPaint(painter: painter),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Elegant background: Base color from theme, subtle radial glow in the center.
    final baseColor = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.accentColor;
    final elementColor = isDark ? Colors.white.withValues(alpha: 0.85) : accentColor.withValues(alpha: 0.85);
    
    return Scaffold(
      backgroundColor: baseColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.85,
            colors: [
              accentColor.withValues(alpha: isDark ? 0.15 : 0.08),
              Colors.transparent,
            ],
            stops: const [0.0, 1.0],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              final logoOpacity = Curves.easeOut.transform((t / 0.18).clamp(0.0, 1.0));
              final logoScale = 0.90 + 0.10 * Curves.easeOutCubic.transform((t / 0.30).clamp(0.0, 1.0));
              
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Light Trails behind elements
                  Positioned.fill(
                    child: CustomPaint(
                      painter: TrailPainter(t, elementColor),
                    ),
                  ),

                  // Elements entering from different directions
                  _buildOrbitingElement(
                    painter: ScissorsPainter(elementColor),
                    delay: 0.15,
                    startOffset: const Offset(-150, -150),
                    endOffset: const Offset(-110, -80),
                    startRot: -math.pi / 2,
                    endRot: -math.pi / 8,
                    t: t,
                  ),

                  _buildOrbitingElement(
                    painter: HairDryerPainter(elementColor),
                    delay: 0.25,
                    startOffset: const Offset(150, -120),
                    endOffset: const Offset(110, -70),
                    startRot: math.pi / 2,
                    endRot: math.pi / 6,
                    t: t,
                  ),

                  _buildOrbitingElement(
                    painter: CombPainter(elementColor),
                    delay: 0.35,
                    startOffset: const Offset(-150, 150),
                    endOffset: const Offset(-105, 80),
                    startRot: -math.pi / 4,
                    endRot: math.pi / 8,
                    t: t,
                  ),

                  _buildOrbitingElement(
                    painter: HandMirrorPainter(elementColor),
                    delay: 0.45,
                    startOffset: const Offset(150, 150),
                    endOffset: const Offset(105, 75),
                    startRot: math.pi / 4,
                    endRot: -math.pi / 10,
                    t: t,
                  ),

                  // Sparkles
                  Positioned.fill(
                    child: CustomPaint(
                      painter: SparklePainter(
                        ((t - 0.75) / 0.20).clamp(0.0, 1.0),
                        elementColor,
                      ),
                    ),
                  ),

                  // Logo (Hero)
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// CUSTOM PAINTERS FOR BEAUTY ELEMENTS (Premium Line-Art)
// ---------------------------------------------------------

class ScissorsPainter extends CustomPainter {
  final Color color;
  ScissorsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
      
    final w = size.width;
    final h = size.height;
    
    final cx = w * 0.5;
    final cy = h * 0.5;
    
    // Blade 1
    canvas.drawLine(Offset(cx, cy), Offset(w * 0.2, h * 0.1), paint);
    // Handle 1 (loop)
    canvas.drawCircle(Offset(w * 0.75, h * 0.8), w * 0.12, paint);
    // Connect blade 1 to handle 1
    canvas.drawLine(Offset(cx, cy), Offset(w * 0.65, h * 0.7), paint);
    
    // Blade 2
    canvas.drawLine(Offset(cx, cy), Offset(w * 0.8, h * 0.1), paint);
    // Handle 2
    canvas.drawCircle(Offset(w * 0.25, h * 0.8), w * 0.12, paint);
    // Connect blade 2 to handle 2
    canvas.drawLine(Offset(cx, cy), Offset(w * 0.35, h * 0.7), paint);
    
    // Pivot screw
    canvas.drawCircle(Offset(cx, cy), 1.5, Paint()..color=color..style=PaintingStyle.fill);
  }
  @override
  bool shouldRepaint(covariant ScissorsPainter oldDelegate) => oldDelegate.color != color;
}

class HairDryerPainter extends CustomPainter {
  final Color color;
  HairDryerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
      
    final w = size.width;
    final h = size.height;
    
    // Body of dryer
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.2, h * 0.3, w * 0.75, h * 0.55), const Radius.circular(8)), paint);
    
    // Nozzle
    canvas.drawLine(Offset(w * 0.75, h * 0.35), Offset(w * 0.95, h * 0.38), paint);
    canvas.drawLine(Offset(w * 0.75, h * 0.5), Offset(w * 0.95, h * 0.47), paint);
    canvas.drawLine(Offset(w * 0.95, h * 0.38), Offset(w * 0.95, h * 0.47), paint);

    // Handle
    canvas.drawLine(Offset(w * 0.45, h * 0.55), Offset(w * 0.35, h * 0.85), paint);
    canvas.drawLine(Offset(w * 0.6, h * 0.55), Offset(w * 0.5, h * 0.85), paint);
    canvas.drawLine(Offset(w * 0.35, h * 0.85), Offset(w * 0.5, h * 0.85), paint);
    
    // Cord
    final cordPath = Path()
      ..moveTo(w * 0.42, h * 0.85)
      ..quadraticBezierTo(w * 0.35, h * 0.92, w * 0.45, h * 0.98);
    canvas.drawPath(cordPath, paint..strokeWidth = 1.0);
    
    // Details
    canvas.drawLine(Offset(w * 0.35, h * 0.3), Offset(w * 0.35, h * 0.55), paint..strokeWidth = 1.0);
  }
  @override
  bool shouldRepaint(covariant HairDryerPainter oldDelegate) => oldDelegate.color != color;
}

class CombPainter extends CustomPainter {
  final Color color;
  CombPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
      
    final w = size.width;
    final h = size.height;
    
    // Spine
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.15, h * 0.4, w * 0.85, h * 0.5), const Radius.circular(4)), paint);
    
    // Teeth
    for (int i = 0; i < 14; i++) {
      final double x = w * 0.2 + (i * w * 0.046);
      canvas.drawLine(Offset(x, h * 0.5), Offset(x, h * 0.7), paint..strokeWidth = 1.5);
    }
  }
  @override
  bool shouldRepaint(covariant CombPainter oldDelegate) => oldDelegate.color != color;
}

class HandMirrorPainter extends CustomPainter {
  final Color color;
  HandMirrorPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
      
    final w = size.width;
    final h = size.height;
    
    // Handle
    canvas.drawLine(Offset(w * 0.5, h * 0.9), Offset(w * 0.5, h * 0.65), paint);
    
    // Mirror frame
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.35), width: w * 0.55, height: h * 0.55), paint);
    
    // Inner reflection
    final reflection = Path()
      ..moveTo(w * 0.35, h * 0.2)
      ..quadraticBezierTo(w * 0.45, h * 0.15, w * 0.55, h * 0.25);
    canvas.drawPath(reflection, paint..strokeWidth = 1.0);
  }
  @override
  bool shouldRepaint(covariant HandMirrorPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------
// ELEGANT MOTION TRAILS AND SPARKLES
// ---------------------------------------------------------

class TrailPainter extends CustomPainter {
  final double progress;
  final Color color;
  TrailPainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;
    
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;

    // Trail 1: Top-Left to Bottom-Right orbiting the logo
    final path1 = Path()
      ..moveTo(cx - 150, cy - 100)
      ..quadraticBezierTo(cx - 50, cy - 120, cx, cy - 80)
      ..quadraticBezierTo(cx + 80, cy - 20, cx + 120, cy + 50);

    // Trail 2: Bottom-Left to Top-Right
    final path2 = Path()
      ..moveTo(cx - 120, cy + 100)
      ..quadraticBezierTo(cx, cy + 120, cx + 60, cy + 80)
      ..quadraticBezierTo(cx + 100, cy + 20, cx + 140, cy - 60);

    _drawAnimatedPath(canvas, path1, progress, color, 0.2, 0.6);
    _drawAnimatedPath(canvas, path2, progress, color, 0.35, 0.75);
  }
  
  void _drawAnimatedPath(Canvas canvas, Path path, double t, Color color, double startT, double endT) {
    if (t < startT) return;
    
    final localT = ((t - startT) / (endT - startT)).clamp(0.0, 1.0);
    
    final metric = path.computeMetrics().first;
    final totalLen = metric.length;
    
    final head = totalLen * localT;
    final tailLen = totalLen * 0.4;
    final tail = (head - tailLen).clamp(0.0, totalLen);
    
    if (head > 0 && head > tail) {
      final segment = metric.extractPath(tail, head);
      final fadeOut = 1.0 - ((localT - 0.7) / 0.3).clamp(0.0, 1.0);
      
      canvas.drawPath(
        segment, 
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: fadeOut * 0.3)
      );
    }
  }

  @override
  bool shouldRepaint(covariant TrailPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class SparklePainter extends CustomPainter {
  final double progress; 
  final Color color;
  SparklePainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;
    
    // Pop and fade
    final scale = math.sin(progress * math.pi); 
    if (scale <= 0) return;

    final paint = Paint()
      ..color = color.withValues(alpha: scale * 0.8)
      ..style = PaintingStyle.fill;
      
    void drawSparkle(Offset center, double maxRadius) {
      final r = maxRadius * scale;
      final path = Path()
        ..moveTo(center.dx, center.dy - r)
        ..quadraticBezierTo(center.dx + r*0.2, center.dy - r*0.2, center.dx + r, center.dy)
        ..quadraticBezierTo(center.dx + r*0.2, center.dy + r*0.2, center.dx, center.dy + r)
        ..quadraticBezierTo(center.dx - r*0.2, center.dy + r*0.2, center.dx - r, center.dy)
        ..quadraticBezierTo(center.dx - r*0.2, center.dy - r*0.2, center.dx, center.dy - r)
        ..close();
      canvas.drawPath(path, paint);
    }
    
    final cx = size.width / 2;
    final cy = size.height / 2;
    
    drawSparkle(Offset(cx + 90, cy - 40), 12);
    drawSparkle(Offset(cx - 80, cy + 30), 8);
    drawSparkle(Offset(cx - 60, cy - 50), 6);
  }

  @override
  bool shouldRepaint(covariant SparklePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
