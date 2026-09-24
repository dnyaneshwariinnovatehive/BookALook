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
  FavouritesTabState createState() => FavouritesTabState();
}

class FavouritesTabState extends State<FavouritesTab> {
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

  Future<void> loadFavourites() => _loadFavourites();

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

  Future<void> _removeFavourite(String salonId) async {
    // Optimistic UI update
    final int index = _favourites.indexWhere((s) => s['id'].toString() == salonId);
    if (index == -1) return;
    
    final removedItem = _favourites[index];
    setState(() {
      _favourites.removeAt(index);
    });
    
    try {
      await _salonService.toggleFavourite(salonId);
    } catch (e) {
      // Revert if failed
      if (mounted) {
        setState(() {
          _favourites.insert(index, removedItem);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove favourite: $e', style: GoogleFonts.outfit()),
            backgroundColor: AppTheme.lightDanger,
          )
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) {
      return GuestRestrictedView(
        title: 'Sign In Required',
        message: 'Please sign in to view your favorite salons.',
        tabIndex: 3,
        icon: Icons.favorite_border,
      );
    }

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.accentColor));
    }

    if (_error.isNotEmpty) {
      return Center(child: Text(_error, style: GoogleFonts.outfit(color: AppTheme.lightDanger)));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFFBF9FF),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Text('My Favourites', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: headingColor)),
            ),
            Expanded(
              child: _favourites.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: borderColor),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 12, offset: Offset(0, 4))
                                ]
                              ),
                              child: Icon(Icons.favorite_border, size: 64, color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight),
                            ),
                            SizedBox(height: 24),
                            Text(
                              'No Favourites Yet',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: headingColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Tap the heart icon on salons you love to save them here.',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: bodyColor,
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
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(20, 4, 20, 90),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.8, // adjust as needed for image+text
                        ),
                        itemCount: _favourites.length,
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
                              )).then((_) => _loadFavourites());
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
                                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: Offset(0, 4))
                                  ]
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.network(
                                            salon['cover_image'] ?? salon['cover_photo_url'] ?? salon['logo_image'] ?? '',
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(color: isDark ? AppTheme.darkAccentSoft : const Color(0xFFF3F0FF), child: Icon(Icons.storefront, color: AppTheme.accentColor)),
                                          ),
                                          if (salon['distance_km'] != null)
                                            Positioned(
                                              bottom: 8,
                                              left: 8,
                                              child: Container(
                                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(6)),
                                                child: Text(
                                                  '${salon['distance_km']} km',
                                                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                            ),
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: InkWell(
                                              onTap: () => _removeFavourite(salon['id'].toString()),
                                              child: Container(
                                                padding: EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: isDark ? AppTheme.darkSurface : Colors.white,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: Offset(0, 2))
                                                  ]
                                                ),
                                                child: Icon(Icons.favorite, size: 16, color: AppTheme.lightDanger),
                                              ),
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(child: Text(salon['name'] ?? 'Unnamed Salon', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: headingColor))),
                                            ],
                                          ),
                                          SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (ratingCount > 0) ...[
                                                Icon(Icons.star, size: 12, color: AppTheme.starRating),
                                                SizedBox(width: 4),
                                                Text(avgVal.toStringAsFixed(1), style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: headingColor)),
                                              ] else
                                                Text('New Salon', style: GoogleFonts.outfit(color: bodyColor, fontSize: 12, fontWeight: FontWeight.w600)),
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
