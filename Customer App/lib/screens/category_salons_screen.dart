import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/category.dart';
import '../services/auth_service.dart';
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
/// Tapping a category anywhere in the app lands here. The answer is whatever
/// `GET /customer/salons?category_id=…` returns for that city, so the list is
/// never padded with salons that do not actually offer the category — if the
/// city has none, this page says so instead of substituting nearby salons.
class CategorySalonsScreen extends StatefulWidget {
  final ServiceCategory category;

  const CategorySalonsScreen({super.key, required this.category});

  @override
  State<CategorySalonsScreen> createState() => _CategorySalonsScreenState();
}

class _CategorySalonsScreenState extends State<CategorySalonsScreen> {
  final SalonService _salonService = SalonService();

  List<Map<String, dynamic>> _salons = [];
  bool _isLoading = true;
  bool _loadFailed = false;

  /// A failed favourite toggle, shown above the list (the heart is put back).
  String? _actionError;

  bool _signedIn = false;
  Set<String> _favouritedIds = {};

  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedSort = 'Recommended';

  /// Combo is not a catalogue row — it is a package a salon assembles from its
  /// own services — so it carries this sentinel id, which the directory
  /// resolves to "salons with an active combo".
  bool get _isCombo => widget.category.id == 'combo';

  String get _categoryName => widget.category.name;

  @override
  void initState() {
    super.initState();
    LocationService.instance.addListener(_onCityChanged);
    _loadSalons();
    _loadFavourites();
  }

  @override
  void dispose() {
    LocationService.instance.removeListener(_onCityChanged);
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
      final body = await _salonService.fetchSalons(
        categoryId: widget.category.id,
      );
      if (!mounted) return;
      final rows = (body['salons'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      setState(() {
        _salons = rows;
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
      // A failed favourites read is not worth an error page; the list still
      // works, it just has no hearts on it.
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
      setState(() => _actionError = 'Could not update your favourites. Please try again.');
    }
  }

  Future<void> _pickCity() async {
    final changed = await showCityPicker(context);
    if (!changed || !mounted) return;
    AppHaptics.selectionClick();
    await _loadSalons();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: context.colors.surfaceMuted,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final headingColor =
        context.colors.textPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 14),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: AppTheme.accentColor),
          ),
          Expanded(
            child: Text(
              _categoryName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: headingColor,
              ),
            ),
          ),
          _buildCityChip(),
        ],
      ),
    );
  }

  Widget _buildCityChip() {
    final borderColor = context.colors.border;
    final headingColor =
        context.colors.textPrimary;
    final cityName = LocationService.instance.city?.name ?? 'Select city';

    return GestureDetector(
      onTap: _pickCity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              constraints: const BoxConstraints(maxWidth: 110),
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

  /// The rectangle: one bordered, rounded surface holding the whole answer for
  /// this category in this city.
  Widget _buildPanel() {
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_isCombo) _buildComboFilters(),
          if (!_isCombo) _buildPanelHeader(),
          Expanded(child: _buildPanelBody()),
        ],
      ),
    );
  }

  Widget _buildComboFilters() {
    final borderColor = context.colors.border;
    final headingColor = context.colors.textPrimary;
    final categories = ['All', 'Women', 'Men', 'Hair', 'Skin', 'Bridal'];
    final sorts = ['Recommended', 'Nearest', 'Highest Rated', 'Price: Low to High', 'Price: High to Low', 'Offers'];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: context.colors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: context.colors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: GoogleFonts.outfit(fontSize: 14, color: headingColor),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search combos...',
                        hintStyle: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: Chip(
                    label: Text(
                      cat,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : headingColor,
                      ),
                    ),
                    backgroundColor: isSelected ? AppTheme.accentColor : context.colors.surfaceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? AppTheme.accentColor : context.colors.border,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedSort,
                    icon: Icon(Icons.arrow_drop_down, color: context.colors.textSecondary),
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: headingColor),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() => _selectedSort = newValue);
                      }
                    },
                    items: sorts.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ),
                const Spacer(),
                if (!_isLoading && !_loadFailed)
                  Text(
                    '${_totalCombosCount} combos found',
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _minComboPrice(List<dynamic> combos) {
    double min = double.infinity;
    for (var c in combos) {
        final p = (c['price'] as num?)?.toDouble() ?? 0;
        if (p < min) min = p;
    }
    return min == double.infinity ? 0 : min;
  }

  int get _totalCombosCount {
    int count = 0;
    for (var salon in _filteredSalons) {
        count += (salon['combos'] as List?)?.length ?? 0;
    }
    return count;
  }

  List<Map<String, dynamic>> get _filteredSalons {
    if (!_isCombo) return _salons;

    List<Map<String, dynamic>> result = [];
    
    for (var salon in _salons) {
      var combos = (salon['combos'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
      if (combos.isEmpty) continue; // Only show salons with combos

      var filteredCombos = combos.where((combo) {
         // Search match
         if (_searchQuery.isNotEmpty) {
             final q = _searchQuery.toLowerCase();
             final name = (combo['name'] ?? '').toLowerCase();
             final servicesStr = ((combo['services'] as List?) ?? []).map((s) => s['name'] ?? '').join(' ').toLowerCase();
             final salonName = (salon['name'] ?? '').toLowerCase();
             if (!name.contains(q) && !servicesStr.contains(q) && !salonName.contains(q)) return false;
         }
         
         // Filter category match
         if (_selectedCategory != 'All') {
             final cat = _selectedCategory.toLowerCase();
             final genderFocus = (salon['gender_focus'] ?? '').toLowerCase();
             if (cat == 'women' && genderFocus == 'men only') return false;
             if (cat == 'men' && genderFocus == 'women only') return false;
             
             if (cat != 'women' && cat != 'men') {
                 final name = (combo['name'] ?? '').toLowerCase();
                 final servicesStr = ((combo['services'] as List?) ?? []).map((s) => s['name'] ?? '').join(' ').toLowerCase();
                 if (!name.contains(cat) && !servicesStr.contains(cat)) return false;
             }
         }
         
         // Offers match
         if (_selectedSort == 'Offers') {
             final price = (combo['price'] as num?)?.toDouble() ?? 0;
             final orig = (combo['original_price'] as num?)?.toDouble() ?? 0;
             if (price >= orig || orig == 0) return false;
         }
         
         return true;
      }).toList();
      
      if (filteredCombos.isNotEmpty) {
          var newSalon = Map<String, dynamic>.from(salon);
          newSalon['combos'] = filteredCombos;
          result.add(newSalon);
      }
    }
    
    if (_selectedSort == 'Nearest') {
        result.sort((a, b) => (a['distance_km'] as num? ?? 999).compareTo(b['distance_km'] as num? ?? 999));
    } else if (_selectedSort == 'Price: Low to High') {
        result.sort((a, b) {
            final aMin = _minComboPrice(a['combos']);
            final bMin = _minComboPrice(b['combos']);
            return aMin.compareTo(bMin);
        });
    } else if (_selectedSort == 'Price: High to Low') {
        result.sort((a, b) {
            final aMin = _minComboPrice(a['combos']);
            final bMin = _minComboPrice(b['combos']);
            return bMin.compareTo(aMin);
        });
    } else if (_selectedSort == 'Highest Rated') {
        result.sort((a, b) => (b['avg_rating'] as num? ?? 0).compareTo(a['avg_rating'] as num? ?? 0));
    }
    
    return result;
  }

  Widget _buildPanelHeader() {
    final borderColor = context.colors.border;
    final headingColor =
        context.colors.textPrimary;
    final cityName = LocationService.instance.city?.name;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.storefront,
            size: 18,
            color: AppTheme.accentColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              cityName == null
                  ? 'Salons offering $_categoryName'
                  : 'Salons in $cityName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: headingColor,
              ),
            ),
          ),
          if (!_isLoading && !_loadFailed)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.colors.accentSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_salons.length}',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanelBody() {
    if (_isLoading) {
      return SkeletonList(
        count: 4,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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

          return DiscoverySalonCard(
            salon: salon,
            isFavourited: _favouritedIds.contains(id),
            showFavourite: _signedIn,
            // The salon opens on this category's services, so arriving from a
            // category never dumps the customer on the salon's full price list.
            categoryId: _isCombo ? null : widget.category.id,
            categoryName: _isCombo ? null : widget.category.name,
            onToggleFavourite: () => _toggleFavourite(id),
          );
        },
      ),
    );

    if (_actionError == null) return list;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
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
