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
import '../../utils/app_haptics.dart';
import '../../services/auth_service.dart';
import '../phone_screen.dart';
import '../../widgets/category_grid.dart';
import '../../theme/app_colors.dart';
import '../../utils/error_text.dart';
import '../../widgets/feedback_states.dart';
import '../../widgets/skeleton.dart';
import '../../utils/bottom_clearance.dart';
import '../../widgets/animated_search_field.dart';

class ExploreTab extends StatefulWidget {
  const ExploreTab({super.key});

  @override
  ExploreTabState createState() => ExploreTabState();
}

/// Public because the bottom-nav shell holds a handle to it: a category picked
/// on the home tab is applied here, and the shell needs to reach in to do it.
class ExploreTabState extends State<ExploreTab> {
  final SalonService _salonService = SalonService();
  final AppointmentService _appointmentService = AppointmentService();
  List<dynamic> _salons = [];
  List<dynamic> _mostVisitedSalons = [];
  bool _isLoading = true;
  String _error = '';

  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All Salons';
  bool _isCardView = true;

  /// Set when the directory is narrowed to one category — from a card on the
  /// home screen or from the all-categories page. Null is the whole directory.
  String? _categoryId;
  String? _categoryLabel;

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

  /// Narrow the directory to one category and reload.
  ///
  /// Called by the shell when a category is picked elsewhere in the app. The
  /// typed search and the rating chips are reset because they belong to the
  /// unfiltered directory and would otherwise leave the customer staring at an
  /// empty list with no obvious way back.
  void applyCategoryFilter({String? categoryId, String? categoryLabel}) {
    if (categoryId == null || categoryId.isEmpty) {
      clearCategoryFilter();
      return;
    }

    AppHaptics.selectionClick();

    _searchController.clear();
    setState(() {
      _categoryId = categoryId;
      _categoryLabel = categoryLabel;
      _selectedFilter = 'All Salons';
      _isLoading = true;
      _error = '';
    });

    _loadSalons();
  }

  /// Back to the whole directory.
  ///
  /// A no-op when nothing is filtered, so tapping the Explore tab in the bottom
  /// bar does not refetch a list that is already correct.
  void clearCategoryFilter() {
    if (_categoryId == null) return;

    setState(() {
      _categoryId = null;
      _categoryLabel = null;
      _isLoading = true;
    });

    _loadSalons();
  }

  Future<void> _toggleFavourite(Map<String, dynamic> salon) async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => const PhoneScreen(isModal: true)),
      );
      if (loggedIn != true) return;
    }

    final salonId = salon['id'].toString();
    final bool currentFav = salon['is_favourited'] == true || salon['is_favourited'] == 1 || salon['is_favourited'] == '1';

    // Optimistic UI update
    setState(() {
      salon['is_favourited'] = !currentFav;
    });
    AppHaptics.lightImpact();

    try {
      final isFavourited = await _salonService.toggleFavourite(salonId);
      if (!mounted) return;
      setState(() {
        salon['is_favourited'] = isFavourited;
      });
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      // Revert optimistic update on failure
      setState(() {
        salon['is_favourited'] = currentFav;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(describeError(e, fallback: 'Could not update your favourites.')),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadSalons() async {
    try {
      final response = await _salonService.fetchSalons(categoryId: _categoryId);
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
        _error = describeError(e, fallback: 'We could not load salons.');
        _isLoading = false;
      });
    }
  }

  void _navigateToSearch() {
    if (_searchController.text.trim().isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(
          initialQuery: _searchController.text,
          categoryId: _categoryId,
          categoryLabel: _categoryLabel,
        ),
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
    // Loading and failure keep the tab's own page colour, instead of a bare
    // spinner or the raw exception in red on whatever is behind the tab.
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.colors.pageTint,
        body: SafeArea(
          bottom: false,
          child: SkeletonList(
            padding: EdgeInsets.fromLTRB(20, 24, 20, bottomClearance(context)),
            itemBuilder: (_) => const SalonCardSkeleton(),
          ),
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Scaffold(
        backgroundColor: context.colors.pageTint,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppTheme.accentColor,
            onRefresh: _loadSalons,
            child: ScrollableStateView(
              bottomInset: bottomClearance(context),
              child: ErrorState(
                title: 'Could not load salons',
                message: _error,
                onRetry: () {
                  setState(() => _isLoading = true);
                  _loadSalons();
                },
              ),
            ),
          ),
        ),
      );
    }

    final filteredSalons = _filteredSalons;


    return Scaffold(
      backgroundColor: context.colors.pageTint,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.accentColor,
          onRefresh: _loadSalons,
          child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 16),
              _buildHeader(),
              if (_categoryId != null) ...[
                SizedBox(height: 16),
                _buildCategoryFilterBanner(),
              ],
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
                
              SizedBox(height: bottomClearance(context)),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// The cart moved off the floating button and up into the header next to the
  /// search field, so the salon list gets the full width it was sharing before.
  ///
  /// It stays put whether or not there is anything in it, so the icon reads as
  /// part of the header rather than something that appears and vanishes.
  Widget _buildCartButton() {
    final surfaceColor = context.colors.surface;
    final iconColor = context.colors.textPrimary;
    final count = ((_globalCart?['items'] as List?) ?? []).length;

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => CartScreen()
        )).then((_) => _loadSalons());
      },
      child: Container(
        height: 50,
        width: 50,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: context.colors.dropShadow,
              blurRadius: 15,
              offset: const Offset(0, 4),
            )
          ]
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(Icons.shopping_cart_rounded, color: iconColor, size: 22),
            ),
            if (count > 0)
              Positioned(
                top: 6,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: context.colors.surface,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.outfit(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final surfaceColor = context.colors.surface;
    final headingColor = context.colors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              padding: EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.dropShadow,
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  )
                ]
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: context.colors.textTertiary, size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: AnimatedSearchField(
                      controller: _searchController,
                      suggestions: const [
                        "haircut",
                        "hair spa",
                        "facial",
                        "manicure",
                        "pedicure",
                        "cleanup",
                        "bridal makeup",
                        "hair colour",
                        "waxing",
                        "combo"
                      ],
                      style: GoogleFonts.outfit(fontSize: 15, color: headingColor),
                      decoration: InputDecoration(
                        hintText: 'Search salons or services...',
                        hintStyle: GoogleFonts.outfit(color: context.colors.textTertiary, fontSize: 15),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      onSubmitted: (_) => _navigateToSearch(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 10),
          _buildCartButton(),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;
    final bodyColor = context.colors.textSecondary;

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
                    BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.01), blurRadius: 4, offset: Offset(0, 2))
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
                color: isSelected ? context.colors.chipSelected : surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.accentColor : borderColor,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.01), blurRadius: 4, offset: Offset(0, 2))
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

  /// Tells the customer the list below is not the whole directory, and gives
  /// them one tap back to it.
  Widget _buildCategoryFilterBanner() {
    final borderColor = context.colors.listBorder;
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;

    final label = _categoryLabel ?? 'this category';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: context.colors.accentSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CategoryGrid.fallbackIcon(label),
                size: 18,
                color: AppTheme.accentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Showing $label salons',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: headingColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Salons in this city that offer $label',
                    maxLines: 2,
                    style: GoogleFonts.outfit(fontSize: 12, color: bodyColor),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                AppHaptics.lightImpact();
                clearCategoryFilter();
              },
              child: Text(
                'Clear',
                style: GoogleFonts.outfit(
                  color: AppTheme.accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String? subtitle) {
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;

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
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;

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
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04), blurRadius: 12, offset: Offset(0, 4))
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
                          errorBuilder: (_, __, ___) => Container(color: context.colors.imagePlaceholder, child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 30)),
                        ),
                        if (salon['distance_km'] != null)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(8)),
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
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _categoryId == null
                        ? 'All Salons near you'
                        : '${_categoryLabel ?? 'Filtered'} salons near you',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: headingColor),
                  ),
                ),
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
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;
    final activeBg = AppTheme.accentColor;
    final activeIcon = Colors.white;
    final inactiveIcon = context.colors.iconInactive;

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
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final isServiceable = salon['is_serviceable'] != false;
    final count = (salon['review_count'] as num?)?.toInt() ?? 0;
    final avg = (salon['avg_rating'] as num?)?.toDouble() ?? 0;
    final bool isFav = salon['is_favourited'] == true || salon['is_favourited'] == 1 || salon['is_favourited'] == '1';

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
                BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04), blurRadius: 12, offset: Offset(0, 4))
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
                        errorBuilder: (_, __, ___) => Container(color: context.colors.imagePlaceholder, child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 40)),
                      ),
                      if (salon['distance_km'] != null)
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              '${salon['distance_is_approximate'] == true ? '~' : ''}${salon['distance_km']} km',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _toggleFavourite(salon),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: context.colors.surface.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                size: 18,
                                color: isFav ? Colors.redAccent : context.colors.iconIdle,
                              ),
                            ),
                          ),
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
                            color: context.colors.warningBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            salon['unavailable_reason'] ?? 'Not taking bookings',
                            style: GoogleFonts.outfit(color: context.colors.warning, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        Text(
                          'Tap to view services',
                          style: GoogleFonts.outfit(color: bodyColor, fontSize: 13),
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
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final isServiceable = salon['is_serviceable'] != false;
    final count = (salon['review_count'] as num?)?.toInt() ?? 0;
    final avg = (salon['avg_rating'] as num?)?.toDouble() ?? 0;
    final bool isFav = salon['is_favourited'] == true || salon['is_favourited'] == 1 || salon['is_favourited'] == '1';

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
                BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03), blurRadius: 10, offset: Offset(0, 4))
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
                        errorBuilder: (_, __, ___) => Container(color: context.colors.imagePlaceholder, child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 30)),
                      ),
                      if (salon['distance_km'] != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              '${salon['distance_is_approximate'] == true ? '~' : ''}${salon['distance_km']} km',
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        )
                    ],
                  ),
                ),
                // Favourite button overlay on the image in compact mode too!
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _toggleFavourite(salon),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: context.colors.surface.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: isFav ? Colors.redAccent : context.colors.iconIdle,
                        ),
                      ),
                    ),
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
                              color: context.colors.warningBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              salon['unavailable_reason'] ?? 'Not taking bookings',
                              style: GoogleFonts.outfit(color: context.colors.warning, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          )
                        else
                        Text(
                          'Tap to view services',
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

    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;

    // A category with no salons in this city is a different problem from a
    // city with no salons at all, and the way out differs too.
    final isFiltered = _categoryId != null;
    final label = _categoryLabel ?? 'this category';

    return Column(
      children: [
        EmptyState(
          icon: isFiltered ? Icons.search_off_rounded : Icons.storefront_outlined,
          title: isFiltered
              ? 'No $label salons in ${cityName ?? 'this city'} yet'
              : cityName == null
                  ? 'No salons found'
                  : 'No salons in $cityName yet',
          message: isFiltered
              ? 'Try another category, show every salon, or check a nearby city.'
              : 'We are adding salons all the time. Try another city in the meantime.',
          actionLabel: isFiltered ? 'Show all salons' : 'Change city',
          onAction: isFiltered
              ? () {
                  AppHaptics.lightImpact();
                  clearCategoryFilter();
                }
              : _pickCity,
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
                        backgroundColor: context.colors.accentSoft,
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
