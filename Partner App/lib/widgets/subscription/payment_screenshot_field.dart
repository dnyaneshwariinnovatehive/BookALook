import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Where the owner attaches the screenshot of a payment to BookALook (a plan,
/// or dues), and sees plainly that it is attached.
///
/// It used to be an outlined button whose label changed from "Upload
/// Screenshot" to "Screenshot Selected" — easy to miss, with no way to see
/// which picture was chosen. Now the empty state is a clear drop zone, and an
/// attached screenshot turns into a green card with the picture itself, its
/// name and size, and Change / Remove.
class PaymentScreenshotField extends StatelessWidget {
  const PaymentScreenshotField({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.onPick,
    this.onRemove,
    this.enabled = true,
    this.hasError = false,
    this.pickKey,
  });

  /// The attached image, or null when nothing is attached yet.
  final Uint8List? bytes;
  final String? fileName;
  final VoidCallback onPick;
  final VoidCallback? onRemove;
  final bool enabled;

  /// Outlines the empty state in red, after Submit was tapped without one.
  final bool hasError;

  /// Put on the tappable area that opens the picker, for tests.
  final Key? pickKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(animation), child: child),
      ),
      child: bytes == null ? _empty(context) : _attached(context, bytes!),
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final edge = hasError ? (dark ? AppTheme.darkDanger : AppTheme.lightDanger) : AppTheme.accentColor;

    return Material(
      key: const ValueKey('screenshot-empty'),
      color: (hasError ? edge : AppTheme.accentColor).withValues(alpha: dark ? 0.10 : 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: pickKey,
        onTap: enabled ? onPick : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: edge.withValues(alpha: 0.55), width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: edge.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_photo_alternate_outlined, color: edge, size: 26),
              ),
              const SizedBox(height: 10),
              Text(
                'Upload payment screenshot',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: scheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                hasError ? 'Required — attach it to submit' : 'Tap to choose it from your gallery',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: hasError ? edge : scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attached(BuildContext context, Uint8List image) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? AppTheme.darkSuccess : AppTheme.lightSuccess;
    final name = (fileName == null || fileName!.isEmpty) ? 'payment-screenshot.jpg' : fileName!;

    return Container(
      key: const ValueKey('screenshot-attached'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: green.withValues(alpha: dark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: green.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        children: [
          // The picture itself, so the owner can see they chose the right one.
          Semantics(
            button: true,
            label: 'View attached screenshot',
            child: GestureDetector(
              onTap: () => _preview(context, image),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      image,
                      width: 64,
                      height: 76,
                      fit: BoxFit.cover,
                      // A file the phone cannot decode still counts as attached;
                      // show a page icon rather than nothing.
                      errorBuilder: (_, _, _) => Container(
                        width: 64,
                        height: 76,
                        color: green.withValues(alpha: 0.15),
                        child: Icon(Icons.image_outlined, color: green),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                      child: const Icon(Icons.zoom_in, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: green, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Screenshot attached',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: green),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                ),
                Text(
                  '${_size(image.lengthInBytes)} · ready to submit',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: pickKey,
                onPressed: enabled ? onPick : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppTheme.accentColor,
                ),
                child: const Text('Change'),
              ),
              if (onRemove != null)
                TextButton(
                  onPressed: enabled ? onRemove : null,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  child: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).ceil()} KB';
  }

  static void _preview(BuildContext context, Uint8List image) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(image, fit: BoxFit.contain),
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A short buzz when a screenshot is attached, so it is felt as well as seen.
  static void confirmAttached() => HapticFeedback.mediumImpact();
}
