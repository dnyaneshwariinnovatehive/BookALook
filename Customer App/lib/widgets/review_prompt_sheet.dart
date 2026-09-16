import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/review_service.dart';
import '../theme/app_theme.dart';

/// Asks a customer how their visit went, the moment they next open the app.
///
/// Built around one rule: the star is the whole ask. Tapping a star is a
/// second's work and most people will do it; typing a paragraph is a minute's
/// work and most people will not. So the stars come first and everything else
/// — words, and the option to report a problem — appears only after a rating
/// has been given, and is always skippable.
///
/// The report is folded in here rather than hidden in a menu because the
/// moment someone is telling you a visit went badly is the only moment they
/// will reliably say why.
class ReviewPromptSheet extends StatefulWidget {
  /// The visit being rated, as returned by /customer/reviews/pending.
  final Map<String, dynamic> visit;

  const ReviewPromptSheet({Key? key, required this.visit}) : super(key: key);

  /// Returns true when a review was actually submitted.
  static Future<bool> show(BuildContext context, Map<String, dynamic> visit) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
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

  // The report, only ever built when the customer asks for it.
  bool _reporting = false;
  final _complaintSubject = TextEditingController();
  final _complaintDetail = TextEditingController();

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
    _complaintSubject.dispose();
    _complaintDetail.dispose();
    super.dispose();
  }

  String get _salonName => widget.visit['salon_name']?.toString() ?? 'the salon';

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Tap a star to rate your visit.');
      return;
    }

    if (_reporting) {
      if (_complaintSubject.text.trim().isEmpty) {
        setState(() => _error = 'Give your report a short title.');
        return;
      }
      if (_complaintDetail.text.trim().isEmpty) {
        setState(() => _error = 'Tell us what went wrong.');
        return;
      }
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
        raiseComplaint: _reporting,
        complaintSubject: _complaintSubject.text.trim(),
        complaintDescription: _complaintDetail.text.trim(),
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                    color: AppTheme.lightBorder,
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
                const SizedBox(height: 14),
                _buildReportToggle(),
                if (_reporting) ...[
                  const SizedBox(height: 14),
                  _buildReportFields(),
                ],
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
            color: AppTheme.lightAccentSoft,
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
              color: AppTheme.lightTextHeading),
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
          style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody),
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
                    color: filled ? const Color(0xFFF5A623) : AppTheme.lightBorder,
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
              color: _rating == 0 ? AppTheme.lightTextLight : AppTheme.lightTextHeading,
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
                  style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextLight)),
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
              hintStyle: GoogleFonts.outfit(color: AppTheme.lightTextLight, fontSize: 13.5),
              counterText: '',
              filled: true,
              fillColor: AppTheme.lightBg,
              contentPadding: const EdgeInsets.all(14),
              border: _border(AppTheme.lightBorder),
              enabledBorder: _border(AppTheme.lightBorder),
              focusedBorder: _border(AppTheme.accentColor),
            ),
          ),
        ],
      );

  /// Reporting is a separate act from rating, and is worded as one. It is not
  /// presented as "leave a bad review" — a salon can be four stars and still
  /// have done something that needs reporting.
  Widget _buildReportToggle() => GestureDetector(
        onTap: () => setState(() {
          _reporting = !_reporting;
          _error = null;
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _reporting ? AppTheme.lightDangerBg : AppTheme.lightBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _reporting ? AppTheme.lightDanger.withOpacity(0.4) : AppTheme.lightBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _reporting ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: _reporting ? AppTheme.lightDanger : AppTheme.lightTextLight,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Report a problem',
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: _reporting ? AppTheme.lightDanger : AppTheme.lightTextHeading,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      'Goes privately to the BookALook team, not to the salon.',
                      style: GoogleFonts.outfit(
                          fontSize: 11.5, height: 1.3, color: AppTheme.lightTextBody),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildReportFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _complaintSubject,
            maxLength: 150,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'What happened, in a few words',
              labelStyle: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody),
              counterText: '',
              filled: true,
              fillColor: AppTheme.lightBg,
              contentPadding: const EdgeInsets.all(14),
              border: _border(AppTheme.lightBorder),
              enabledBorder: _border(AppTheme.lightBorder),
              focusedBorder: _border(AppTheme.lightDanger),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _complaintDetail,
            maxLines: 4,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Tell us more',
              labelStyle: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody),
              counterText: '',
              filled: true,
              fillColor: AppTheme.lightBg,
              contentPadding: const EdgeInsets.all(14),
              border: _border(AppTheme.lightBorder),
              enabledBorder: _border(AppTheme.lightBorder),
              focusedBorder: _border(AppTheme.lightDanger),
            ),
          ),
        ],
      );

  Widget _buildError() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.lightDangerBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 17, color: AppTheme.lightDanger),
            const SizedBox(width: 9),
            Expanded(
              child: Text(_error!,
                  style: GoogleFonts.outfit(
                      fontSize: 12.5, height: 1.35, color: AppTheme.lightDanger)),
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
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.lightBorder,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 19,
                      width: 19,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_reporting ? 'Submit rating and report' : 'Submit rating',
                      style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context, false),
            child: Text('Maybe later',
                style: GoogleFonts.outfit(fontSize: 13.5, color: AppTheme.lightTextBody)),
          ),
        ],
      );

  OutlineInputBorder _border(Color colour) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colour),
      );
}
