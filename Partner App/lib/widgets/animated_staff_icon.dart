import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/app_theme.dart';

class AnimatedStaffIcon extends StatefulWidget {
  final bool isActive;
  const AnimatedStaffIcon({super.key, required this.isActive});

  @override
  State<AnimatedStaffIcon> createState() => _AnimatedStaffIconState();
}

class _AnimatedStaffIconState extends State<AnimatedStaffIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    if (widget.isActive) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedStaffIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.forward(from: 0.0);
    } else if (!widget.isActive) {
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When inactive, match the standard BottomNavigationBar unselected color.
    final unselectedColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    final activeColor = AppTheme.accentColor;

    // Both are inactive grey when not selected. 
    // When selected, Person A becomes purple.
    final personAColor = widget.isActive ? activeColor : unselectedColor;
    final personBColor = unselectedColor;

    // When inactive, we can just use people_outline if we want, or just two person_outlines
    final iconData = widget.isActive ? Icons.person : Icons.person_outline;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        // angle goes from 0 to 2*pi
        final angle = _animation.value * 2 * math.pi;

        // Circular/Orbital math
        // We use radiusX and radiusY to create a slightly elliptical orbit
        const double radiusX = 4.0;
        const double radiusY = 2.0;

        // Person A starts on the left (-radiusX)
        final aX = -radiusX * math.cos(angle);
        final aY = -radiusY * math.sin(angle);

        // Person B starts on the right (radiusX)
        final bX = radiusX * math.cos(angle);
        final bY = radiusY * math.sin(angle);

        final personA = Transform.translate(
          offset: Offset(aX, aY),
          child: Icon(iconData, color: personAColor, size: 22),
        );

        final personB = Transform.translate(
          offset: Offset(bX, bY),
          child: Icon(iconData, color: personBColor, size: 22),
        );

        // Z-Index: the person with the higher Y value is drawn last (on top)
        final children = aY > bY ? [personB, personA] : [personA, personB];

        return SizedBox(
          width: 26,
          height: 26,
          child: Stack(
            alignment: Alignment.center,
            children: children,
          ),
        );
      },
    );
  }
}

