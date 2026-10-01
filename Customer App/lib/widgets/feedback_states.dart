import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// What an [InlineStatus] is telling the customer.
enum StatusKind { error, warning, info, success }

/// A message shown in place, next to the thing it is about.
///
/// The app used SnackBars for this, which is the wrong tool for anything but
/// a passing confirmation: they vanish before a slow reader finishes, they
/// stack, they cover the bottom of the page — and with the keyboard up they
/// sit behind it. An inline status stays until it is resolved, and a screen
/// reader announces it when it appears.
///
/// SnackBars remain for "Saved."-style confirmations, where vanishing is the
/// point.
class InlineStatus extends StatelessWidget {
  const InlineStatus({
    super.key,
    required this.message,
    this.kind = StatusKind.error,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.onDismiss,
  });

  final String message;
  final StatusKind kind;

  /// Shows a retry action when set.
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Shows a close button when set.
  final VoidCallback? onDismiss;

  static const Key retryKey = Key('inline-status-retry');
  static const Key dismissKey = Key('inline-status-dismiss');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color tone, Color background, IconData icon) = switch (kind) {
      StatusKind.error => (colors.danger, colors.dangerBg, Icons.error_outline_rounded),
      StatusKind.warning => (colors.warning, colors.warningBg, Icons.warning_amber_rounded),
      StatusKind.info => (colors.info, colors.infoBg, Icons.info_outline_rounded),
      StatusKind.success => (colors.success, colors.successBg, Icons.check_circle_outline_rounded),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(icon, size: 18, color: tone)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.outfit(
                  color: tone,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                key: retryKey,
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: tone,
                  minimumSize: const Size(48, 48),
                ),
                child: Text(retryLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            if (onDismiss != null)
              IconButton(
                key: dismissKey,
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded, size: 18, color: tone),
              ),
          ],
        ),
      ),
    );
  }
}

/// A whole area that failed to load, with a way to try again.
///
/// Replaces the bare "Something went wrong" text some screens showed with no
/// retry, which left pulling to refresh — if the screen had it — as the only
/// way out.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.message = 'Check your connection and try again.',
    this.icon = Icons.cloud_off_rounded,
    required this.onRetry,
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback onRetry;

  static const Key retryKey = Key('error-state-retry');

  @override
  Widget build(BuildContext context) {
    return _CentredState(
      icon: icon,
      title: title,
      message: message,
      action: ElevatedButton.icon(
        key: retryKey,
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 19),
        label: const Text('Try again'),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.colors.actionFill,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
        ),
      ),
    );
  }
}

/// Nothing to show yet — said plainly, with the obvious next step.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  static const Key actionKey = Key('empty-state-action');

  @override
  Widget build(BuildContext context) {
    return _CentredState(
      icon: icon,
      title: title,
      message: message,
      action: actionLabel == null || onAction == null
          ? null
          : OutlinedButton(
              key: actionKey,
              onPressed: onAction,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(actionLabel!),
            ),
    );
  }
}

class _CentredState extends StatelessWidget {
  const _CentredState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: colors.accentSoft, shape: BoxShape.circle),
              child: ExcludeSemantics(
                child: Icon(icon, size: 34, color: AppTheme.accentColor),
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(fontSize: 14, height: 1.45, color: colors.textSecondary),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Wraps a centred state so it can sit inside a RefreshIndicator: the
/// indicator needs a scrollable child even when there is nothing to scroll,
/// or pulling down does nothing on an error or empty screen.
class ScrollableState extends StatelessWidget {
  const ScrollableState({super.key, required this.child, this.bottomInset = 0});

  final Widget child;

  /// Extra space at the bottom, e.g. for the floating navigation pill.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - bottomInset).clamp(0, double.infinity),
          ),
          child: child,
        ),
      ),
    );
  }
}
