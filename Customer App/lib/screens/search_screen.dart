import 'dart:async';

import 'package:flutter/material.dart';

import '../services/search_service.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';
import 'salon_detail_screen.dart';
import 'category_salons_screen.dart';
import '../theme/app_colors.dart';

/// Search, answered the way a customer asks it.
///
/// People search for what they want done, not for who does it — "haircut", not
/// the name of a salon three streets away they have never heard of. So a
/// service match leads the results and carries its salon with it: the price,
/// the rating and where it is, all on the one row, so the choice can be made
/// without opening anything.
///
/// Results update as the customer types, after a short pause. Searching on
/// every keystroke would fire a request per letter; waiting for them to press
/// enter makes them do work the app can do for them.
class SearchScreen extends StatefulWidget {
  final String initialQuery;

  /// Set when the customer arrives from a category in Explore, so the search
  /// keeps answering the question that category is asking. Null for a search
  /// started from Home or the sidebar, which is deliberately unrestricted.
  final String? categoryId;
  final String? categoryLabel;

  const SearchScreen({
    super.key,
    this.initialQuery = '',
    this.categoryId,
    this.categoryLabel,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  SearchResults? _results;
  bool _searching = false;
  String? _error;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;

    if (widget.initialQuery.trim().length >= 2) {
      _run(widget.initialQuery);
    } else {
      // Arriving with an empty box means the customer came here to type.
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();

    if (value.trim().length < 2) {
      setState(() {
        _results = null;
        _error = null;
        _searching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () => _run(value));
  }

  Future<void> _run(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return;

    setState(() {
      _searching = true;
      _error = null;
      _lastQuery = trimmed;
    });

    try {
      final results = await CustomerSearchService.search(
        trimmed,
        categoryId: widget.categoryId,
      );

      // A slow response for a query the customer has already typed past must
      // not overwrite the results for what they are looking at now.
      if (!mounted || _lastQuery != trimmed) return;

      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || _lastQuery != trimmed) return;
      setState(() {
        _error = 'Could not search right now. Check your connection.';
        _searching = false;
      });
    }
  }

  void _openSalon(String salonId) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SalonDetailScreen(salonId: salonId)),
      );

  void _openCategory(CategoryHit category) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CategorySalonsScreen(
            category: ServiceCategory(
              id: category.id,
              name: category.name,
              iconUrl: category.iconUrl,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bg = context.colors.surfaceMuted;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        titleSpacing: 0,
        title: _searchField(),
      ),
      body: widget.categoryId == null
          ? _body()
          : Column(
              children: [
                _scopeStrip(),
                Expanded(child: _body()),
              ],
            ),
    );
  }

  /// Says the search is narrowed, because a customer who typed "facial" while
  /// inside Hair deserves to know why nothing came back rather than guessing.
  Widget _scopeStrip() {
    final label = widget.categoryLabel;

    if (label == null || label.isEmpty) {
      return const SizedBox.shrink();
    }

    final muted = context.colors.textTertiary;

    return Container(
      width: double.infinity,
      color: context.colors.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined, size: 15, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Searching within $label',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.search,
              size: 20,
              color: context.colors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _run,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search haircut, facial, salon…',
                hintStyle: TextStyle(
                  fontSize: 14.5,
                  color: context.colors.textTertiary,
                ),
              ),
              style: const TextStyle(fontSize: 14.5),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                _onChanged('');
                _focus.requestFocus();
              },
              child: Icon(Icons.close,
                  size: 18,
                  color: context.colors.textTertiary),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _centred(Icons.wifi_off_rounded, 'Something went wrong', _error!);
    }

    if (_controller.text.trim().length < 2) {
      return _centred(
        Icons.search,
        'What are you looking for?',
        'Search for a service like "haircut" or "facial", or type a salon name.',
      );
    }

    if (_searching && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final results = _results;
    if (results == null) return const SizedBox.shrink();

    if (results.isEmpty) {
      return _centred(
        Icons.search_off,
        'Nothing found for "${_controller.text.trim()}"',
        'Try a shorter word, or check the spelling.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        // Shown above the results rather than instead of them: the customer's
        // spelling may well have been right, so the results stay and the
        // correction is only an offer.
        if (results.didYouMean != null)
          _didYouMean(results.didYouMean!),

        if (results.categories.isNotEmpty) ...[
          _sectionTitle('Browse'),
          _categoryRow(results.categories),
        ],

        if (results.services.isNotEmpty) ...[
          _sectionTitle(
            '${results.services.length} service${results.services.length == 1 ? '' : 's'}',
          ),
          ...results.services.map((hit) => _serviceRow(hit)),
        ],

        if (results.salons.isNotEmpty) ...[
          _sectionTitle(
            '${results.salons.length} salon${results.salons.length == 1 ? '' : 's'}',
          ),
          ...results.salons.map((hit) => _salonRow(hit)),
        ],
      ],
    );
  }

  Widget _didYouMean(String suggestion) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: GestureDetector(
          onTap: () {
            _controller.text = suggestion;
            _run(suggestion);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded,
                    size: 17, color: AppTheme.accentColor),
                const SizedBox(width: 9),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13.5,
                        color: context.colors.textSecondary,
                      ),
                      children: [
                        const TextSpan(text: 'Did you mean '),
                        TextSpan(
                          text: suggestion,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentColor,
                          ),
                        ),
                        const TextSpan(text: '?'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: context.colors.textSecondary,
          ),
        ),
      );

  Widget _categoryRow(List<CategoryHit> categories) => SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: categories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final category = categories[index];
            return GestureDetector(
              onTap: () => _openCategory(category),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                      color:
                          context.colors.border),
                ),
                child: Text(
                  category.name,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
            );
          },
        ),
      );

  /// The service, and everything needed to judge it: what it costs, how long
  /// it takes, who does it, how well they are rated and where they are.
  Widget _serviceRow(ServiceHit hit) => InkWell(
        onTap: () => _openSalon(hit.salon.id),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: context.colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          '₹${hit.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentColor,
                          ),
                        ),
                        if (hit.durationMinutes > 0) ...[
                          Text(' · ${hit.durationMinutes} min',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: context.colors.textSecondary)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 9),
                    // The salon, set apart so the row reads as "this service,
                    // at this place" rather than as one run-on line.
                    Row(
                      children: [
                        Icon(Icons.storefront_outlined,
                            size: 14,
                            color: context.colors.textSecondary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            hit.salon.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (hit.salon.hasRating) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.star_rounded,
                              size: 14, color: Color(0xFFF5A623)),
                          const SizedBox(width: 2),
                          Text(
                            hit.salon.avgRating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                    if (hit.salon.area != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        hit.salon.area!,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right_rounded,
                  color: context.colors.textTertiary),
            ],
          ),
        ),
      );

  Widget _salonRow(SalonHit hit) => InkWell(
        onTap: () => _openSalon(hit.id),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: context.colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.colors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront_rounded,
                    size: 21, color: AppTheme.accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (hit.hasRating) ...[
                          const Icon(Icons.star_rounded,
                              size: 14, color: Color(0xFFF5A623)),
                          const SizedBox(width: 2),
                          Text(
                            '${hit.avgRating.toStringAsFixed(1)} (${hit.reviewCount})',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ] else
                          Text('New',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: context.colors.textTertiary)),
                        if (hit.area != null) ...[
                          Text(' · ${hit.area}',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: context.colors.textSecondary)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: context.colors.textTertiary),
            ],
          ),
        ),
      );

  Widget _centred(IconData icon, String title, String detail) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 46,
                  color: context.colors.textTertiary),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color:
                      context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}
