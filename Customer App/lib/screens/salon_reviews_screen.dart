import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/review_service.dart';
import '../theme/app_theme.dart';
import '../widgets/rating_bars.dart';
import '../theme/app_colors.dart';
import '../utils/bottom_clearance.dart';
import '../widgets/skeleton.dart';

/// Every review a salon has, with the two filters a reader actually wants.
///
/// The questions people bring to a review page are "what do the bad ones say"
/// and "show me the ones that said something" — not "sort by date". So the
/// filters are the star rows themselves, which doubles the distribution chart
/// as the navigation.
class SalonReviewsScreen extends StatefulWidget {
  final String salonId;
  final String salonName;

  const SalonReviewsScreen({
    Key? key,
    required this.salonId,
    required this.salonName,
  }) : super(key: key);

  @override
  State<SalonReviewsScreen> createState() => _SalonReviewsScreenState();
}

class _SalonReviewsScreenState extends State<SalonReviewsScreen> {
  final _scrollController = ScrollController();

  Map<String, dynamic>? _summary;
  final List<dynamic> _reviews = [];

  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;

  int? _starFilter;
  bool _onlyWithComment = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load the next page before they hit the bottom, so the list never
    // visibly stalls.
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400 &&
        _hasMore &&
        !_loadingMore) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _failed = false;
        _page = 1;
        _reviews.clear();
      });
    } else {
      setState(() => _loadingMore = true);
    }

    final body = await ReviewService.forSalon(
      widget.salonId,
      page: _page,
      rating: _starFilter,
      withComment: _onlyWithComment,
    );

    if (!mounted) return;

    setState(() {
      if (body == null) {
        _failed = reset;
      } else {
        _summary = Map<String, dynamic>.from(body['summary'] as Map);
        _reviews.addAll(body['reviews'] as List? ?? const []);
        final meta = body['meta'] as Map?;
        _hasMore = meta?['has_more'] == true;
        if (_hasMore) _page++;
      }
      _loading = false;
      _loadingMore = false;
    });
  }

  void _applyStarFilter(int? star) {
    setState(() => _starFilter = _starFilter == star ? null : star);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surfaceMuted,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ratings & reviews',
                style: GoogleFonts.outfit(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary)),
            Text(widget.salonName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(fontSize: 12, color: context.colors.textSecondary)),
          ],
        ),
      ),
      body: _loading
          ? SkeletonList(
              padding: const EdgeInsets.all(16),
              itemBuilder: (_) => const ReviewSkeleton(),
              count: 4,
            )
          : _failed
              ? _buildFailed()
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(16, 16, 16, bottomClearance(context)),
                    children: [
                      RatingSummaryCard(
                        summary: _summary ?? const {},
                        activeStar: _starFilter,
                        onStarTapped: _applyStarFilter,
                      ),
                      const SizedBox(height: 16),
                      _buildFilterRow(),
                      const SizedBox(height: 14),
                      if (_reviews.isEmpty)
                        _buildEmpty()
                      else ...[
                        for (final review in _reviews)
                          ReviewTile(review: Map<String, dynamic>.from(review as Map)),
                        if (_loadingMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: ReviewSkeleton(),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildFilterRow() => Row(
        children: [
          Expanded(
            child: Text(
              _describeFilter(),
              style: GoogleFonts.outfit(
                  fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _onlyWithComment = !_onlyWithComment);
              _load(reset: true);
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: _onlyWithComment ? context.colors.accentSoft : context.colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _onlyWithComment ? AppTheme.accentColor : context.colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _onlyWithComment ? Icons.check_rounded : Icons.notes_rounded,
                    size: 14,
                    color: _onlyWithComment ? AppTheme.accentColor : context.colors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text('With comments',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: _onlyWithComment ? FontWeight.bold : FontWeight.normal,
                        color: _onlyWithComment ? AppTheme.accentColor : context.colors.textSecondary,
                      )),
                ],
              ),
            ),
          ),
        ],
      );

  String _describeFilter() {
    if (_starFilter != null) return '$_starFilter-star reviews';
    return 'All reviews';
  }

  Widget _buildEmpty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.rate_review_outlined, size: 44, color: context.colors.textTertiary),
            const SizedBox(height: 14),
            Text(
              _starFilter != null || _onlyWithComment
                  ? 'No reviews match that filter.'
                  : 'No reviews yet — be the first to rate this salon.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13.5, color: context.colors.textSecondary),
            ),
          ],
        ),
      );

  Widget _buildFailed() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 44, color: context.colors.textTertiary),
              const SizedBox(height: 14),
              Text('Could not load reviews.',
                  style: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _load(reset: true),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.accentColor),
              ),
            ],
          ),
        ),
      );
}
