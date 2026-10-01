import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/location_service.dart';
import '../widgets/city_picker_sheet.dart';
import '../services/salon_service.dart';
import 'salon_detail_screen.dart';
import '../theme/app_colors.dart';
import '../utils/error_text.dart';
import '../widgets/feedback_states.dart';
import '../widgets/skeleton.dart';

class SalonListScreen extends StatefulWidget {
  final String? initialSearch;
  final String? initialGender;
  final String? initialCategoryId;
  final String title;

  const SalonListScreen({
    Key? key,
    this.initialSearch,
    this.initialGender,
    this.initialCategoryId,
    required this.title,
  }) : super(key: key);

  @override
  _SalonListScreenState createState() => _SalonListScreenState();
}

class _SalonListScreenState extends State<SalonListScreen> {
  final SalonService _salonService = SalonService();
  List<dynamic> _salons = [];
  List<dynamic> _suggestedSalons = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadSalons();
  }

  Future<void> _loadSalons() async {
    try {
      final response = await _salonService.fetchSalons(
        search: widget.initialSearch,
        gender: widget.initialGender,
        categoryId: widget.initialCategoryId,
      );
      if (!mounted) return;
      setState(() {
        _salons = response['salons'] ?? [];
        _suggestedSalons = response['suggested_salons'] ?? [];
        _error = '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, fallback: 'We could not load salons.');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: Theme.of(context).appBarTheme.titleTextStyle),
        centerTitle: true,
      ),
      body: _isLoading
          ? SkeletonList(
              padding: const EdgeInsets.all(20),
              itemBuilder: (_) => const CompactSalonCardSkeleton(),
            )
          // Prices and availability change while someone browses; pulling
          // down is the obvious way to ask for the latest.
          : RefreshIndicator(
              color: AppTheme.accentColor,
              onRefresh: _loadSalons,
              child: _error.isNotEmpty
                  ? ScrollableState(
                      child: ErrorState(
                        title: 'Could not load salons',
                        message: _error,
                        onRetry: _retry,
                      ),
                    )
                  : _salons.isEmpty
                      ? _buildEmptyOrSuggestions()
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                          itemCount: _salons.length,
                          separatorBuilder: (context, index) => SizedBox(height: 16),
                          itemBuilder: (context, index) => _buildSalonItem(_salons[index]),
                        ),
            ),
    );
  }

  /// Back to the skeleton, then reload: a retry should look like one.
  void _retry() {
    setState(() => _isLoading = true);
    _loadSalons();
  }

  Widget _buildEmptyOrSuggestions() {
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty && _suggestedSalons.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 8),
            child: Text(
              LocationService.instance.hasCity
                  ? 'No match in ${LocationService.instance.city!.name}.'
                  : 'No exact match found.',
              style: GoogleFonts.outfit(color: context.colors.danger, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Here are some nearby salons you might like:',
              style: GoogleFonts.outfit(color: context.colors.textSecondary, fontSize: 14),
            ),
          ),
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              itemCount: _suggestedSalons.length,
              separatorBuilder: (context, index) => SizedBox(height: 16),
              itemBuilder: (context, index) => _buildSalonItem(_suggestedSalons[index]),
            ),
          ),
        ],
      );
    }

    // Naming the city matters here: searching is city-scoped, so "nothing
    // found" without it reads as "this salon does not exist" rather than
    // "not in the city you are looking at".
    return ScrollableState(
      child: EmptyState(
        icon: Icons.search_off,
        title: LocationService.instance.hasCity
            ? 'No salons found in ${LocationService.instance.city!.name}.'
            : 'No salons found.',
        message: 'Try a different search, or change your city.',
        actionLabel: 'Change city',
        onAction: () async {
          final changed = await showCityPicker(context);
          if (changed && mounted) _retry();
        },
      ),
    );
  }

  Widget _buildSalonItem(dynamic salon) {
    final isServiceable = salon['is_serviceable'] != false;

    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => SalonDetailScreen(salonId: salon['id'].toString())
        ));
      },
      child: Opacity(
        opacity: isServiceable ? 1.0 : 0.6,
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.colors.border),
            boxShadow: [
              BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), blurRadius: 10, offset: Offset(0, 4))
            ]
          ),
          child: Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: context.colors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 40),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(salon['name'] ?? 'Unnamed Salon', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: context.colors.textSecondary),
                        SizedBox(width: 4),
                        Expanded(child: Text(salon['address'] ?? 'No address provided', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(color: context.colors.textSecondary, fontSize: 13))),
                      ],
                    ),
                    SizedBox(height: 8),
                    if (!isServiceable)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: context.colors.warningBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          salon['unavailable_reason'] ?? 'Not taking bookings right now',
                          style: GoogleFonts.outfit(
                              color: context.colors.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      Builder(
                        builder: (_) {
                          // Real figures rather than a placeholder that claimed
                          // every salon was 4.5 from 120 reviews.
                          final count = (salon['review_count'] as num?)?.toInt() ?? 0;
                          final avg = (salon['avg_rating'] as num?)?.toDouble() ?? 0;

                          if (count == 0) {
                            return Text('New salon',
                                style: GoogleFonts.outfit(color: context.colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600));
                          }

                          return Row(
                            children: [
                              Icon(Icons.star, size: 14, color: AppTheme.starRating),
                              SizedBox(width: 4),
                              Text('${avg.toStringAsFixed(1)} ($count ${count == 1 ? 'review' : 'reviews'})',
                                  style: GoogleFonts.outfit(color: context.colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          );
                        },
                      )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
