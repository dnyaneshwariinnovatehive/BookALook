import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';

/// Two dependent dropdowns: the city, then the locality inside it.
///
/// A city on its own is too coarse to be useful — "Pune" covers a two-hour
/// drive — so nothing on the platform asks for one without the other. The area
/// list reloads whenever the city changes, and any area already chosen is
/// cleared, because it would now belong to the wrong city.
class CityAreaPicker extends StatefulWidget {
  final String? cityId;
  final String? subAreaId;

  /// Fires with (cityId, subAreaId). Either may be null while the customer is
  /// still choosing.
  final void Function(String? cityId, String? subAreaId) onChanged;

  /// Narrows the lists to places that actually have an open salon. What a
  /// customer picking where to browse should see; a salon registering itself
  /// should not be limited to it.
  final bool serviceableOnly;

  const CityAreaPicker({
    Key? key,
    required this.onChanged,
    this.cityId,
    this.subAreaId,
    this.serviceableOnly = false,
  }) : super(key: key);

  @override
  State<CityAreaPicker> createState() => _CityAreaPickerState();
}

class _CityAreaPickerState extends State<CityAreaPicker> {
  static String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  List<dynamic> _cities = const [];
  List<dynamic> _areas = const [];

  List<String> _states = const [];
  String? _selectedState = 'Maharashtra';

  String? _cityId;
  String? _subAreaId;

  bool _loadingCities = true;
  bool _loadingAreas = false;

  @override
  void initState() {
    super.initState();
    _cityId = widget.cityId;
    _subAreaId = widget.subAreaId;
    _loadCities();
  }

  Future<void> _loadCities() async {
    try {
      final uri = Uri.parse('$_baseUrl/cities')
          .replace(queryParameters: widget.serviceableOnly ? {'serviceable': '1'} : null);
      final response = await http.get(uri, headers: {'Accept': 'application/json'});

      if (!mounted) return;
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final citiesList = decoded is List ? decoded : const [];
        
        final statesSet = <String>{};
        for (var city in citiesList) {
          if (city['state'] != null) {
            statesSet.add(city['state'].toString());
          }
        }
        
        setState(() {
          _cities = citiesList;
          _states = statesSet.toList()..sort();
          if (_cityId != null) {
            final city = _cities.firstWhere((c) => c['id'].toString() == _cityId, orElse: () => null);
            if (city != null && city['state'] != null) {
              _selectedState = city['state'].toString();
            }
          } else if (!_states.contains(_selectedState) && _states.isNotEmpty) {
             _selectedState = _states.first;
          }
        });
      }
    } catch (_) {
      // Left empty; the dropdown says so rather than throwing at the customer.
    } finally {
      if (mounted) setState(() => _loadingCities = false);
      if (_cityId != null) _loadAreas(_cityId!);
    }
  }

  Future<void> _loadAreas(String cityId) async {
    setState(() {
      _loadingAreas = true;
      _areas = const [];
    });

    try {
      final uri = Uri.parse('$_baseUrl/cities/$cityId/sub-areas')
          .replace(queryParameters: widget.serviceableOnly ? {'serviceable': '1'} : null);
      final response = await http.get(uri, headers: {'Accept': 'application/json'});

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        setState(() => _areas = body['sub_areas'] as List? ?? const []);
      }
    } catch (_) {
      // Same again — an empty list reads as "none listed yet".
    } finally {
      if (mounted) setState(() => _loadingAreas = false);
    }
  }

  void _pickState(String? state) {
    setState(() {
      _selectedState = state;
      _cityId = null;
      _subAreaId = null;
      _areas = const [];
    });
    widget.onChanged(null, null);
  }

  void _pickCity(String? cityId) {
    setState(() {
      _cityId = cityId;
      // The old area belongs to the old city.
      _subAreaId = null;
      _areas = const [];
    });

    widget.onChanged(cityId, null);
    if (cityId != null) _loadAreas(cityId);
  }

  void _pickArea(String? subAreaId) {
    setState(() => _subAreaId = subAreaId);
    widget.onChanged(_cityId, subAreaId);
  }

  @override
  Widget build(BuildContext context) {
    final filteredCities = _selectedState == null 
        ? const [] 
        : _cities.where((c) => c['state']?.toString() == _selectedState).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: _states.contains(_selectedState) ? _selectedState : null,
          isExpanded: true,
          decoration: _decoration(
            'State *',
            Icons.map,
            _loadingCities ? 'Loading states…' : 'Select your state',
          ),
          items: _states
              .map<DropdownMenuItem<String>>((state) => DropdownMenuItem(
                    value: state,
                    child: Text(state, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: _loadingCities ? null : _pickState,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: filteredCities.any((c) => c['id'].toString() == _cityId) ? _cityId : null,
          isExpanded: true,
          decoration: _decoration(
            'City *',
            Icons.location_city_outlined,
            _loadingCities ? 'Loading cities…' : 'Select your city',
          ),
          items: filteredCities
              .map<DropdownMenuItem<String>>((city) => DropdownMenuItem(
                    value: city['id'].toString(),
                    child: Text(city['name'].toString(),
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (_loadingCities || _selectedState == null) ? null : _pickCity,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _areas.any((a) => a['id'].toString() == _subAreaId) ? _subAreaId : null,
          isExpanded: true,
          decoration: _decoration('Area *', Icons.map_outlined, _areaHint),
          items: _areas
              .map<DropdownMenuItem<String>>((area) => DropdownMenuItem(
                    value: area['id'].toString(),
                    child: Text(area['name'].toString(), overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: _cityId == null || _loadingAreas || _areas.isEmpty ? null : _pickArea,
        ),
      ],
    );
  }

  String get _areaHint {
    if (_cityId == null) return 'Choose a city first';
    if (_loadingAreas) return 'Loading areas…';
    if (_areas.isEmpty) return 'No areas listed for this city yet';
    return 'Select your area';
  }

  InputDecoration _decoration(String label, IconData icon, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: GoogleFonts.outfit(fontSize: 13.5, color: AppTheme.lightTextLight),
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      );
}
