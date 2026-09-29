import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// A small status or to-do pill.
///
/// There were three near-identical copies of this across the tabs — `_todoChip`
/// on Assigned, `_statusChip` on Assigned, and a third inline version on My
/// Salons — which had already drifted on padding and radius. One widget now.
///
/// [colour] is the semantic foreground; the fill is that colour at low alpha,
/// which stays legible against both a light and a dark surface.
class CollaboratorChip extends StatelessWidget {
  final String label;
  final Color colour;

  /// Optional leading glyph. The status chips use one so the colour is not the
  /// only thing carrying the meaning.
  final IconData? icon;

  const CollaboratorChip({
    super.key,
    required this.label,
    required this.colour,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: colour),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: colour,
              fontWeight: FontWeight.bold,
              fontSize: icon != null ? 11 : 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A selectable filter pill for the My Salons status bar.
///
/// Kept separate from [CollaboratorChip] because selection is a different job:
/// this one is tappable, carries a count, and needs to look pressed when it is
/// the active filter.
class CollaboratorFilterChip extends StatelessWidget {
  final String label;

  /// How many items sit behind this filter. Shown inline so the collaborator
  /// can see where the work is before switching.
  final int count;

  final bool selected;
  final VoidCallback onTap;

  const CollaboratorFilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Material(
      color: selected ? AppTheme.accentColor : palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: selected
            ? Colors.white.withValues(alpha: 0.15)
            : AppTheme.accentColor.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.accentColor : palette.border,
            ),
          ),
          // The label states both the filter and its count, so it carries the
          // whole meaning for anyone not reading the pill's colour.
          child: Semantics(
            button: true,
            selected: selected,
            label: '$label, $count',
            excludeSemantics: true,
            child: Text(
              '$label · $count',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? palette.onAccent : palette.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
