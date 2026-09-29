import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// A salon cover image, or a storefront placeholder when there is nothing to
/// show.
///
/// Assigned and My Salons each had their own version of this at a different
/// size — 56px and 62px for the same idea. They now share one at [size] = 60.
class CollaboratorThumb extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;

  const CollaboratorThumb({
    super.key,
    required this.url,
    this.size = 60,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.storefront_outlined,
        size: size * 0.38,
        color: AppTheme.accentColor,
      ),
    );

    if (url == null || url!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A dead CDN link is normal on a salon that has just been submitted,
        // so it falls back rather than throwing a red error box at the user.
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}
