import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/category.dart';
import '../services/audience_service.dart';
import '../services/auth_service.dart';
import '../services/discovery_service.dart';
import '../services/location_service.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import '../widgets/city_picker_sheet.dart';
import '../widgets/combo_discovery_card.dart';
import '../widgets/discovery_salon_card.dart';
import '../widgets/feedback_states.dart';
import '../widgets/skeleton.dart';
import '../theme/app_colors.dart';

/// Salons that offer a service in one category, in the city the customer picked.
///
/// Implements modern mobile design with search, sub-service category pills,
/// and interactive salon cards where services can be directly selected.
/// Whether a directory row is for the audience picked on the category screen
/// ("Unisex", "Women Only", "Men Only"; anything else means everyone).
///
/// A salon that does not say whom it serves is open to everyone. The server has
/// already filtered by gender, and treating a missing value as "no match" used
/// to empty the whole list for anyone with a gender on their profile.
bool salonServesAudience(Map<String, dynamic> salon, String audience) {
  final target = audience.toLowerCase();
  final raw = (salon['gender_focus'] ?? '').toString().trim().toLowerCase();
  final focus = raw.isEmpty ? 'unisex' : raw;
  return switch (target) {
    'unisex' => focus == 'unisex',
    'women only' => focus == 'women only' || focus == 'unisex',
    'men only' => focus == 'men only' || focus == 'unisex',
    _ => true,
  };
}

class CategorySalonsScreen extends StatefulWidget {
  final ServiceCategory category;

  const CategorySalonsScreen({super.key, required this.category});

  @override
  State<CategorySalonsScreen> createState() => _CategorySalonsScreenState();
}

class _CategorySalonsScreenState extends State<CategorySalonsScreen> {
  final SalonService _salonService = SalonService();
  final DiscoveryService _discoveryService = DiscoveryService();

  List<Map<String, dynamic>> _salons = [];
  List<DiscoveryServiceItem> _discoveredServices = [];
  bool _isLoading = true;
  bool _loadFailed = false;

  /// A failed favourite toggle, shown above the list (the heart is put back).
  String? _actionError;

  bool _signedIn = false;
  Set<String> _favouritedIds = {};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedSubCategory = 'All';
  String _selectedSort = 'Recommended';
  String _selectedGender = 'All';


  bool get _isCombo => widget.category.id == 'combo';
  String get _categoryName => widget.category.name;

  @override
  void initState() {
    super.initState();
    LocationService.instance.addListener(_onCityChanged);
    _loadForProfileAudience();
    _loadFavourites();
  }

  /// Start out showing what is meant for the customer — a woman sees Unisex
  /// and Women Only — with a chip that says so and lets her see everything.
  Future<void> _loadForProfileAudience() async {
    final gender = await AudienceService.profileGender();
    if (!mounted) return;
    setState(() => _selectedGender = AudienceService.focusFilterFor(gender));
    await _loadSalons();
  }

  @override
  void dispose() {
    LocationService.instance.removeListener(_onCityChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onCityChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadSalons() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      final audience = AudienceService.apiParam(_selectedGender);
      final futures = await Future.wait([
        _salonService.fetchSalons(categoryId: widget.category.id, gender: audience),
        if (!_isCombo)
          _discoveryService
              .fetchCategoryServices(widget.category.id, gender: audience)
              .catchError((_) => <DiscoveryServiceItem>[])
        else
          Future.value(<DiscoveryServiceItem>[]),
      ]);

      if (!mounted) return;
      final body = futures[0] as Map<String, dynamic>;
      final discovered = futures[1] as List<DiscoveryServiceItem>;

      final rows = (body['salons'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

      setState(() {
        _salons = rows;
        _discoveredServices = discovered;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFavourites() async {
    final token = await AuthService.getToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) return;

    try {
      final favourites = await _salonService.fetchFavourites();
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _favouritedIds = favourites.map((f) => f['id'].toString()).toSet();
      });
    } catch (_) {
      // Failed favourites read does not break the list
    }
  }

  Future<void> _toggleFavourite(String salonId) async {
    final wasFavourite = _favouritedIds.contains(salonId);
    setState(() {
      wasFavourite
          ? _favouritedIds.remove(salonId)
          : _favouritedIds.add(salonId);
    });

    try {
      final nowFavourite = await _salonService.toggleFavourite(salonId);
      if (!mounted) return;
      setState(() {
        _actionError = null;
        nowFavourite
            ? _favouritedIds.add(salonId)
            : _favouritedIds.remove(salonId);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        wasFavourite
            ? _favouritedIds.add(salonId)
            : _favouritedIds.remove(salonId);
      });
      setState(
        () => _actionError =
            'Could not update your favourites. Please try again.',
      );
    }
  }

  Future<void> _pickCity() async {
    final changed = await showCityPicker(context);
    if (!changed || !mounted) return;
    AppHaptics.selectionClick();
    await _loadSalons();
  }

  List<String> get _availablePills {
    if (_isCombo) {
      return const ['All', 'Women', 'Men', 'Hair', 'Skin', 'Bridal'];
    }

    final set = <String>{};
    // 1. Add discovered services from catalogue
    for (final item in _discoveredServices) {
      if (item.name.trim().isNotEmpty) {
        set.add(item.name.trim());
      }
    }
    // 2. Add services present in returned salons
    for (final s in _salons) {
      final list = s['category_services'] as List?;
      if (list != null) {
        for (final item in list) {
          if (item is Map && item['name'] != null) {
            final name = item['name'].toString().trim();
            if (name.isNotEmpty) set.add(name);
          }
        }
      }
    }

    // Fallbacks if no services were returned yet
    if (set.isEmpty) {
      final cat = _categoryName.toLowerCase();
      if (cat.contains('hair')) {
        return const [
          'All',
          "Men's Haircut",
          'Hair Styling',
          'Hair Colour',
          'Beard Styling',
          'Hair Spa',
        ];
      }
      return const ['All'];
    }

    return ['All', ...set];
  }

  double _getMinPrice(Map<String, dynamic> salon) {
    double min = double.infinity;
    final services = (salon['category_services'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final s in services) {
      final p = (s['price'] as num?)?.toDouble() ?? 0;
      if (p > 0 && p < min) min = p;
    }
    final combos = (salon['combos'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final c in combos) {
      final p = (c['price'] as num?)?.toDouble() ?? 0;
      if (p > 0 && p < min) min = p;
    }
    return min == double.infinity ? 0 : min;
  }

  List<Map<String, dynamic>> get _filteredSalons {
    List<Map<String, dynamic>> list = _salons;

    // Search query match
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((salon) {
        final name = (salon['name'] ?? '').toString().toLowerCase();
        final addr = (salon['address'] ?? '').toString().toLowerCase();
        final services =
            (salon['category_services'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map((s) => (s['name'] ?? '').toString().toLowerCase())
                .join(' ');
        final combos = (salon['combos'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((c) => (c['name'] ?? '').toString().toLowerCase())
            .join(' ');
        return name.contains(q) ||
            addr.contains(q) ||
            services.contains(q) ||
            combos.contains(q);
      }).toList();
    }

    // Sub-category / Service match
    if (_selectedSubCategory != 'All') {
      final target = _selectedSubCategory.toLowerCase();
      list = list.where((salon) {
        final services =
            (salon['category_services'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>();
        for (final s in services) {
          final sName = (s['name'] ?? '').toString().toLowerCase();
          if (sName.contains(target) || target.contains(sName)) {
            return true;
          }
        }

        if (_isCombo) {
          final genderFocus =
              (salon['gender_focus'] ?? '').toString().toLowerCase();
          if (target == 'women' && genderFocus == 'men only') return false;
          if (target == 'men' && genderFocus == 'women only') return false;
          final combos = (salon['combos'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>();
          for (final c in combos) {
            final cName = (c['name'] ?? '').toString().toLowerCase();
            if (cName.contains(target)) return true;
          }
        }
        return false;
      }).toList();
    }

    // Gender focus match
    if (_selectedGender != 'All') {
      list = list.where((salon) => salonServesAudience(salon, _selectedGender)).toList();
    }

    // Sort order
    final sorted = List<Map<String, dynamic>>.from(list);
    if (_selectedSort == 'Nearest') {
      sorted.sort(
        (a, b) => (a['distance_km'] as num? ?? 999).compareTo(
          b['distance_km'] as num? ?? 999,
        ),
      );
    } else if (_selectedSort == 'Highest Rated') {
      sorted.sort(
        (a, b) => (b['avg_rating'] as num? ?? 0).compareTo(
          a['avg_rating'] as num? ?? 0,
        ),
      );
    } else if (_selectedSort == 'Price: Low to High') {
      sorted.sort((a, b) => _getMinPrice(a).compareTo(_getMinPrice(b)));
    } else if (_selectedSort == 'Price: High to Low') {
      sorted.sort((a, b) => _getMinPrice(b).compareTo(_getMinPrice(a)));
    }

    return sorted;
  }

  void _showFilterModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String tempSort = _selectedSort;
        String tempGender = _selectedGender;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.colors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter & Sort',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            tempSort = 'Recommended';
                            tempGender = 'All';
                          });
                        },
                        child: Text(
                          'Reset',
                          style: GoogleFonts.outfit(
                            color: AppTheme.accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sort By',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      'Recommended',
                      'Nearest',
                      'Highest Rated',
                      'Price: Low to High',
                      'Price: High to Low',
                    ].map((sortOption) {
                      final isSelected = tempSort == sortOption;
                      return ChoiceChip(
                        label: Text(sortOption),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) setSheetState(() => tempSort = sortOption);
                        },
                        selectedColor: AppTheme.accentColor,
                        labelStyle: GoogleFonts.outfit(
                          color: isSelected
                              ? Colors.white
                              : context.colors.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                        backgroundColor: context.colors.surfaceMuted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? AppTheme.accentColor
                                : context.colors.border,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Gender Focus',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['All', 'Unisex', 'Women Only', 'Men Only']
                        .map((g) {
                      final isSelected = tempGender == g;
                      return ChoiceChip(
                        label: Text(g),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) setSheetState(() => tempGender = g);
                        },
                        selectedColor: AppTheme.accentColor,
                        labelStyle: GoogleFonts.outfit(
                          color: isSelected
                              ? Colors.white
                              : context.colors.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                        backgroundColor: context.colors.surfaceMuted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? AppTheme.accentColor
                                : context.colors.border,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        final audienceChanged = AudienceService.apiParam(tempGender) !=
                            AudienceService.apiParam(_selectedGender);
                        setState(() {
                          _selectedSort = tempSort;
                          _selectedGender = tempGender;
                        });
                        Navigator.pop(ctx);
                        // The server decides which services are for whom, so
                        // a different audience is a fresh fetch.
                        if (audienceChanged) _loadSalons();
                      },
                      child: Text(
                        'Apply Filters',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surfaceMuted,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBarAndFilter(),
            _buildCategoryPills(),
            _buildAudienceChip(),
            const SizedBox(height: 8),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  /// Says out loud that the list is narrowed to one audience, so a filter
  /// that came from the profile is never a silent one.
  Widget _buildAudienceChip() {
    final audience = AudienceService.apiParam(_selectedGender);
    if (audience == null) return const SizedBox.shrink();

    return Padding(
      key: const ValueKey('audience-chip'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 16, color: AppTheme.accentColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Showing services for $audience',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _selectedGender = 'All');
              _loadSalons();
            },
            child: Text('Show all', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final cityName = LocationService.instance.city?.name ?? 'Pune';

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: headingColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: headingColor,
                  ),
                ),
                Text(
                  'Find the best ${_categoryName.toLowerCase()} salons in $cityName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: bodyColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildCityChip(),
        ],
      ),
    );
  }

  Widget _buildCityChip() {
    final borderColor = context.colors.border;
    final headingColor = context.colors.textPrimary;
    final cityName = LocationService.instance.city?.name ?? 'Select city';

    return GestureDetector(
      onTap: _pickCity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 15,
              color: AppTheme.accentColor,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                cityName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: headingColor,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: context.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBarAndFilter() {
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final borderColor = context.colors.border;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor.withValues(alpha: 0.7)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: bodyColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: headingColor,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search salons or services...',
                        hintStyle: GoogleFonts.outfit(
                          fontSize: 13.5,
                          color: bodyColor,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: bodyColor,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _showFilterModal,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (_selectedSort != 'Recommended' ||
                          _selectedGender != 'All')
                      ? AppTheme.accentColor
                      : borderColor,
                  width: (_selectedSort != 'Recommended' ||
                          _selectedGender != 'All')
                      ? 1.5
                      : 1.1,
                ),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 20,
                color: (_selectedSort != 'Recommended' ||
                        _selectedGender != 'All')
                    ? AppTheme.accentColor
                    : headingColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPills() {
    final headingColor = context.colors.textPrimary;
    final borderColor = context.colors.border;
    final pills = _availablePills;

    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: pills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final pill = pills[index];
          final isAll = index == 0;
          final isSelected = isAll
              ? _selectedSubCategory == 'All'
              : _selectedSubCategory == pill;

          final labelText = isAll ? 'All (${_filteredSalons.length})' : pill;

          return GestureDetector(
            onTap: () {
              AppHaptics.selectionClick();
              setState(() {
                if (isAll) {
                  _selectedSubCategory = 'All';
                } else {
                  _selectedSubCategory = isSelected ? 'All' : pill;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.accentColor
                    : context.colors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected ? AppTheme.accentColor : borderColor,
                  width: 1.1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                labelText,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : headingColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return SkeletonList(
        count: 4,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
        itemBuilder: (_) => const SalonCardSkeleton(),
      );
    }

    if (_loadFailed) {
      return RefreshIndicator(
        color: AppTheme.accentColor,
        onRefresh: _loadSalons,
        child: ScrollableStateView(
          child: ErrorState(
            title: 'Could not load salons',
            onRetry: () {
              setState(() => _isLoading = true);
              _loadSalons();
            },
          ),
        ),
      );
    }

    final filteredSalons = _filteredSalons;

    if (filteredSalons.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.accentColor,
        onRefresh: _loadSalons,
        child: ScrollableStateView(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: _isCombo ? 'No combos found' : 'No salons found',
            message: _isCombo
                ? 'Try a different search or filter.'
                : 'No salons near ${LocationService.instance.city?.name ?? 'you'} currently offer $_categoryName.',
            actionLabel: 'Change city',
            onAction: _pickCity,
          ),
        ),
      );
    }

    final list = RefreshIndicator(
      color: AppTheme.accentColor,
      onRefresh: _loadSalons,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
        itemCount: filteredSalons.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final salon = filteredSalons[index];
          final id = salon['id'].toString();

          if (_isCombo) {
            return ComboDiscoveryCard(
              salon: salon,
              isFavourited: _favouritedIds.contains(id),
              showFavourite: _signedIn,
              onToggleFavourite: () => _toggleFavourite(id),
            );
          }

          String? subServiceId;
          if (_selectedSubCategory != 'All') {
            final catServices = (salon['category_services'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>();
            for (final s in catServices) {
              final sName = (s['name'] ?? '').toString().toLowerCase();
              final target = _selectedSubCategory.toLowerCase();
              if (sName == target || sName.contains(target) || target.contains(sName)) {
                subServiceId = s['template_id']?.toString() ?? s['id']?.toString();
                break;
              }
            }
          }

          return DiscoverySalonCard(
            salon: salon,
            isFavourited: _favouritedIds.contains(id),
            showFavourite: _signedIn,
            categoryId: _isCombo ? null : widget.category.id,
            categoryName: _isCombo ? null : widget.category.name,
            serviceId: subServiceId,
            onToggleFavourite: () => _toggleFavourite(id),
          );
        },
      ),
    );

    if (_actionError == null) return list;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          child: InlineStatus(
            message: _actionError!,
            onDismiss: () => setState(() => _actionError = null),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }
}
