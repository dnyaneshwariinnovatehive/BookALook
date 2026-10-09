import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partner_app/theme/app_theme.dart';

class BookALookTabLoadingOverlay extends StatefulWidget {
  final String message;
  final int tabIndex;

  const BookALookTabLoadingOverlay({
    super.key,
    required this.message,
    required this.tabIndex,
  });

  @override
  State<BookALookTabLoadingOverlay> createState() =>
      _BookALookTabLoadingOverlayState();
}

class _BookALookTabLoadingOverlayState extends State<BookALookTabLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine which icons to show based on tab
    IconData icon1;
    IconData icon2;

    switch (widget.tabIndex) {
      case 0: // Home
        icon1 = Icons.home_outlined;
        icon2 = Icons.auto_awesome;
        break;
      case 1: // Appointments
        icon1 = Icons.calendar_today_outlined;
        icon2 = Icons.auto_awesome;
        break;
      case 2: // Staff
        icon1 = Icons.people_outline;
        icon2 = Icons.auto_awesome;
        break;
      case 3: // Services
        icon1 = Icons.content_cut_outlined;
        icon2 = Icons.auto_awesome;
        break;
      case 4: // More
        icon1 = Icons.settings_outlined;
        icon2 = Icons.auto_awesome;
        break;
      default:
        icon1 = Icons.auto_awesome;
        icon2 = Icons.content_cut_outlined;
    }

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  // Gentle float and rotate
                  final float1 = math.sin(_controller.value * 2 * math.pi) * 6;
                  final float2 = math.cos(_controller.value * 2 * math.pi) * 6;
                  
                  final pulse = 0.8 + (math.sin(_controller.value * 2 * math.pi) + 1) * 0.1;

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(-10, float1 - 10),
                        child: Transform.rotate(
                          angle: -0.2,
                          child: Icon(
                            icon1,
                            size: 32,
                            color: AppTheme.accentColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(15, float2 + 5),
                        child: Transform.scale(
                          scale: pulse,
                          child: Transform.rotate(
                            angle: 0.2,
                            child: Icon(
                              icon2,
                              size: 24,
                              color: AppTheme.accentGradientLightEnd.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.message,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
