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
import '../search_screen.dart';

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
  bool _isCardView = true;

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
        builder: (context) => SearchScreen(initialQuery: _searchController.text),
      ),
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
                _buildHorizontalSalonList(_mostVisitedSalons),
              ],
              
              ..._buildTopRatedSalons(filteredSalons),

              SizedBox(height: 28),
              _buildAllSalonsHeader(filteredSalons.length),
              SizedBox(height: 16),
              
              if (filteredSalons.isEmpty) 
                _buildEmptyCity()
              else
                _buildAllSalons(filteredSalons),
                
              SizedBox(height: 140),
            ],
          ),
        ),
      ),
      floatingActionButton: _globalCart != null && (_globalCart!['items'] as List).isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(bottom: 95.0),
              child: FloatingActionButton.extended(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (context) => CartScreen()
                  )).then((_) => _loadSalons());
                },
                backgroundColor: AppTheme.accentColor,
                icon: Icon(Icons.shopping_cart, color: Colors.white),
                label: Text('View Cart (${_globalCart!['salon']?['name'] ?? 'Cart'})', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
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
        height: 50,
        padding: EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.02), blurRadius: 10, offset: Offset(0, 2))
          ]
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.outfit(fontSize: 15, color: headingColor),
                decoration: InputDecoration(
                  hintText: 'Search salons or services...',
                  hintStyle: GoogleFonts.outfit(color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight, fontSize: 15),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
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
      height: 38,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length + 1,
        separatorBuilder: (_, __) => SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            final cityName = LocationService.instance.city?.name ?? 'Select City';
            return InkWell(
              onTap: _pickCity,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.01), blurRadius: 4, offset: Offset(0, 2))
                  ]
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: bodyColor),
                    SizedBox(width: 6),
                    Text(
                      cityName,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
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
              padding: EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? (isDark ? AppTheme.accentColor.withOpacity(0.15) : AppTheme.lightAccentSoft) : surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.accentColor : borderColor,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.01), blurRadius: 4, offset: Offset(0, 2))
                ]
              ),
              child: Text(
                filter,
                style: GoogleFonts.outfit(
                  fontSize: 14,
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

  List<Widget> _buildTopRatedSalons(List<dynamic> salons) {
    List<dynamic> topRated = List.from(salons)..sort((a, b) {
      final avgA = (a['avg_rating'] as num?)?.toDouble() ?? 0;
      final avgB = (b['avg_rating'] as num?)?.toDouble() ?? 0;
      return avgB.compareTo(avgA); // descending
    });
    
    topRated = topRated.where((s) {
      final avg = (s['avg_rating'] as num?)?.toDouble() ?? 0;
      return avg >= 4.0; 
    }).take(8).toList();

    if (topRated.isEmpty) return [];

    return [
      SizedBox(height: 28),
      _buildSectionTitle('Top Rated Salons', null),
      SizedBox(height: 16),
      _buildHorizontalSalonList(topRated),
    ];
  }

  Widget _buildHorizontalSalonList(List<dynamic> salonsList) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return SizedBox(
      height: 195, 
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: salonsList.length,
        separatorBuilder: (_, __) => SizedBox(width: 16),
        itemBuilder: (context, index) {
          final salon = salonsList[index];
          final avg = (salon['avg_rating'] as num?)?.toDouble() ?? 0;
          return InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalonDetailScreen(salonId: salon['id'].toString()))),
            child: Container(
              width: 220,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 1.5),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04), blurRadius: 12, offset: Offset(0, 4))
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
                          errorBuilder: (_, __, ___) => Container(color: isDark ? AppTheme.darkAccentSoft : const Color(0xFFF3F0FF), child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 30)),
                        ),
                        if (salon['distance_km'] != null)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75), borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                '${salon['distance_is_approximate'] == true ? '~' : ''}${salon['distance_km']} km',
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(salon['name'] ?? 'Salon', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: headingColor))),
                            Icon(Icons.star, size: 14, color: AppTheme.starRating),
                            SizedBox(width: 4),
                            Text(avg > 0 ? avg.toStringAsFixed(1) : 'New', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: headingColor)),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 12, color: bodyColor),
                            SizedBox(width: 4),
                            Expanded(child: Text(salon['address'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 13, color: bodyColor))),
                          ]
                        ),
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

  Widget _buildAllSalonsHeader(int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text('All Salons near you', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: headingColor)),
                SizedBox(width: 6),
                Text('($count)', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: bodyColor)),
              ],
            ),
          ),
          _buildViewToggle(),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final activeBg = AppTheme.accentColor;
    final activeIcon = Colors.white;
    final inactiveIcon = isDark ? AppTheme.darkTextLight : const Color(0xFF9E98AE);

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isCardView = true),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: _isCardView ? activeBg : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.grid_view_rounded, size: 18, color: _isCardView ? activeIcon : inactiveIcon),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isCardView = false),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: !_isCardView ? activeBg : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.format_list_bulleted_rounded, size: 18, color: !_isCardView ? activeIcon : inactiveIcon),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllSalons(List<dynamic> salons) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: salons.map((salon) => _isCardView ? _buildDetailedSalonCard(salon) : _buildCompactSalonCard(salon)).toList(),
      ),
    );
  }

  Widget _buildDetailedSalonCard(dynamic salon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final isServiceable = salon['is_serviceable'] != false;
    final count = (salon['review_count'] as num?)?.toInt() ?? 0;
    final avg = (salon['avg_rating'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: EdgeInsets.only(bottom: 20),
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
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04), blurRadius: 12, offset: Offset(0, 4))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 180,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        salon['cover_image'] ?? salon['cover_photo_url'] ?? salon['logo_image'] ?? '',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: isDark ? AppTheme.darkAccentSoft : const Color(0xFFF3F0FF), child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 40)),
                      ),
                      if (salon['distance_km'] != null)
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75), borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              '${salon['distance_is_approximate'] == true ? '~' : ''}${salon['distance_km']} km',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkSurface.withOpacity(0.9) : Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.favorite_border, size: 18, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              salon['name'] ?? 'Unnamed Salon',
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: headingColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (count > 0) ...[
                            Icon(Icons.star, size: 16, color: AppTheme.starRating),
                            SizedBox(width: 4),
                            Text(avg.toStringAsFixed(1), style: GoogleFonts.outfit(color: headingColor, fontSize: 16, fontWeight: FontWeight.bold)),
                          ] else
                            Text('New', style: GoogleFonts.outfit(color: bodyColor, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on_outlined, size: 16, color: bodyColor),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              salon['address'] ?? 'No address',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(color: bodyColor, fontSize: 14)
                            )
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Divider(color: borderColor, thickness: 1, height: 1),
                      SizedBox(height: 12),
                      if (!isServiceable)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkWarningBg : AppTheme.lightWarningBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            salon['unavailable_reason'] ?? 'Not taking bookings',
                            style: GoogleFonts.outfit(color: isDark ? AppTheme.darkWarning : AppTheme.lightWarning, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Tap to view services',
                              style: GoogleFonts.outfit(color: bodyColor, fontSize: 13),
                            ),
                            Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.accentColor),
                          ],
                        ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactSalonCard(dynamic salon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
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
            height: 140, // increased height to accommodate the divider
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.03), blurRadius: 10, offset: Offset(0, 4))
              ]
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image on the left
                SizedBox(
                  width: 120,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        salon['cover_image'] ?? salon['cover_photo_url'] ?? salon['logo_image'] ?? '',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: isDark ? AppTheme.darkAccentSoft : const Color(0xFFF3F0FF), child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 30)),
                      ),
                      if (salon['distance_km'] != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75), borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              '${salon['distance_is_approximate'] == true ? '~' : ''}${salon['distance_km']} km',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                              Text(avg.toStringAsFixed(1), style: GoogleFonts.outfit(color: headingColor, fontSize: 14, fontWeight: FontWeight.bold)),
                            ] else
                              Text('New', style: GoogleFonts.outfit(color: bodyColor, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on_outlined, size: 14, color: bodyColor),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                salon['address'] ?? 'No address',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(color: bodyColor, fontSize: 13)
                              )
                            ),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: Divider(color: borderColor, thickness: 1, height: 1),
                          ),
                        ),
                        if (!isServiceable)
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                            style: GoogleFonts.outfit(color: AppTheme.accentColor, fontSize: 13, fontWeight: FontWeight.w600),
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
