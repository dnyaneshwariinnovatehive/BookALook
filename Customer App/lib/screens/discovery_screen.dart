import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/category.dart';
import '../services/auth_service.dart';
import '../services/discovery_service.dart';
import '../services/location_service.dart';
import '../services/salon_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import '../widgets/category_grid.dart';
import '../widgets/city_picker_sheet.dart';
import '../widgets/discovery_salon_card.dart';

enum _DiscoveryMode { category, combo }

class CategoryDiscoveryScreen extends StatelessWidget {
  final ServiceCategory category;

  const CategoryDiscoveryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return _DiscoveryScaffold(mode: _DiscoveryMode.category, category: category);
  }
}

class ComboDiscoveryScreen extends StatelessWidget {
  const ComboDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DiscoveryScaffold(mode: _DiscoveryMode.combo);
  }
}

class _Option {
  final String? key;
  final String name;
  final int salonCount;
  final String? subtitle;
  final double? rating;

  const _Option({this.key, required this.name, this.salonCount = 0, this.subtitle, this.rating});
}

/// The shared Zomato-style discovery layout: hero header, a search field that
/// stays scoped to the category or combo being browsed, a horizontal scroller
/// of real catalogue offerings, and the salons that actually offer the
/// selection. Every row comes from the backend — nothing here is templated or
/// hardcoded, and an empty answer is shown as an empty state, never padded
/// with unrelated salons.
class _DiscoveryScaffold extends StatefulWidget {
  final _DiscoveryMode mode;
  final ServiceCategory? category;

  const _DiscoveryScaffold({required this.mode, this.category});

  @override
  State<_DiscoveryScaffold> createState() => _DiscoveryScaffoldState();
}

class _DiscoveryScaffoldState extends State<_DiscoveryScaffold> {
  final SalonService _salonService = SalonService();
  final DiscoveryService _discoveryService = DiscoveryService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  List<DiscoveryServiceItem> _services = [];
  List<DiscoveryComboItem> _combos = [];
  String? _selectedKey;
  List<dynamic>? _salons;
  bool _loadFailed = false;
  bool _signedIn = false;
  Set<String> _favouritedIds = {};

  bool get _isCombo => widget.mode == _DiscoveryMode.combo;

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEverything() async {
    setState(() {
      _salons = null;
      _loadFailed = false;
    });
    await Future.wait([_fetchOptions(), _fetchSalons(), _loadFavourites()]);
  }

  Future<void> _fetchOptions() async {
    try {
      if (_isCombo) {
        final combos = await _discoveryService.fetchCombos();
        if (!mounted) return;
        setState(() => _combos = combos);
      } else {
        final services = await _discoveryService
            .fetchCategoryServices(widget.category?.id ?? '');
        if (!mounted) return;
        setState(() => _services = services);
      }
    } catch (_) {}
  }

  Future<void> _fetchSalons() async {
    final String? categoryId;
    final String? serviceId;
    final String? combo;

    if (_isCombo) {
      categoryId = CategoryGrid.comboSentinelId;
      serviceId = null;
      combo = _selectedKey;
    } else {
      categoryId = widget.category?.id;
      serviceId = _selectedKey;
      combo = null;
    }

    final query = _searchController.text.trim();
    try {
      final body = await _salonService.fetchSalons(
        search: query.isEmpty ? null : query,
        categoryId: categoryId,
        serviceId: serviceId,
        combo: combo,
      );
      if (!mounted) return;
      setState(() {
        _salons = body['salons'] as List<dynamic>? ?? [];
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _salons ??= [];
      });
    }
  }

  Future<void> _loadFavourites() async {
    final token = await AuthService.getToken();
    if (token == null) {
      if (mounted) setState(() => _signedIn = false);
      return;
    }
    if (!mounted) return;
    setState(() => _signedIn = true);
    try {
      final favourites = await _salonService.fetchFavourites();
      if (!mounted) return;
      setState(() {
        _favouritedIds = favourites.map((f) => f['id'].toString()).toSet();
      });
    } catch (_) {}
  }

  Future<void> _toggleFavourite(String salonId) async {
    final wasFav = _favouritedIds.contains(salonId);
    setState(() {
      wasFav ? _favouritedIds.remove(salonId) : _favouritedIds.add(salonId);
    });

    try {
      final nowFav = await _salonService.toggleFavourite(salonId);
      if (!mounted) return;
      setState(() {
        nowFav ? _favouritedIds.add(salonId) : _favouritedIds.remove(salonId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        wasFav ? _favouritedIds.add(salonId) : _favouritedIds.remove(salonId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update favourite: $e')),
      );
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _fetchSalons();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    _fetchSalons();
  }

  Future<void> _pickCity() async {
    final changed = await showCityPicker(context);
    if (!changed || !mounted) return;
    AppHaptics.selectionClick();
    setState(() {});
    await _loadEverything();
  }

  List<_Option> get _options {
    if (_isCombo) {
      return [
        const _Option(key: null, name: 'All combos'),
        ..._combos.map(
          (c) => _Option(
            key: c.name,
            name: c.name,
            salonCount: c.salonCount,
            rating: c.rating,
            subtitle: c.startingPrice > 0 ? 'from ₹${c.startingPrice.toStringAsFixed(0)}' : null,
          ),
        ),
      ];
    }
    return [
      const _Option(key: null, name: 'All services'),
      ..._services.map(
        (s) => _Option(
          key: s.serviceId,
          name: s.name,
          salonCount: s.salonCount,
          rating: s.rating,
          subtitle: [
            '₹${s.minPrice.toStringAsFixed(0)}',
            if (s.durationMinutes > 0) '${s.durationMinutes} min',
          ].join(' · '),
        ),
      ),
    ];
  }

  bool get _hasNoOptions {
    if (_salons == null) return false;
    return _isCombo ? _combos.isEmpty : _services.isEmpty;
  }

  /// Rated offerings, best first, for the top-rated horizontal cards. The
  /// rating is the best any salon in the city earns for that offering, so the
  /// order is honest — not a templated popularity guess.
  List<_Option> get _topRatedOptions {
    final rated = _options
        .where((o) => o.key != null && (o.rating ?? 0) > 0)
        .toList()
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    return rated.take(8).toList();
  }

  String get _heading => _isCombo ? 'Combos' : (widget.category?.name ?? '');

  String get _contextLabel {
    if (_isCombo) {
      return _selectedKey ?? 'combos';
    }
    String? name;
    for (final s in _services) {
      if (s.serviceId == _selectedKey) {
        name = s.name;
        break;
      }
    }
    return name ?? widget.category?.name ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: _hasNoOptions
            ? _buildNoOptionsState(isDark)
            : Column(
                children: [
                  _buildHeader(isDark, headingColor, bodyColor),
                  Expanded(child: _buildBody(isDark, headingColor, bodyColor)),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color headingColor, Color bodyColor) {
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final city = LocationService.instance.city;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: AppTheme.accentColor),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: headingColor,
                      ),
                    ),
                    Text(
                      _isCombo
                          ? 'Combo packages offered near you'
                          : '${_services.length} services · ${city?.name ?? 'your city'}',
                      style: GoogleFonts.outfit(fontSize: 13, color: bodyColor),
                    ),
                  ],
                ),
              ),
              GestureDetector(
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
                      Icon(Icons.location_on_outlined, size: 15, color: AppTheme.accentColor),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          city?.name ?? 'Nearby',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: headingColor,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, size: 18, color: bodyColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSearchField(isDark, bodyColor),
          const SizedBox(height: 12),
          _buildCapsules(isDark, headingColor, bodyColor),
          _buildTopRatedSection(isDark, headingColor, bodyColor),
        ],
      ),
    );
  }

  Widget _buildSearchField(bool isDark, Color bodyColor) {
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final fillColor = isDark ? AppTheme.darkSurface : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        onSubmitted: (_) {
          _debounce?.cancel();
          _fetchSalons();
        },
        textInputAction: TextInputAction.search,
        style: GoogleFonts.outfit(fontSize: 14, color: isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintText: _isCombo ? 'Search salons offering combos' : 'Search salons in ${widget.category?.name ?? ''}',
          hintStyle: GoogleFonts.outfit(fontSize: 14, color: bodyColor),
          prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.accentColor),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppTheme.accentColor),
                    onPressed: _clearSearch,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCapsules(bool isDark, Color headingColor, Color bodyColor) {
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final options = _options;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = option.key == _selectedKey;
          return GestureDetector(
            onTap: () {
              AppHaptics.selectionClick();
              setState(() => _selectedKey = option.key);
              _fetchSalons();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accentColor
                    : (isDark ? AppTheme.darkSurface : Colors.white),
                borderRadius: BorderRadius.circular(999),
                border: selected ? null : Border.all(color: borderColor, width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : headingColor,
                    ),
                  ),
                  if (option.salonCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Text(
                        '(${option.salonCount})',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white70 : bodyColor,
                        ),
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

  Widget _buildTopRatedSection(bool isDark, Color headingColor, Color bodyColor) {
    final top = _topRatedOptions;
    if (top.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _isCombo ? 'Top rated combos' : 'Top rated services',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: headingColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: top.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _buildTopRatedCard(top[index]),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// One top-rated card: the offering name is the highlight and the rating is
  /// the badge. No salon name — this ranks the service, not a host.
  Widget _buildTopRatedCard(_Option option) {
    final rating = option.rating ?? 0;

    return GestureDetector(
      onTap: () {
        AppHaptics.selectionClick();
        setState(() => _selectedKey = option.key);
        _fetchSalons();
      },
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accentColor,
              Color.lerp(AppTheme.accentColor, Colors.black, 0.25)!,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                const SizedBox(width: 3),
                Text(
                  rating.toStringAsFixed(1),
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  '${option.salonCount} salons',
                  style: GoogleFonts.outfit(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
            const Spacer(),
            Text(
              option.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 4),
            if (option.subtitle != null)
              Text(
                option.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark, Color headingColor, Color bodyColor) {
    if (_salons == null) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.accentColor),
        ),
      );
    }

    if (_loadFailed) {
      return _buildErrorState(isDark, headingColor, bodyColor);
    }

    if (_salons!.isEmpty) {
      return _buildNoSalonsState(isDark, headingColor, bodyColor);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _salons!.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSectionHeader(bodyColor);
        }
        final salon = _salons![index - 1] as Map<String, dynamic>;
        final id = salon['id'].toString();
        return DiscoverySalonCard(
          salon: salon,
          isFavourited: _favouritedIds.contains(id),
          showFavourite: _signedIn,
          onToggleFavourite: () => _toggleFavourite(id),
        );
      },
    );
  }

  Widget _buildSectionHeader(Color bodyColor) {
    final count = _salons?.length ?? 0;
    String? selectedSubtitle;
    for (final o in _options) {
      if (o.key == _selectedKey) {
        selectedSubtitle = o.subtitle;
        break;
      }
    }

    final String text;
    if (_selectedKey == null) {
      text = _isCombo ? 'All combos ($count)' : 'Salons offering ${widget.category?.name ?? ''} ($count)';
    } else if (selectedSubtitle == null) {
      text = 'Salons offering $_contextLabel';
    } else {
      text = 'Salons offering $_contextLabel · $selectedSubtitle';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(
        text,
        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: bodyColor),
      ),
    );
  }

  Widget _buildNoSalonsState(bool isDark, Color headingColor, Color bodyColor) {
    final isSearching = _searchController.text.trim().isNotEmpty;
    final detail = isSearching
        ? 'No salons near ${LocationService.instance.city?.name ?? 'you'} match your search.'
        : 'No salons near ${LocationService.instance.city?.name ?? 'you'} currently offer $_contextLabel.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded, size: 44, color: AppTheme.accentColor.withOpacity(0.6)),
            ),
            const SizedBox(height: 18),
            Text(
              'No salons found',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: headingColor),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 14, color: bodyColor),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () {
                if (isSearching) {
                  _clearSearch();
                } else {
                  _pickCity();
                }
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              icon: Icon(isSearching ? Icons.close : Icons.location_on_outlined, size: 18, color: AppTheme.accentColor),
              label: Text(
                isSearching ? 'Clear search' : 'Change city',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.accentColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoOptionsState(bool isDark) {
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final title = _isCombo ? 'No combos available' : 'No services available';
    final detail = _isCombo
        ? 'No salons near ${LocationService.instance.city?.name ?? 'you'} are offering combo packages yet.'
        : 'No salons near ${LocationService.instance.city?.name ?? 'you'} offer ${widget.category?.name ?? 'these services'} yet.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.content_paste_search_rounded, size: 44, color: AppTheme.accentColor.withOpacity(0.6)),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: headingColor),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 14, color: bodyColor),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _pickCity,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              icon: const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.accentColor),
              label: Text(
                'Change city',
                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.accentColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(bool isDark, Color headingColor, Color bodyColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 44, color: (isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody).withOpacity(0.6)),
            const SizedBox(height: 18),
            Text(
              'Could not load salons',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: headingColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 14, color: bodyColor),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _loadEverything,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: Text('Retry', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}