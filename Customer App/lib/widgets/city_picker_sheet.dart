import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

/// Where the customer chooses which city they are shopping in.
///
/// Shows only cities with salons in them, and says how many, so the choice is
/// informed rather than hopeful. Returns true when the city changed, so the
/// caller knows whether to reload.
Future<bool> showCityPicker(BuildContext context) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
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
  bool _loading = true;
  bool _locating = false;
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
    try {
      final cities = await LocationService.instance.fetchCities();
      if (!mounted) return;
      setState(() {
        _all = cities;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load cities. Check your connection.';
        _loading = false;
      });
    }
  }

  /// Filtered on the device: the serviceable list is short, so a round trip per
  /// keystroke would be slower than it is worth.
  List<ServiceCity> get _visible {
    final term = _search.text.trim().toLowerCase();

    if (term.isEmpty) return _all;

    return _all
        .where((c) =>
            c.name.toLowerCase().contains(term) ||
            c.state.toLowerCase().contains(term))
        .toList();
  }

  /// Let the device pick the city, and say so plainly when it cannot.
  ///
  /// Location is a shortcut, never a requirement — a refusal leaves the list
  /// below fully usable rather than blocking the screen.
  Future<void> _useMyLocation() async {
    setState(() => _locating = true);

    final problem = await LocationService.instance.useCurrentLocation();

    if (!mounted) return;
    setState(() => _locating = false);

    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    Navigator.pop(context, true);
  }

  Future<void> _choose(ServiceCity city) async {
    final previous = LocationService.instance.city?.id;
    await LocationService.instance.setCity(city);

    if (!mounted) return;
    Navigator.pop(context, previous != city.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedId = LocationService.instance.city?.id;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
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
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choose your city',
                      style: GoogleFonts.outfit(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'We will show you salons you can actually book.',
                    style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 18),
                  label: Text(_locating ? 'Finding you…' : 'Use my current location'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                    side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search city or state',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: theme.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody(scrollController, selectedId)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController controller, String? selectedId) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return _message(Icons.cloud_off, _error, action: _load);
    }

    final cities = _visible;

    if (cities.isEmpty) {
      return _message(
        Icons.location_off_outlined,
        _search.text.trim().isEmpty
            ? 'No cities are live yet.'
            : 'We are not in “${_search.text.trim()}” yet.\nWe are adding cities all the time.',
      );
    }

    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: cities.length,
      separatorBuilder: (context, index) => const Divider(height: 1, indent: 60),
      itemBuilder: (context, i) {
        final city = cities[i];
        final selected = city.id == selectedId;

        return ListTile(
          onTap: () => _choose(city),
          leading: CircleAvatar(
            backgroundColor: selected
                ? AppTheme.accentColor
                : AppTheme.accentColor.withValues(alpha: 0.12),
            child: Icon(Icons.location_city_rounded,
                size: 20,
                color: selected ? Colors.white : AppTheme.accentColor),
          ),
          title: Text(city.name,
              style: GoogleFonts.outfit(
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600)),
          subtitle: Text(
            '${city.state} · ${city.salonCount} salon${city.salonCount == 1 ? '' : 's'}',
            style: GoogleFonts.outfit(fontSize: 12),
          ),
          trailing: selected
              ? const Icon(Icons.check_circle, color: AppTheme.accentColor)
              : null,
        );
      },
    );
  }

  Widget _message(IconData icon, String text, {VoidCallback? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.grey.shade700)),
              if (action != null) ...[
                const SizedBox(height: 12),
                TextButton(onPressed: action, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      );
}
