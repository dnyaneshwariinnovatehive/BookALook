import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// A person's initials in a circle, for anywhere the app would otherwise need
/// a face to show.
///
/// There is no photo for any human role in this product — no column on
/// `service_providers`, none on `users`, and no upload anywhere — so an avatar
/// that stands in for a person is always a placeholder. This is the honest one:
/// it says who the person is by their name instead of drawing a stranger's face
/// or a generic silhouette that looks like a photo failed to load.
///
/// Two initials rather than one, because a single letter gives every customer in
/// a city the same circle: "Aarav Sharma" and "Anita Verma" would both be "A".
/// With first and last, the two are told apart at a glance.
class InitialsAvatar extends StatelessWidget {
  /// The person's name. Anything non-letter is ignored, so "Dr. Aarav Sharma (Jr)"
  /// reads "AS" rather than "DA".
  final String name;

  final double radius;

  /// Dims the circle and the letters, for someone the app is only listing rather
  /// than presenting as active.
  final bool dimmed;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.radius = 24,
    this.dimmed = false,
  });

  /// Honourifics that turn up inside a stored name without being part of it.
  /// Matched after punctuation is split off, so these carry no full stops.
  static const Set<String> _titles = {
    'dr',
    'mr',
    'mrs',
    'ms',
    'miss',
    'prof',
    'shri',
    'smt',
  };

  /// The letters themselves, separated out so they can be reused and tested
  /// without a widget.
  static String initialsOf(String name) {
    // A parenthetical is a qualification or a suffix, not part of the name, so
    // "Aarav Sharma (Jr)" has to read "AS" and not "AJ".
    final segments = name
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .split(RegExp(r'[^a-zA-Z]+'))
        .where((w) => w.isNotEmpty)
        .toList();

    // Titles get stored inside a name but aren't part of it, so "Dr. Priya
    // Sharma" has to read "PS" and not "DS". A name that is *only* a title still
    // falls back to that title's own letter rather than to a question mark.
    final words = segments
        .where((w) => !_titles.contains(w.toLowerCase()))
        .toList();

    if (words.isEmpty)
      return segments.isEmpty ? '?' : segments.first[0].toUpperCase();

    // One word gives the one letter it has; more than one gives first and last,
    // skipping any middle name so "Aarav Kumar Sharma" stays "AS".
    if (words.length == 1) return words.first[0].toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color background;
    final Color foreground;

    if (dimmed) {
      background = isDark ? AppTheme.darkTextLight : AppTheme.lightBorder;
      foreground = isDark ? AppTheme.darkSurface : AppTheme.lightTextLight;
    } else {
      background = isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft;
      foreground = AppTheme.accentColor;
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      child: Text(
        initialsOf(name),
        style: GoogleFonts.outfit(
          fontSize: radius * 0.72,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
      ),
    );
  }
}
