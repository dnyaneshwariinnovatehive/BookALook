import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// An in-app viewer for salon payment transfer proof screenshots.
///
/// Features interactive zoom/pan, loading indicators, graceful error handling,
/// and an external browser fallback.
class PaymentProofViewer extends StatefulWidget {
  final String imageUrl;
  final String? title;
  final String? transactionId;
  final String? note;

  const PaymentProofViewer({
    super.key,
    required this.imageUrl,
    this.title,
    this.transactionId,
    this.note,
  });

  /// Convenience helper to display the proof viewer in a full modal.
  static Future<void> show(
    BuildContext context, {
    required String imageUrl,
    String? title,
    String? transactionId,
    String? note,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PaymentProofViewer(
        imageUrl: imageUrl,
        title: title,
        transactionId: transactionId,
        note: note,
      ),
    );
  }

  @override
  State<PaymentProofViewer> createState() => _PaymentProofViewerState();
}

class _PaymentProofViewerState extends State<PaymentProofViewer> {
  int _imageKey = 0;

  void _retry() {
    setState(() {
      _imageKey++;
    });
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.imageUrl.trim());
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(milliseconds: 2500),
            content: Text('Could not open the link in browser.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 750),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 22,
                    color: AppTheme.accentColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title ?? 'Payment Proof',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (widget.transactionId != null &&
                            widget.transactionId!.isNotEmpty)
                          Text(
                            'Ref: ${widget.transactionId}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // Image Content
            Flexible(
              child: Container(
                color: isDark ? Colors.black : Colors.grey.shade100,
                alignment: Alignment.center,
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Image.network(
                    widget.imageUrl,
                    key: ValueKey(_imageKey),
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      final total = loadingProgress.expectedTotalBytes;
                      final current = loadingProgress.cumulativeBytesLoaded;
                      final progress = (total != null && total > 0)
                          ? current / total
                          : null;

                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppTheme.accentColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Loading payment proof…',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image_outlined,
                              size: 48,
                              color: colors.danger,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Could not load the payment proof',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Please check your internet connection or open in browser.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Note (if present)
            if (widget.note != null && widget.note!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: colors.surfaceMuted,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.note_outlined,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.note!,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Footer actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: const Text('Open original'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      textStyle: GoogleFonts.outfit(fontSize: 13),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
