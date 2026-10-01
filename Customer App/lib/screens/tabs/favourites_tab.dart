import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_restricted_view.dart';
import '../../services/salon_service.dart';
import '../salon_detail_screen.dart';
import '../../theme/app_colors.dart';
import '../../services/explore_request_bus.dart';
import '../../utils/error_text.dart';
import '../../widgets/feedback_states.dart';
import '../../widgets/skeleton.dart';
import '../../utils/bottom_clearance.dart';

class FavouritesTab extends StatefulWidget {
  final bool isGuest;

  const FavouritesTab({Key? key, required this.isGuest}) : super(key: key);

  @override
  FavouritesTabState createState() => FavouritesTabState();
}

class FavouritesTabState extends State<FavouritesTab> {
  final SalonService _salonService = SalonService();
  List<dynamic> _favourites = [];
  bool _isLoading = true;
  String _error = '';

  /// A failed un-favourite, shown above the grid (the card is put back).
  String? _actionError;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadFavourites();
    }
  }

  Future<void> loadFavourites() => _loadFavourites();

  Future<void> _loadFavourites() async {
    try {
      final favourites = await _salonService.fetchFavourites();
      if (mounted) {
        setState(() {
          _favourites = favourites;
          _error = '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeError(e, fallback: 'We could not load your favourites.');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _removeFavourite(String salonId) async {
    // Optimistic UI update
    final int index = _favourites.indexWhere(
      (s) => s['id'].toString() == salonId,
    );
    if (index == -1) return;

    final removedItem = _favourites[index];
    setState(() {
      _favourites.removeAt(index);
    });

    try {
      await _salonService.toggleFavourite(salonId);
      if (mounted && _actionError != null) setState(() => _actionError = null);
    } catch (e) {
      // Revert if failed
      if (mounted) {
        setState(() {
          _favourites.insert(index, removedItem);
        });
        setState(() => _actionError = describeError(e,
            fallback: 'Could not remove that salon from your favourites.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) {
      return GuestRestrictedView(
        title: 'Sign In Required',
        message: 'Please sign in to view your favorite salons.',
        // No longer a tab of its own, so signing in returns to the profile that
        // this screen was reached from.
        tabIndex: 3,
        icon: Icons.favorite_border,
      );
    }

    // Loading and failure get the same page and header as the list, instead
    // of a bare widget with no Scaffold under it.
    if (_isLoading || _error.isNotEmpty) {
      return Scaffold(
        backgroundColor: context.colors.pageTint,
        appBar: AppBar(
          backgroundColor: context.colors.pageTint,
          title: const Text('My Favourites'),
        ),
        body: _isLoading
            ? Skeleton(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: 4,
                  itemBuilder: (_, _) => const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: SkeletonBox(height: double.infinity, radius: 16)),
                      SizedBox(height: 10),
                      SkeletonLine(widthFactor: 0.8, height: 14),
                      SizedBox(height: 6),
                      SkeletonLine(widthFactor: 0.5),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                color: AppTheme.accentColor,
                onRefresh: _loadFavourites,
                child: ScrollableState(
                  child: ErrorState(
                    title: 'Could not load your favourites',
                    message: _error,
                    onRetry: () {
                      setState(() => _isLoading = true);
                      _loadFavourites();
                    },
                  ),
                ),
              ),
      );
    }

    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;

    return Scaffold(
      backgroundColor: context.colors.pageTint,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 20, 16),
              child: Row(
                children: [
                  // Reached from the profile rather than from the footer, so it
                  // carries its own way back.
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppTheme.accentColor,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'My Favourites',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: headingColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_actionError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: InlineStatus(
                  message: _actionError!,
                  onDismiss: () => setState(() => _actionError = null),
                ),
              ),
            Expanded(
              child: _favourites.isEmpty
                  ? EmptyState(
                      icon: Icons.favorite_border,
                      title: 'No Favourites Yet',
                      message: 'Tap the heart icon on salons you love to save them here.',
                      actionLabel: 'Explore salons',
                      onAction: ExploreRequestBus.instance.showAll,
                    )
                  : RefreshIndicator(
                      color: AppTheme.accentColor,
                      onRefresh: _loadFavourites,
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(20, 4, 20, bottomClearance(context)),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio:
                              0.8, // adjust as needed for image+text
                        ),
                        itemCount: _favourites.length,
                        itemBuilder: (context, index) {
                          final salon = _favourites[index];
                          final isServiceable =
                              salon['is_serviceable'] != false;

                          // Parse rating
                          final rating = salon['rating'] ?? {};
                          final ratingCount = (rating['count'] ?? 0) as int;
                          final ratingAvg = (rating['average'] ?? 0.0);
                          final double avgVal = ratingAvg is int
                              ? ratingAvg.toDouble()
                              : (ratingAvg is double
                                    ? ratingAvg
                                    : double.tryParse(ratingAvg.toString()) ??
                                          0.0);

                          return InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SalonDetailScreen(
                                    salonId: salon['id'].toString(),
                                  ),
                                ),
                              ).then((_) => _loadFavourites());
                            },
                            child: Opacity(
                              opacity: isServiceable ? 1.0 : 0.6,
                              child: Container(
                                clipBehavior: Clip.hardEdge,
                                decoration: BoxDecoration(
                                  color: surfaceColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withValues(alpha: 0.03),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.network(
                                            salon['cover_image'] ??
                                                salon['cover_photo_url'] ??
                                                salon['logo_image'] ??
                                                '',
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                                  color: context.colors.imagePlaceholder,
                                                  child: Icon(
                                                    Icons.storefront,
                                                    color: AppTheme.accentColor,
                                                  ),
                                                ),
                                          ),
                                          if (salon['distance_km'] != null)
                                            Positioned(
                                              bottom: 8,
                                              left: 8,
                                              child: Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.7),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  '${salon['distance_km']} km',
                                                  style: GoogleFonts.outfit(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: InkWell(
                                              onTap: () => _removeFavourite(
                                                salon['id'].toString(),
                                              ),
                                              child: Container(
                                                padding: EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: context.colors.surface,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface
                                                          .withValues(alpha: 0.1),
                                                      blurRadius: 4,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Icon(
                                                  Icons.favorite,
                                                  size: 16,
                                                  color: context.colors.danger,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  salon['name'] ??
                                                      'Unnamed Salon',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: headingColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (ratingCount > 0) ...[
                                                Icon(
                                                  Icons.star,
                                                  size: 12,
                                                  color: AppTheme.starRating,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  avgVal.toStringAsFixed(1),
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: headingColor,
                                                  ),
                                                ),
                                              ] else
                                                Text(
                                                  'New Salon',
                                                  style: GoogleFonts.outfit(
                                                    color: bodyColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
