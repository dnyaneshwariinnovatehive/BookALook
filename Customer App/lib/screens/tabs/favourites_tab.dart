import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_restricted_view.dart';
import '../../services/salon_service.dart';
import '../salon_detail_screen.dart';

class FavouritesTab extends StatefulWidget {
  final bool isGuest;

  const FavouritesTab({Key? key, required this.isGuest}) : super(key: key);

  @override
  _FavouritesTabState createState() => _FavouritesTabState();
}

class _FavouritesTabState extends State<FavouritesTab> {
  final SalonService _salonService = SalonService();
  List<dynamic> _favourites = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadFavourites();
    }
  }

  Future<void> _loadFavourites() async {
    try {
      final favourites = await _salonService.fetchFavourites();
      if (mounted) {
        setState(() {
          _favourites = favourites;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) {
      return GuestRestrictedView(
        title: 'Sign In Required',
        message: 'Please sign in to view your favorite salons.',
        icon: Icons.favorite_border,
      );
    }

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.accentColor));
    }

    if (_error.isNotEmpty) {
      return Center(child: Text(_error, style: GoogleFonts.outfit(color: AppTheme.lightDanger)));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(20),
              child: Text('My Favourites', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
            ),
            Expanded(
              child: _favourites.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.favorite_border, size: 80, color: Theme.of(context).dividerColor),
                            SizedBox(height: 24),
                            Text(
                              'No Favourites Yet',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Tap the heart icon on salons you love to save them here.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.accentColor,
                      onRefresh: _loadFavourites,
                      child: ListView.separated(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: _favourites.length,
                        separatorBuilder: (context, index) => SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final salon = _favourites[index];
                          final isServiceable = salon['is_serviceable'] != false;
                          
                          // Parse rating
                          final rating = salon['rating'] ?? {};
                          final ratingCount = (rating['count'] ?? 0) as int;
                          final ratingAvg = (rating['average'] ?? 0.0);
                          final double avgVal = ratingAvg is int ? ratingAvg.toDouble() : (ratingAvg is double ? ratingAvg : double.tryParse(ratingAvg.toString()) ?? 0.0);

                          return InkWell(
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (context) => SalonDetailScreen(salonId: salon['id'].toString())
                              )).then((_) {
                                // Refresh favorites when returning from detail screen
                                _loadFavourites();
                              });
                            },
                            child: Opacity(
                              opacity: isServiceable ? 1.0 : 0.6,
                              child: Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.lightSurface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.lightBorder),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 4))
                                  ]
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: AppTheme.lightAccentSoft,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 40),
                                    ),
                                    SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(salon['name'] ?? 'Unnamed Salon', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
                                          SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.location_on, size: 14, color: AppTheme.lightTextBody),
                                              SizedBox(width: 4),
                                              Expanded(child: Text(salon['address'] ?? 'No address provided', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 13))),
                                            ],
                                          ),
                                          SizedBox(height: 8),
                                          if (!isServiceable)
                                            Container(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: AppTheme.lightWarningBg,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                salon['unavailable_reason'] ?? 'Not taking bookings right now',
                                                style: GoogleFonts.outfit(
                                                    color: AppTheme.lightWarning,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600),
                                              ),
                                            )
                                          else if (ratingCount > 0)
                                            Row(
                                              children: [
                                                Icon(Icons.star, size: 14, color: AppTheme.starRating),
                                                SizedBox(width: 4),
                                                Text('${avgVal.toStringAsFixed(1)} ($ratingCount reviews)', style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 12, fontWeight: FontWeight.w600)),
                                              ],
                                            )
                                          else
                                            Text('New Salon', style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 12, fontWeight: FontWeight.w600))
                                        ],
                                      ),
                                    )
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
