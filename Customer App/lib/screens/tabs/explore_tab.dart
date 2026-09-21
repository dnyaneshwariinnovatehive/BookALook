import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/salon_service.dart';
import '../../services/appointment_service.dart';
import '../salon_detail_screen.dart';
import '../../services/cart_service.dart';
import '../../services/location_service.dart';
import '../../widgets/city_picker_sheet.dart';
import '../cart_screen.dart';
import '../salon_list_screen.dart';

class ExploreTab extends StatefulWidget {
  @override
  _ExploreTabState createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  final SalonService _salonService = SalonService();
  final AppointmentService _appointmentService = AppointmentService();
  List<dynamic> _salons = [];
  List<dynamic> _mostVisitedSalons = [];
  bool _isLoading = true;
  String _error = '';

  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All Salons';

  final CartService _cartService = CartService();
  Map<String, dynamic>? _globalCart;

  /// When this city has nothing in it, the directory hands back somewhere that
  /// does, rather than leaving the customer on an empty screen.
  List<dynamic> _suggested = [];
  Map<String, dynamic>? _suggestedCity;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    LocationService.instance.addListener(_onCityChanged);
  }

  @override
  void dispose() {
    LocationService.instance.removeListener(_onCityChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await LocationService.instance.restore();
    await _loadSalons();
  }

  void _onCityChanged() {
    if (!mounted) return;
    setState(() => _isLoading = true);
    _loadSalons();
  }

  Future<void> _pickCity() async => showCityPicker(context);

  Future<void> _loadSalons() async {
    try {
      final response = await _salonService.fetchSalons();
      final salons = response['salons'] ?? [];
      final globalCart = await _cartService.getGlobalCart();
      
      // Fetch past bookings to determine 'Most Visited'
      List<dynamic> mostVisited = [];
      try {
        final bookings = await _appointmentService.getMyBookings();
        final past = (bookings['past'] as List?) ?? [];
        
        // Count salon visits
        final Map<String, int> visitCounts = {};
        final Map<String, dynamic> salonData = {};
        for (var booking in past) {
          final sId = booking['salon_id']?.toString();
          if (sId != null && booking['salon'] != null) {
            visitCounts[sId] = (visitCounts[sId] ?? 0) + 1;
            salonData[sId] = booking['salon'];
          }
        }
        
        // Sort by visits and take top 5
        final sortedKeys = visitCounts.keys.toList()
          ..sort((a, b) => visitCounts[b]!.compareTo(visitCounts[a]!));
        for (var key in sortedKeys.take(5)) {
          mostVisited.add(salonData[key]);
        }
      } catch (_) {
        // Ignore errors for most visited
      }

      if (!mounted) return;
      setState(() {
        _salons = salons;
        _mostVisitedSalons = mostVisited;
        _suggested = response['suggested_salons'] ?? [];
        _suggestedCity = response['suggested_city'] as Map<String, dynamic>?;
        _globalCart = globalCart;
        _isLoading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _navigateToSearch() {
    if (_searchController.text.trim().isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SalonListScreen(
          initialSearch: _searchController.text,
          title: 'Search Results',
        ),
      )
    );
  }

  List<dynamic> get _filteredSalons {
    if (_selectedFilter == 'Open Now') {
      return _salons.where((s) => s['is_serviceable'] != false).toList();
    } else if (_selectedFilter == 'Top Rated (4.8+)') {
      return _salons.where((s) {
        final avg = (s['avg_rating'] as num?)?.toDouble() ?? 0;
        return avg >= 4.8;
      }).toList();
    } else if (_selectedFilter == 'Top Rated (4.5+)') {
      return _salons.where((s) {
        final avg = (s['avg_rating'] as num?)?.toDouble() ?? 0;
        return avg >= 4.5;
      }).toList();
    }
    return _salons;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.accentColor));
    }
    if (_error.isNotEmpty) {
      return Center(child: Text(_error, style: GoogleFonts.outfit(color: AppTheme.lightDanger)));
    }

    final filteredSalons = _filteredSalons;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFFBF9FF),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 16),
              _buildHeader(),
              SizedBox(height: 20),
              _buildFilters(),
              
              if (_mostVisitedSalons.isNotEmpty) ...[
                SizedBox(height: 28),
                _buildSectionTitle('Most Visited by You', null),
                SizedBox(height: 16),
                _buildMostVisited(),
              ],
              
              // Top Rated Combos Near You
              ..._buildCombosSection(),

              SizedBox(height: 28),
              _buildSectionTitle('All Salons near you', '(${filteredSalons.length})'),
              SizedBox(height: 16),
              
              if (filteredSalons.isEmpty) 
                _buildEmptyCity()
              else
                _buildAllSalons(filteredSalons),
                
              SizedBox(height: 90),
            ],
          ),
        ),
      ),
      floatingActionButton: _globalCart != null && (_globalCart!['items'] as List).isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => CartScreen()
                )).then((_) => _loadSalons());
              },
              backgroundColor: AppTheme.accentColor,
              icon: Icon(Icons.shopping_cart, color: Colors.white),
              label: Text('View Cart (${_globalCart!['salon']?['name'] ?? 'Cart'})', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: Offset(0, 2))
          ]
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.outfit(fontSize: 14, color: headingColor),
                decoration: InputDecoration(
                  hintText: 'Search salons or services...',
                  hintStyle: GoogleFonts.outfit(color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => _navigateToSearch(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    final filters = ['All Salons', 'Open Now', 'Top Rated (4.8+)', 'Top Rated (4.5+)'];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length + 1,
        separatorBuilder: (_, __) => SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            final cityName = LocationService.instance.city?.name ?? 'Select City';
            return InkWell(
              onTap: _pickCity,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: Offset(0, 2))
                  ]
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: bodyColor),
                    SizedBox(width: 4),
                    Text(
                      cityName,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: bodyColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final filter = filters[index - 1];
          final isSelected = _selectedFilter == filter;
          return InkWell(
            onTap: () => setState(() => _selectedFilter = filter),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.accentColor : borderColor,
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: Offset(0, 2))
                ]
              ),
              child: Text(
                filter,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? AppTheme.accentColor : bodyColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title, String? subtitle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: headingColor)),
          if (subtitle != null) ...[
            SizedBox(width: 6),
            Text(subtitle, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: bodyColor)),
          ],
        ],
      ),
    );
  }

  Widget _buildMostVisited() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return SizedBox(
      height: 170,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _mostVisitedSalons.length,
        separatorBuilder: (_, __) => SizedBox(width: 16),
        itemBuilder: (context, index) {
          final salon = _mostVisitedSalons[index];
          final avg = (salon['avg_rating'] as num?)?.toDouble() ?? 0;
          return InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalonDetailScreen(salonId: salon['id'].toString()))),
            child: Container(
              width: 160,
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
                            right: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                '${salon['distance_km']} km',
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
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
                            Expanded(child: Text(salon['name'] ?? 'Salon', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: headingColor))),
                            Icon(Icons.star, size: 12, color: AppTheme.starRating),
                            SizedBox(width: 2),
                            Text(avg > 0 ? avg.toStringAsFixed(1) : 'New', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: headingColor)),
                          ],
                        ),
                        SizedBox(height: 2),
                        Text(salon['address'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 11, color: bodyColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildCombosSection() {
    final List<Map<String, dynamic>> allCombos = [];
    for (var salon in _salons) {
      if (salon['combos'] != null && salon['combos'] is List) {
        for (var combo in salon['combos']) {
          final enrichedCombo = Map<String, dynamic>.from(combo);
          enrichedCombo['salon_name'] = salon['name'];
          enrichedCombo['salon_rating'] = salon['avg_rating'];
          enrichedCombo['salon_id'] = salon['id'];
          enrichedCombo['cover_image'] = salon['cover_image'] ?? salon['cover_photo_url'] ?? salon['logo_image'];
          allCombos.add(enrichedCombo);
        }
      }
    }

    if (allCombos.isEmpty) return [];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final lightTextColor = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;

    return [
      SizedBox(height: 28),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top Rated Combos Near You', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: headingColor)),
            SizedBox(height: 2),
            Text('Save more with bundled services', style: GoogleFonts.outfit(fontSize: 13, color: lightTextColor)),
          ],
        ),
      ),
      SizedBox(height: 16),
      SizedBox(
        height: 270,
        child: ListView.separated(
          padding: EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          itemCount: allCombos.length,
          separatorBuilder: (_, __) => SizedBox(width: 16),
          itemBuilder: (context, index) {
            final combo = allCombos[index];
            final avg = (combo['salon_rating'] as num?)?.toDouble() ?? 0;
            return Container(
              width: 240,
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
                          combo['cover_image'] ?? '',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: isDark ? AppTheme.darkAccentSoft : const Color(0xFFF3F0FF), child: Icon(Icons.storefront, color: AppTheme.accentColor)),
                        ),
                        if (combo['discount_percent'] != null && combo['discount_percent'] > 0)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                'SAVE ${combo['discount_percent']}%',
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(combo['salon_name'] ?? 'Salon', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600))),
                            Icon(Icons.star, size: 12, color: AppTheme.starRating),
                            SizedBox(width: 2),
                            Text(avg > 0 ? avg.toStringAsFixed(1) : 'New', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: headingColor)),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(combo['name'] ?? 'Combo', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: headingColor)),
                        SizedBox(height: 6),
                        Row(
                          children: [
                            Text('₹${combo['price'] ?? 0}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                            SizedBox(width: 10),
                            Icon(Icons.access_time, size: 12, color: bodyColor),
                            SizedBox(width: 4),
                            Text('${combo['duration_minutes'] ?? 60} mins', style: GoogleFonts.outfit(fontSize: 11, color: bodyColor)),
                          ],
                        ),
                        if (combo['description'] != null) ...[
                          SizedBox(height: 6),
                          Text(combo['description'], maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 11, color: lightTextColor)),
                        ],
                        SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalonDetailScreen(salonId: combo['salon_id'].toString()))),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? AppTheme.darkButtonBg : AppTheme.accentColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: EdgeInsets.symmetric(vertical: 10)
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Book Combo', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                                SizedBox(width: 6),
                                Icon(Icons.arrow_forward, size: 16),
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      )
    ];
  }

  Widget _buildAllSalons(List<dynamic> salons) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final lightTextColor = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: salons.map((salon) {
          final isServiceable = salon['is_serviceable'] != false;
          final count = (salon['review_count'] as num?)?.toInt() ?? 0;
          final avg = (salon['avg_rating'] as num?)?.toDouble() ?? 0;

          return Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: InkWell(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => SalonDetailScreen(salonId: salon['id'].toString())
                ));
              },
              child: Opacity(
                opacity: isServiceable ? 1.0 : 0.6,
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: Offset(0, 4))
                    ]
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Image on the left
                        SizedBox(
                          width: 110,
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
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(6)),
                                  child: Text(
                                    '${salon['distance_is_approximate'] == true ? '~' : ''}${salon['distance_km']} km',
                                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              )
                          ],
                        ),
                      ),
                      // Details on the right
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      salon['name'] ?? 'Unnamed Salon',
                                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: headingColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (count > 0) ...[
                                    Icon(Icons.star, size: 14, color: AppTheme.starRating),
                                    SizedBox(width: 4),
                                    Text(avg.toStringAsFixed(1), style: GoogleFonts.outfit(color: headingColor, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ] else
                                    Text('New', style: GoogleFonts.outfit(color: bodyColor, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 13, color: bodyColor),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      salon['address'] ?? 'No address',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(color: bodyColor, fontSize: 12)
                                    )
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              if (!isServiceable)
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppTheme.darkWarningBg : AppTheme.lightWarningBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    salon['unavailable_reason'] ?? 'Not taking bookings',
                                    style: GoogleFonts.outfit(color: isDark ? AppTheme.darkWarning : AppTheme.lightWarning, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                )
                              else
                                Text(
                                  'Tap to view services \u2192',
                                  style: GoogleFonts.outfit(color: AppTheme.accentColor, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyCity() {
    final cityName = LocationService.instance.city?.name;
    final suggestedName = _suggestedCity?['name'];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return Column(
      children: [
        SizedBox(height: 40),
        Icon(Icons.storefront_outlined, size: 56, color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          cityName == null ? 'No salons found' : 'No salons in $cityName yet',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: headingColor),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'We are adding salons all the time. Try another city in the meantime.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: bodyColor, fontSize: 13),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _pickCity,
          icon: const Icon(Icons.location_on, size: 18),
          label: const Text('Change city'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
        ),
        
        if (_suggested.isNotEmpty) ...[
          const SizedBox(height: 40),
          Text(
            suggestedName == null ? 'You might like these' : 'Popular in $suggestedName',
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: headingColor),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: _suggested.map((salon) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SalonDetailScreen(salonId: salon['id'].toString()))),
                      tileColor: surfaceColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: borderColor),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
                        child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 20),
                      ),
                      title: Text(salon['name'] ?? 'Unnamed Salon', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: headingColor)),
                      subtitle: Text(salon['address'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 12, color: bodyColor)),
                    ),
                  )).toList(),
            ),
          )
        ],
      ],
    );
  }
}
