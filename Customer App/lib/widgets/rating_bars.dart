import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// The star colour, in one place, so nothing drifts.
const kStarColour = Color(0xFFF5A623);

/// A row of five stars at a given size, filled to [rating].
///
/// Halves matter here: a salon averaging 4.5 shown as four stars is being
/// undersold, and shown as five is being oversold.
class StarRow extends StatelessWidget {
  final double rating;
  final double size;
  final Color? colour;

  const StarRow({Key? key, required this.rating, this.size = 14, this.colour})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final position = index + 1;
        final icon = rating >= position
            ? Icons.star_rounded
            : rating >= position - 0.5
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded;

        return Icon(icon, size: size, color: colour ?? kStarColour);
      }),
    );
  }
}

/// The headline average, and the distribution behind it.
///
/// The distribution is the honest part. Four stars made of straight fours is a
/// different salon from four stars made of fives and ones, and only the bars
/// show which one you are looking at. Each bar is tappable, so the chart is
/// also the filter — the natural next thought after seeing a tall one-star bar
/// is "what do those say".
class RatingSummaryCard extends StatelessWidget {
  final Map<String, dynamic> summary;

  /// Star row currently being filtered on, if any.
  final int? activeStar;
  final ValueChanged<int?>? onStarTapped;

  const RatingSummaryCard({
    Key? key,
    required this.summary,
    this.activeStar,
    this.onStarTapped,
  }) : super(key: key);

  double get _average => (summary['average'] as num?)?.toDouble() ?? 0;
  int get _count => (summary['count'] as num?)?.toInt() ?? 0;

  /// Accepts either shape the API sends: `{5: {count, percent}}` from the
  /// service, or a flat `{5: count}` from older payloads.
  Map<int, ({int count, int percent})> get _breakdown {
    final raw = summary['breakdown'];
    if (raw is! Map) return {};

    final total = _count == 0 ? 1 : _count;
    final out = <int, ({int count, int percent})>{};

    raw.forEach((key, value) {
      final star = int.tryParse(key.toString());
      if (star == null) return;

      if (value is Map) {
        out[star] = (
          count: (value['count'] as num?)?.toInt() ?? 0,
          percent: (value['percent'] as num?)?.toInt() ?? 0,
        );
      } else if (value is num) {
        out[star] = (count: value.toInt(), percent: (value / total * 100).round());
      }
    });

    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return _buildEmpty();

    final breakdown = _breakdown;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Column(
              children: [
                Text(_average.toStringAsFixed(1),
                    style: GoogleFonts.outfit(
                        fontSize: 38,
                        height: 1.05,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.lightTextHeading)),
                const SizedBox(height: 4),
                StarRow(rating: _average, size: 15),
                const SizedBox(height: 6),
                Text('$_count ${_count == 1 ? 'rating' : 'ratings'}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                        fontSize: 11.5, color: AppTheme.lightTextBody)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  _buildBar(star, breakdown[star] ?? (count: 0, percent: 0)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBar(int star, ({int count, int percent}) row) {
    final active = activeStar == star;
    final tappable = onStarTapped != null && row.count > 0;

    return GestureDetector(
      onTap: tappable ? () => onStarTapped!(star) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Text('$star',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? AppTheme.accentColor : AppTheme.lightTextBody,
                  )),
            ),
            const Icon(Icons.star_rounded, size: 11, color: kStarColour),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: row.percent / 100,
                  minHeight: 7,
                  backgroundColor: AppTheme.lightBg,
                  valueColor: AlwaysStoppedAnimation(
                      active ? AppTheme.accentColor : kStarColour),
                ),
              ),
            ),
            SizedBox(
              width: 30,
              child: Text('${row.count}',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? AppTheme.accentColor : AppTheme.lightTextBody,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.rate_review_outlined, color: AppTheme.lightTextLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text('No ratings yet — be the first to rate this salon.',
                  style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody)),
            ),
          ],
        ),
      );
}

/// One review, as a reader sees it.
class ReviewTile extends StatelessWidget {
  final Map<String, dynamic> review;

  const ReviewTile({Key? key, required this.review}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment']?.toString() ?? '';
    final name = review['customer_name']?.toString() ?? 'Customer';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: AppTheme.lightAccentSoft,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentColor),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.lightTextHeading)),
              ),
              Text(review['age_label']?.toString() ?? '',
                  style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextLight)),
            ],
          ),
          const SizedBox(height: 9),
          StarRow(rating: rating.toDouble(), size: 14),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(comment,
                style: GoogleFonts.outfit(
                    fontSize: 13.5, height: 1.45, color: AppTheme.lightTextBody)),
          ],
        ],
      ),
    );
  }
}
