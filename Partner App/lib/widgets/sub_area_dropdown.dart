import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_config.dart';
import '../theme/app_theme.dart';

/// The locality inside a city, loaded from whichever city is selected above it.
///
/// Both places that capture a salon address already had a city dropdown, so
/// this is the second half rather than a replacement: give it the chosen city
/// and it reloads itself, clearing any area that belonged to the previous one.
class SubAreaDropdown extends StatefulWidget {
  final String? cityId;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Painted red once the step has been attempted and this is still empty.
  final bool showError;

  const SubAreaDropdown({
    super.key,
    required this.cityId,
    required this.value,
    required this.onChanged,
    this.showError = false,
  });

  @override
  State<SubAreaDropdown> createState() => _SubAreaDropdownState();
}

class _SubAreaDropdownState extends State<SubAreaDropdown> {
  List<dynamic> _areas = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.cityId != null) _load(widget.cityId!);
  }

  @override
  void didUpdateWidget(SubAreaDropdown old) {
    super.didUpdateWidget(old);

    if (old.cityId != widget.cityId) {
      if (widget.cityId == null) {
        setState(() => _areas = const []);
      } else {
        _load(widget.cityId!);
      }
    }
  }

  Future<void> _load(String cityId) async {
    setState(() {
      _loading = true;
      _areas = const [];
    });

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/cities/$cityId/sub-areas'),
        headers: {'Accept': 'application/json'},
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        setState(() => _areas = body['sub_areas'] as List? ?? const []);
      }
    } catch (_) {
      // An empty list reads as "none listed yet", which is the truth either way.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _hint {
    if (widget.cityId == null) return 'Pick a city first';
    if (_loading) return 'Loading areas…';
    if (_areas.isEmpty) return 'No areas listed for this city yet';
    return 'Select area';
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.showError ? AppTheme.lightDanger : AppTheme.lightBorder;

    return DropdownButtonFormField<String>(
      initialValue: widget.value,
      isExpanded: true,
      hint: Text(_hint,
          style: const TextStyle(color: AppTheme.lightTextLight, fontSize: 13.5)),
      items: _areas
          .map<DropdownMenuItem<String>>((area) => DropdownMenuItem(
                value: area['id'].toString(),
                child: Text(area['name'].toString(), overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: widget.cityId == null || _loading || _areas.isEmpty
          ? null
          : widget.onChanged,
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.map_outlined,
            size: 19, color: widget.showError ? AppTheme.lightDanger : AppTheme.lightTextLight),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: widget.showError ? AppTheme.lightDanger : AppTheme.accentColor)),
      ),
    );
  }
}
