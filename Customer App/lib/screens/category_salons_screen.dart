import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/category.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import '../widgets/city_picker_sheet.dart';
import '../widgets/discovery_salon_card.dart';

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

  bool _signedIn = false;
  Set<String> _favouritedIds = {};

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update favourite.')),
      );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            Expanded(child: _buildPanel(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final headingColor =
        isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 14),
      child: Row(
        children: [
          IconButton(
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
          _buildCityChip(isDark),
        ],
      ),
    );
  }

  Widget _buildCityChip(bool isDark) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final headingColor =
        isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final cityName = LocationService.instance.city?.name ?? 'Select city';

    return GestureDetector(
      onTap: _pickCity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
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
              color: isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody,
            ),
          ],
        ),
      ),
    );
  }

  /// The rectangle: one bordered, rounded surface holding the whole answer for
  /// this category in this city.
  Widget _buildPanel(bool isDark) {
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color:
                Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildPanelHeader(isDark),
          Expanded(child: _buildPanelBody(isDark)),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(bool isDark) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final headingColor =
        isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
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
                color: isDark
                    ? AppTheme.darkAccentSoft
                    : AppTheme.lightAccentSoft,
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

  Widget _buildPanelBody(bool isDark) {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppTheme.accentColor,
          ),
        ),
      );
    }

    if (_loadFailed) {
      return _buildMessage(
        isDark,
        icon: Icons.wifi_off_rounded,
        title: 'Could not load salons',
        detail: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: _loadSalons,
      );
    }

    if (_salons.isEmpty) {
      return _buildMessage(
        isDark,
        icon: Icons.search_off_rounded,
        title: 'No salons found',
        detail: _isCombo
            ? 'No salons near ${LocationService.instance.city?.name ?? 'you'} offer combo packages yet.'
            : 'No salons near ${LocationService.instance.city?.name ?? 'you'} currently offer $_categoryName.',
        actionLabel: 'Change city',
        onAction: _pickCity,
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentColor,
      onRefresh: _loadSalons,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        itemCount: _salons.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final salon = _salons[index];
          final id = salon['id'].toString();

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
  }

  Widget _buildMessage(
    bool isDark, {
    required IconData icon,
    required String title,
    required String detail,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) {
    final headingColor =
        isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.darkAccentSoft
                    : AppTheme.lightAccentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 38,
                color: AppTheme.accentColor.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: headingColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13.5, color: bodyColor),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => onAction(),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: Icon(
                actionLabel == 'Retry'
                    ? Icons.refresh_rounded
                    : Icons.location_on_outlined,
                size: 18,
                color: AppTheme.accentColor,
              ),
              label: Text(
                actionLabel,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
