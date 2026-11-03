import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/bottom_clearance.dart';
import 'feedback_states.dart';

/// Where the customer chooses where they are, the way delivery apps do it:
/// "use my current location" first, the places they used before, then a city
/// and — optionally — an area inside it.
///
/// Salons are always filtered by the CITY; the area is what the header shows.
/// Only cities with salons are listed, with how many, so the choice is
/// informed rather than hopeful. Returns true when the place changed, so the
/// caller knows whether to reload.
Future<bool> showCityPicker(BuildContext context) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Over the navigation pill, not behind it: the list runs to the bottom of
    // the sheet and the last rows have to stay tappable.
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CityPickerSheet(),
  );

  return changed ?? false;
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet();

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _search = TextEditingController();
  List<ServiceCity> _all = [];
  List<RecentPlace> _recent = [];
  bool _loading = true;
  bool _locating = false;

  /// Step two: the city whose areas are being shown.
  ServiceCity? _city;
  List<ServiceArea> _areas = [];
  bool _loadingAreas = false;
  String _areasError = '';

  /// Why "use my location" did not work (permission refused, services off),
  /// shown under the button. A SnackBar would appear behind this sheet.
  String? _locationProblem;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final recent = await LocationService.instance.recentPlaces();
    try {
      final cities = await LocationService.instance.fetchCities();
      if (!mounted) return;
      setState(() {
        _all = cities;
        _recent = recent;
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recent = recent;
        _error = 'Could not load cities. Check your connection.';
        _loading = false;
      });
    }
  }

  String get _term => _search.text.trim().toLowerCase();

  /// Filtered on the device: the serviceable list is short, so a round trip per
  /// keystroke would be slower than it is worth.
  List<ServiceCity> get _visibleCities => _term.isEmpty
      ? _all
      : _all.where((c) => c.name.toLowerCase().contains(_term) || c.state.toLowerCase().contains(_term)).toList();

  List<ServiceArea> get _visibleAreas =>
      _term.isEmpty ? _areas : _areas.where((a) => a.name.toLowerCase().contains(_term)).toList();

  /// Let the device pick the city and name the area, and say so plainly when
  /// it cannot. Location is a shortcut, never a requirement — a refusal
  /// leaves the list below fully usable rather than blocking the screen.
  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locationProblem = null;
    });

    final before = _placeKey();
    final problem = await LocationService.instance.useCurrentLocation();

    if (!mounted) return;
    setState(() => _locating = false);

    // "Not in your area yet" still switched the city: say so, then close.
    if (problem != null && LocationService.instance.city == null) {
      setState(() => _locationProblem = problem);
      return;
    }
    if (problem != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(problem)));
    }
    Navigator.pop(context, before != _placeKey());
  }

  String _placeKey() => '${LocationService.instance.city?.id}|${LocationService.instance.area}';

  /// Step two: show this city's areas. A city with none is chosen straight away.
  Future<void> _openCity(ServiceCity city) async {
    setState(() {
      _city = city;
      _areas = [];
      _areasError = '';
      _loadingAreas = true;
      _search.clear();
    });
    try {
      final areas = await LocationService.instance.fetchAreas(city.id);
      if (!mounted || _city?.id != city.id) return;
      if (areas.isEmpty) {
        await _choose(city, null);
        return;
      }
      setState(() {
        _areas = areas;
        _loadingAreas = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _areasError = 'Could not load areas. You can still choose the whole city.';
        _loadingAreas = false;
      });
    }
  }

  Future<void> _choose(ServiceCity city, String? area) async {
    final before = _placeKey();
    await LocationService.instance.setCity(city, area: area);

    if (!mounted) return;
    Navigator.pop(context, before != _placeKey());
  }

  void _back() => setState(() {
        _city = null;
        _search.clear();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inCity = _city != null;

    return PopScope(
      // Back from the area step returns to the cities, not out of the sheet.
      canPop: !inCity,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inCity) _back();
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(inCity ? 8 : 20, 14, 20, 4),
                child: Row(
                  children: [
                    if (inCity)
                      IconButton(
                        key: const ValueKey('location_back'),
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: _back,
                        tooltip: 'Back to cities',
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(inCity ? 'Choose your area in ${_city!.name}' : 'Choose your location',
                              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            inCity
                                ? 'You will see salons across ${_city!.name}, nearest first.'
                                : 'We will show you salons in your city that you can actually book.',
                            style: GoogleFonts.outfit(
                                fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!inCity) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('use_current_location'),
                      onPressed: _locating ? null : _useMyLocation,
                      icon: _locating
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location, size: 18),
                      label: Text(_locating ? 'Finding you…' : 'Use my current location'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accentColor,
                        side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
                if (_locationProblem != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: InlineStatus(
                      message: _locationProblem!,
                      kind: StatusKind.warning,
                      onDismiss: () => setState(() => _locationProblem = null),
                    ),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: TextField(
                  key: const ValueKey('location_search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: inCity ? 'Search area in ${_city!.name}' : 'Search city or state',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: theme.cardColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              Expanded(child: inCity ? _buildAreas(scrollController) : _buildCities(scrollController)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
        child: Text(text.toUpperCase(),
            style: GoogleFonts.outfit(
                fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: context.colors.textSecondary)),
      );

  Widget _buildCities(ScrollController controller) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) return _message(Icons.cloud_off, _error, action: _load);

    final cities = _visibleCities;
    final selectedId = LocationService.instance.city?.id;
    final selectedArea = LocationService.instance.area;
    final recent = _term.isEmpty ? _recent : <RecentPlace>[];

    if (cities.isEmpty && recent.isEmpty) {
      return _message(
        Icons.location_off_outlined,
        _term.isEmpty
            ? 'No cities are live yet.'
            : 'We are not in “${_search.text.trim()}” yet.\nWe are adding cities all the time.',
      );
    }

    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + sheetBottomInset(context)),
      children: [
        if (recent.isNotEmpty) ...[
          _sectionTitle('Recent'),
          for (final place in recent)
            ListTile(
              key: ValueKey('recent_${place.city.id}_${place.area ?? ''}'),
              onTap: () => _choose(place.city, place.area),
              leading: const Icon(Icons.history_rounded),
              title: Text(place.title, style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              subtitle: Text(place.subtitle, style: GoogleFonts.outfit(fontSize: 12)),
              trailing: place.city.id == selectedId && place.area == selectedArea
                  ? const Icon(Icons.check_circle, color: AppTheme.accentColor)
                  : null,
            ),
          _sectionTitle('Cities'),
        ],
        for (final city in cities) ...[
          ListTile(
            key: ValueKey('city_${city.id}'),
            onTap: () => _openCity(city),
            leading: CircleAvatar(
              backgroundColor:
                  city.id == selectedId ? AppTheme.accentColor : AppTheme.accentColor.withValues(alpha: 0.12),
              child: Icon(Icons.location_city_rounded,
                  size: 20, color: city.id == selectedId ? context.colors.onAccent : AppTheme.accentColor),
            ),
            title: Text(city.name,
                style: GoogleFonts.outfit(fontWeight: city.id == selectedId ? FontWeight.bold : FontWeight.w600)),
            subtitle: Text('${city.state} · ${city.salonCount} salon${city.salonCount == 1 ? '' : 's'}',
                style: GoogleFonts.outfit(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
          const Divider(height: 1, indent: 60),
        ],
      ],
    );
  }

  Widget _buildAreas(ScrollController controller) {
    final city = _city!;
    if (_loadingAreas) return const Center(child: CircularProgressIndicator());

    final areas = _visibleAreas;
    final selectedArea = LocationService.instance.city?.id == city.id ? LocationService.instance.area : null;

    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + sheetBottomInset(context)),
      children: [
        if (_term.isEmpty)
          ListTile(
            key: const ValueKey('whole_city'),
            onTap: () => _choose(city, null),
            leading: const Icon(Icons.public_rounded, color: AppTheme.accentColor),
            title: Text('All of ${city.name}', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
            subtitle: Text('${city.salonCount} salon${city.salonCount == 1 ? '' : 's'}',
                style: GoogleFonts.outfit(fontSize: 12)),
            trailing: LocationService.instance.city?.id == city.id && selectedArea == null
                ? const Icon(Icons.check_circle, color: AppTheme.accentColor)
                : null,
          ),
        if (_areasError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: InlineStatus(message: _areasError, kind: StatusKind.warning),
          ),
        if (areas.isNotEmpty) _sectionTitle('Areas'),
        for (final area in areas)
          ListTile(
            key: ValueKey('area_${area.id}'),
            onTap: () => _choose(city, area.name),
            leading: const Icon(Icons.place_outlined),
            title: Text(area.name,
                style: GoogleFonts.outfit(fontWeight: area.name == selectedArea ? FontWeight.bold : FontWeight.w500)),
            trailing: area.name == selectedArea ? const Icon(Icons.check_circle, color: AppTheme.accentColor) : null,
          ),
        if (_term.isNotEmpty && areas.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No area called “${_search.text.trim()}” in ${city.name}.',
                textAlign: TextAlign.center, style: GoogleFonts.outfit(color: context.colors.textSecondary)),
          ),
      ],
    );
  }

  Widget _message(IconData icon, String text, {VoidCallback? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: context.colors.iconIdle),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: GoogleFonts.outfit(color: context.colors.textSecondary)),
              if (action != null) ...[
                const SizedBox(height: 12),
                TextButton(onPressed: action, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      );
}
