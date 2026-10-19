import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/review_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../utils/bottom_clearance.dart';

/// Asks a customer how their visit went, the moment they next open the app.
///
/// Built around one rule: the star is the whole ask. Tapping a star is a
/// second's work and most people will do it; typing a paragraph is optional.
/// The stars come first and an optional comment appears only after a rating
/// has been given, and is always skippable.
class ReviewPromptSheet extends StatefulWidget {
  /// The visit being rated, as returned by /customer/reviews/pending.
  final Map<String, dynamic> visit;

  const ReviewPromptSheet({super.key, required this.visit});

  /// Returns true when a review was actually submitted.
  static Future<bool> show(BuildContext context, Map<String, dynamic> visit) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      // Dismissable on purpose. A rating prompt that traps you is a rating
      // prompt people learn to resent.
      isDismissible: true,
      builder: (_) => ReviewPromptSheet(visit: visit),
    );

    return submitted == true;
  }

  @override
  State<ReviewPromptSheet> createState() => _ReviewPromptSheetState();
}

class _ReviewPromptSheetState extends State<ReviewPromptSheet> {
  int _rating = 0;
  bool _submitting = false;
  String? _error;

  final _comment = TextEditingController();

  static const _ratingWords = {
    1: 'Poor',
    2: 'Not great',
    3: 'Fine',
    4: 'Good',
    5: 'Excellent',
  };

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  String get _salonName => widget.visit['salon_name']?.toString() ?? 'the salon';

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Tap a star to rate your visit.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await ReviewService.submit(
        appointmentId: widget.visit['appointment_id'].toString(),
        rating: _rating,
        comment: _comment.text,
      );

      if (!mounted) return;
      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message']?.toString() ?? 'Thanks for rating your visit.'),
      ));
    } on ReviewRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No connection. Your rating was not saved — try again in a moment.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),

              _buildHeader(),
              const SizedBox(height: 22),
              _buildStars(),

              // Everything below only matters once they have rated.
              if (_rating > 0) ...[
                const SizedBox(height: 22),
                _buildCommentField(),
              ],

              if (_error != null) ...[
                const SizedBox(height: 14),
                _buildError(),
              ],

              const SizedBox(height: 22),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final provider = widget.visit['provider_name']?.toString();
    final visited = widget.visit['visited_label']?.toString() ?? '';

    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: context.colors.accentSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.rate_review_outlined,
              size: 28, color: AppTheme.accentColor),
        ),
        const SizedBox(height: 14),
        Text(
          'How was $_salonName?',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          [
            if (provider != null && provider.isNotEmpty) 'With $provider',
            // Left as the caller wrote it. Lowercasing turned "On 14 Sep 2026"
            // into "on 14 sep 2026" once this sheet started being opened from a
            // dated booking card as well as from the launch prompt.
            if (visited.isNotEmpty) visited,
          ].join(' · '),
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(fontSize: 13, color: context.colors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildStars() => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final star = index + 1;
              final filled = star <= _rating;

              return GestureDetector(
                onTap: () => setState(() {
                  _rating = star;
                  _error = null;
                }),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 42,
                    color: filled ? const Color(0xFFF5A623) : context.colors.border,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _rating == 0 ? 'Tap to rate' : _ratingWords[_rating]!,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: _rating == 0 ? FontWeight.normal : FontWeight.bold,
              color: _rating == 0 ? context.colors.textTertiary : context.colors.textPrimary,
            ),
          ),
        ],
      );

  Widget _buildCommentField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Anything to add?',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text('optional',
                  style: GoogleFonts.outfit(fontSize: 11.5, color: context.colors.textTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            maxLines: 3,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: _rating >= 4
                  ? 'What went well?'
                  : 'What would have made it better?',
              hintStyle: GoogleFonts.outfit(color: context.colors.textTertiary, fontSize: 13.5),
              counterText: '',
              filled: true,
              fillColor: context.colors.surfaceMuted,
              contentPadding: const EdgeInsets.all(14),
              border: _border(context.colors.border),
              enabledBorder: _border(context.colors.border),
              focusedBorder: _border(AppTheme.accentColor),
            ),
          ),
        ],
      );

  Widget _buildError() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.dangerBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: context.colors.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: GoogleFonts.outfit(
                  color: context.colors.danger,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildActions() => Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppTheme.accentColor,
                foregroundColor: context.colors.onAccent,
                disabledBackgroundColor: context.colors.border,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? SizedBox(
                      height: 19,
                      width: 19,
                      child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.onAccent))
                  : Text('Submit rating',
                      style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context, false),
            child: Text('Maybe later',
                style: GoogleFonts.outfit(fontSize: 13.5, color: context.colors.textSecondary)),
          ),
        ],
      );

  OutlineInputBorder _border(Color colour) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colour),
      );
}
