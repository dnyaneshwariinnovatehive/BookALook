import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// One tab in [FloatingPillNavBar].
class PillNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const PillNavItem({required this.icon, required this.activeIcon, required this.label});
}

/// The floating rounded navigation bar the customer app uses: a pill held off
/// the screen edges, the selected icon filling in with a small pop, and a dot
/// under the selected label. Kept identical to the customer app so both apps
/// feel like one product.
class FloatingPillNavBar extends StatelessWidget {
  static const double height = 75;
  static const double margin = 20;

  final List<PillNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FloatingPillNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.only(left: margin, right: margin, bottom: margin),
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: context.colors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9850F1).withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                _NavButton(item: items[i], isSelected: i == currentIndex, onTap: () => onTap(i)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final PillNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavButton({required this.item, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppTheme.accentColor : context.colors.textTertiary;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: item.label,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: AppTheme.accentColor.withValues(alpha: 0.1),
            highlightColor: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AnimatedTabIcon(icon: item.icon, activeIcon: item.activeIcon, isSelected: isSelected),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: isSelected ? 5 : 0,
                  height: isSelected ? 5 : 0,
                  decoration: const BoxDecoration(color: AppTheme.accentColor, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The selected icon pops up and back while it swaps to its filled version.
class _AnimatedTabIcon extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;

  const _AnimatedTabIcon({required this.icon, required this.activeIcon, required this.isSelected});

  @override
  State<_AnimatedTabIcon> createState() => _AnimatedTabIconState();
}

class _AnimatedTabIconState extends State<_AnimatedTabIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _lift;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 60),
    ]).animate(_controller);

    _lift = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -3.0).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -3.0, end: 0.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 60),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _AnimatedTabIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      // No pop when the system asks for reduced motion.
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
      _controller.forward(from: 0.0);
    } else if (!widget.isSelected && oldWidget.isSelected) {
      // A quick tap elsewhere snaps this one back rather than finishing.
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _lift.value),
        child: Transform.scale(scale: _scale.value, child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: Icon(
            widget.isSelected ? widget.activeIcon : widget.icon,
            key: ValueKey<bool>(widget.isSelected),
            size: 22,
            color: widget.isSelected ? AppTheme.accentColor : context.colors.textTertiary,
          ),
        ),
      ),
    );
  }
}
