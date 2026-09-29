import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// The "there is nothing here" panel.
///
/// Each tab had its own, and they disagreed — Assigned offered a "Check again"
/// button, My Salons offered "Refresh", and neither told the collaborator what
/// to do about it. An empty list in this app is never a dead end: work arrives
/// when SuperAdmin assigns it, so the useful action is either to retry the
/// fetch or to go somewhere the work actually shows up.
class CollaboratorEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  /// Optional call to action. Without one the state is informational only.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A quieter second action, for "go to the tab where the work is".
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const CollaboratorEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: palette.textTertiary),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: palette.textSecondary,
              ),
            ),
            if (onAction != null || onSecondary != null) ...[
              const SizedBox(height: 20),
              if (onAction != null)
                OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: Text(actionLabel ?? 'Try again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                    backgroundColor: palette.accentSoft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              if (onAction != null && onSecondary != null)
                const SizedBox(height: 4),
              if (onSecondary != null)
                TextButton(
                  onPressed: onSecondary,
                  child: Text(
                    secondaryLabel ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A full-screen loading state that still lets a pull-to-refresh through.
///
/// The tabs used `Center(child: CircularProgressIndicator())` on their first
/// paint, which meant a blank page with a spinner for as long as three network
/// calls took. This keeps the scaffold sized correctly and is scrollable, so
/// an impatient pull is handled rather than swallowed.
class CollaboratorLoadingState extends StatelessWidget {
  final String message;

  const CollaboratorLoadingState({super.key, this.message = 'Loading…'});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}
