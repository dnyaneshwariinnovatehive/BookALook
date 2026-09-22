import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_config.dart';
import '../../../theme/app_theme.dart';

/// What customers said, written for a salon owner rather than an analyst.
///
/// An owner between customers has about ten seconds. So the page opens with one
/// sentence they can read and stop — "4.6 out of 5, from 38 customers" — then
/// one sentence on whether that is moving, and only then the detail. No charts,
/// no percentages to interpret, no metrics with names you have to learn.
///
/// The star bars double as the filter, because after seeing a tall 1-star bar
/// the only next thought is "what did those people say".
class SalonReviewsScreen extends StatefulWidget {
  final String salonId;

  const SalonReviewsScreen({super.key, required this.salonId});

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

  /// Matches the server's default. The labels come from the server too, so the
  /// menu cannot drift out of step with what the API will actually accept.
  String _sort = 'recent';
  Map<String, String> _sorts = const {
    'recent': 'Newest first',
    'oldest': 'Oldest first',
    'highest': 'Highest rated',
    'lowest': 'Lowest rated',
  };

  /// How many reviews matched the current filter, for the results line.
  int _total = 0;

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

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final uri = Uri.parse('${ApiConfig.baseUrl}/partner/salons/${widget.salonId}/reviews')
          .replace(queryParameters: {
        'page': '$_page',
        'sort': _sort,
        if (_starFilter != null) 'rating': '$_starFilter',
        if (_onlyWithComment) 'with_comment': '1',
      });

      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _failed = reset;
          _loading = false;
          _loadingMore = false;
        });
        return;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      final meta = body['meta'] as Map?;

      setState(() {
        _summary = Map<String, dynamic>.from(body['summary'] as Map);
        _reviews.addAll(body['reviews'] as List? ?? const []);
        _hasMore = meta?['has_more'] == true;
        _total = (meta?['total'] as num?)?.toInt() ?? _reviews.length;
        if (body['sorts'] is Map) {
          _sorts = Map<String, String>.from(body['sorts'] as Map);
        }
        if (_hasMore) _page++;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = reset;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _toggleStar(int star) {
    setState(() => _starFilter = _starFilter == star ? null : star);
    _load(reset: true);
  }

  int get _count => (_summary?['count'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        title: Text('Customer reviews',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? _buildFailed()
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _buildHeadlineCard(),
                      if (_count > 0) ...[
                        const SizedBox(height: 14),
                        _buildBreakdownCard(),
                        const SizedBox(height: 16),
                        _buildFilterRow(),
                        const SizedBox(height: 12),
                        if (_reviews.isEmpty)
                          _buildNoMatches()
                        else ...[
                          for (final review in _reviews)
                            _buildReviewTile(Map<String, dynamic>.from(review as Map)),
                          if (_loadingMore)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }

  /// The whole answer in two sentences. Everything below this card is optional
  /// reading.
  Widget _buildHeadlineCard() {
    final average = (_summary?['average'] as num?)?.toDouble() ?? 0;
    final headline = _summary?['headline']?.toString() ?? '';
    final trend = Map<String, dynamic>.from((_summary?['trend'] as Map?) ?? {});

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_count > 0) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(average.toStringAsFixed(1),
                    style: GoogleFonts.outfit(
                        fontSize: 42,
                        height: 1.05,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.lightTextHeading)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stars(average, 18),
                    const SizedBox(height: 4),
                    Text('out of 5',
                        style: GoogleFonts.outfit(
                            fontSize: 12.5, color: AppTheme.lightTextBody)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text(headline,
              style: GoogleFonts.outfit(
                  fontSize: 14, height: 1.4, color: AppTheme.lightTextBody)),
          if (trend['label'] != null) ...[
            const SizedBox(height: 12),
            _buildTrendChip(trend),
          ],
        ],
      ),
    );
  }

  /// This month against last, in words. Deliberately not a chart — and it says
  /// so outright when there are too few ratings to compare rather than
  /// inventing a direction from two data points.
  Widget _buildTrendChip(Map<String, dynamic> trend) {
    final direction = trend['direction']?.toString();
    final comparable = trend['comparable'] == true;

    final (colour, icon) = switch (direction) {
      'up' => (AppTheme.lightSuccess, Icons.trending_up_rounded),
      'down' => (AppTheme.lightDanger, Icons.trending_down_rounded),
      'flat' => (AppTheme.lightInfo, Icons.trending_flat_rounded),
      _ => (AppTheme.lightTextBody, Icons.schedule_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: comparable
            ? colour.withValues(alpha: 0.09)
            : AppTheme.lightBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: colour),
          const SizedBox(width: 9),
          Expanded(
            child: Text(trend['label'].toString(),
                style: GoogleFonts.outfit(
                    fontSize: 12.5, height: 1.35, color: colour)),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    final breakdown = (_summary?['breakdown'] as Map?) ?? {};

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How the ratings split',
              style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Tap a row to read just those reviews.',
              style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextLight)),
          const SizedBox(height: 12),
          for (var star = 5; star >= 1; star--)
            _buildBar(star, Map<String, dynamic>.from(
                (breakdown['$star'] ?? breakdown[star] ?? {}) as Map)),
        ],
      ),
    );
  }

  Widget _buildBar(int star, Map<String, dynamic> row) {
    final count = (row['count'] as num?)?.toInt() ?? 0;
    final percent = (row['percent'] as num?)?.toInt() ?? 0;
    final active = _starFilter == star;

    return GestureDetector(
      onTap: count > 0 ? () => _toggleStar(star) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Row(
                children: [
                  Text('$star',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.bold : FontWeight.normal,
                        color: active ? AppTheme.accentColor : AppTheme.lightTextBody,
                      )),
                  const SizedBox(width: 3),
                  const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF5A623)),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 8,
                  backgroundColor: AppTheme.lightBg,
                  valueColor: AlwaysStoppedAnimation(
                      active ? AppTheme.accentColor : const Color(0xFFF5A623)),
                ),
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(count == 0 ? '—' : '$count ($percent%)',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? AppTheme.accentColor : AppTheme.lightTextLight,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  /// Filter and sort, both visible rather than hidden in a gesture.
  ///
  /// The star bars above already filter when tapped, but nothing on screen
  /// says so — an owner with a run of one-star reviews should not have to
  /// discover that by accident. These say it out loud.
  Widget _buildFilterRow() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _resultsLabel(),
                  style: GoogleFonts.outfit(
                      fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
              ),
              _buildSortButton(),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  label: 'All',
                  active: _starFilter == null && !_onlyWithComment,
                  onTap: () {
                    setState(() {
                      _starFilter = null;
                      _onlyWithComment = false;
                    });
                    _load(reset: true);
                  },
                ),
                const SizedBox(width: 8),
                // Highest first: an owner scanning for problems looks for the
                // low ones, but the common case is checking the good ones are
                // still coming in.
                for (final star in [5, 4, 3, 2, 1]) ...[
                  _filterChip(
                    label: '$star',
                    icon: Icons.star_rounded,
                    active: _starFilter == star,
                    onTap: () => _toggleStar(star),
                  ),
                  const SizedBox(width: 8),
                ],
                _filterChip(
                  label: 'With comments',
                  active: _onlyWithComment,
                  onTap: () {
                    setState(() => _onlyWithComment = !_onlyWithComment);
                    _load(reset: true);
                  },
                ),
              ],
            ),
          ),
        ],
      );

  String _resultsLabel() {
    if (_total == 0) return 'No reviews match';

    final filtered = _starFilter != null || _onlyWithComment;
    final noun = _total == 1 ? 'review' : 'reviews';

    // While more pages are outstanding, say how far through we are — a list
    // that simply stops looks like the end of the reviews rather than the end
    // of the page.
    if (_reviews.length < _total) {
      return 'Showing ${_reviews.length} of $_total $noun';
    }

    return filtered ? '$_total matching $noun' : '$_total $noun';
  }

  Widget _buildSortButton() => PopupMenuButton<String>(
        initialValue: _sort,
        onSelected: (value) {
          if (value == _sort) return;
          setState(() => _sort = value);
          _load(reset: true);
        },
        itemBuilder: (context) => _sorts.entries
            .map((entry) => PopupMenuItem(
                  value: entry.key,
                  child: Row(
                    children: [
                      Icon(
                        entry.key == _sort
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 17,
                        color: entry.key == _sort
                            ? AppTheme.accentColor
                            : AppTheme.lightTextLight,
                      ),
                      const SizedBox(width: 10),
                      Text(entry.value, style: GoogleFonts.outfit(fontSize: 13.5)),
                    ],
                  ),
                ))
            .toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_vert_rounded,
                  size: 15, color: AppTheme.accentColor),
              const SizedBox(width: 5),
              Text(
                _sorts[_sort] ?? 'Sort',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentColor),
              ),
            ],
          ),
        ),
      );

  Widget _filterChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
    IconData? icon,
  }) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppTheme.lightAccentSoft : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? AppTheme.accentColor : AppTheme.lightBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? AppTheme.accentColor : AppTheme.lightTextBody,
                  )),
              if (icon != null) ...[
                const SizedBox(width: 3),
                Icon(icon,
                    size: 13,
                    color: active
                        ? AppTheme.accentColor
                        : AppTheme.lightTextBody),
              ],
            ],
          ),
        ),
      );

  Widget _buildReviewTile(Map<String, dynamic> review) {
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
          const SizedBox(height: 8),
          _stars(rating.toDouble(), 14),
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

  Widget _stars(double rating, double size) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (index) {
          final position = index + 1;
          final icon = rating >= position
              ? Icons.star_rounded
              : rating >= position - 0.5
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded;

          return Icon(icon, size: size, color: const Color(0xFFF5A623));
        }),
      );

  Widget _buildNoMatches() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text('No reviews match that filter.',
              style: GoogleFonts.outfit(fontSize: 13.5, color: AppTheme.lightTextBody)),
        ),
      );

  Widget _buildFailed() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 44, color: AppTheme.lightTextLight),
              const SizedBox(height: 14),
              Text('Could not load your reviews.',
                  style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
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
