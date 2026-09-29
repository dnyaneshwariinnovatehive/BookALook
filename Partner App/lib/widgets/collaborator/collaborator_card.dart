import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// The collaborator app's one card treatment.
///
/// Every panel in the four tabs used to hand-roll this — a white `Container`
/// with a 14px radius and a 1px border — and they had already drifted, with
/// some cards at 14 and some at 16. Radius is the default here so a panel
/// cannot quietly become a different shape from its neighbours.
///
/// Pass [onTap] and the card gets a real ripple. The tap targets this replaces
/// were raw `GestureDetector`s, which gave no press feedback at all and
/// announced nothing to a screen reader.
class CollaboratorCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  /// Overrides the fill. Used by the warning and danger callouts, which are
  /// tinted rather than neutral.
  final Color? color;

  /// Overrides the outline. Defaults to a hairline in the current palette.
  final Color? borderColor;

  final double radius;

  const CollaboratorCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 14),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? palette.border),
      ),
      // Clipping here is what lets the ink splash stop at the rounded corner
      // instead of bleeding out over the scaffold.
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap,
                splashColor: AppTheme.accentColor.withValues(alpha: 0.08),
                highlightColor: AppTheme.accentColor.withValues(alpha: 0.04),
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
  }
}
