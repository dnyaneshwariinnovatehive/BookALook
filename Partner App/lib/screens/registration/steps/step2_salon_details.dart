import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../../services/salon_location_api.dart';
import '../../../../theme/app_theme.dart';
import '../../../../services/api_service.dart';

class Step2SalonDetails extends StatefulWidget {
  final Function(Map<String, dynamic>) onNext;
  final VoidCallback onBack;

  const Step2SalonDetails({super.key, required this.onNext, required this.onBack});

  @override
  State<Step2SalonDetails> createState() => _Step2SalonDetailsState();
}

class _Step2SalonDetailsState extends State<Step2SalonDetails> {
  final _formKey = GlobalKey<FormState>();
  final _salonNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  /// Where the salon is. Optional at sign-up, and null until the owner taps.
  double? _latitude;
  double? _longitude;
  bool _locating = false;
  
  String _genderFocus = 'Unisex';
  
  List<dynamic> _cities = [];
  List<String> _states = [];
  List<dynamic> _filteredCities = [];
  
  String? _selectedCityId;
  String? _selectedState;
  bool _isLoadingCities = true;

  bool get _useDropdowns => _cities.isNotEmpty && _states.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    final cities = await ApiService.fetchCities();
    if (mounted) {
      setState(() {
        _cities = cities;
        if (_cities.isNotEmpty) {
          final statesSet = <String>{};
          for (var city in _cities) {
            if (city['state'] != null && city['state'].toString().trim().isNotEmpty) {
              statesSet.add(city['state'].toString().trim());
            }
          }
          _states = statesSet.toList()..sort();
        }
        _isLoadingCities = false;
      });
    }
  }

  void _onStateChanged(String? newState) {
    setState(() {
      _selectedState = newState;
      _selectedCityId = null;
      if (newState != null) {
        _filteredCities = _cities.where((c) => c['state']?.toString().trim() == newState).toList();
      } else {
        _filteredCities = [];
      }
    });
  }

  /// Read the owner's position, if they are standing in the salon.
  ///
  /// Never blocks registration: plenty of owners sign up from home, and a
  /// missing pin is a thing to fix later rather than a reason to stop.
  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);

    final position = await SalonLocationApi.devicePosition();

    if (!mounted) return;

    setState(() {
      _locating = false;
      _latitude = position?.latitude;
      _longitude = position?.longitude;
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(position == null
          ? 'Could not read your location. You can add it later from More > Salon Location.'
          : 'Location captured. Nearby customers will see you at the right distance.'),
    ));
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      // Append state to address to respect the schema
      String stateVal = _useDropdowns ? (_selectedState ?? '') : _stateController.text.trim();
      String fullStreet = _addressController.text.trim();
      if (stateVal.isNotEmpty) {
        fullStreet += ', ' + stateVal;
      }

      widget.onNext({
        'salon_name': _salonNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'street_address': fullStreet,
        'city_id': _useDropdowns ? _selectedCityId : null,
        if (!_useDropdowns) 'city_name': _cityController.text.trim(),
        'pincode': _pincodeController.text.trim(),
        'gender_focus': _genderFocus,
        // Optional. Customers browse nearest-first, so a salon that pins itself
        // at sign-up is placed correctly from its first day. Skipping it is
        // fine — the owner can pin later from More > Salon Location.
        if (_latitude != null) 'latitude': _latitude,
        if (_longitude != null) 'longitude': _longitude,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Salon Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
            ),
            const SizedBox(height: 4),
            Text(
              'Tell us about your salon.',
              style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
            ),
            const SizedBox(height: 24),

            _buildLocationCard(),
            const SizedBox(height: 20),

            _buildLabel('Salon Name *'),
            _buildTextField(
              controller: _salonNameController,
              hint: 'Salon name',
              icon: Icons.storefront_outlined,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            _buildLabel('Description'),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Brief description of your salon...',
                hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.26)),
                prefixIcon: Icon(Icons.description_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), size: 20),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accentColor)),
              ),
            ),
            const SizedBox(height: 16),

            _buildLabel('Address *'),
            _buildTextField(
              controller: _addressController,
              hint: 'Street address',
              icon: Icons.location_on_outlined,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('State *'),
                      if (_isLoadingCities)
                        const Center(child: CircularProgressIndicator())
                      else if (_useDropdowns)
                        DropdownButtonFormField<String>(
                          value: _selectedState,
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText: 'State',
                            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.26)),
                            prefixIcon: Icon(Icons.map_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), size: 20),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accentColor)),
                          ),
                          items: _states.map((state) {
                            return DropdownMenuItem<String>(
                              value: state,
                              child: Text(state, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: _onStateChanged,
                          validator: (v) => v == null ? 'Required' : null,
                        )
                      else
                        _buildTextField(
                          controller: _stateController,
                          hint: 'State',
                          icon: Icons.map_outlined,
                          validator: (v) => v!.isEmpty ? 'Required' : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('City *'),
                      if (_isLoadingCities)
                        const Center(child: CircularProgressIndicator())
                      else if (_useDropdowns)
                        DropdownButtonFormField<String>(
                          value: _selectedCityId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText: 'City',
                            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.26)),
                            prefixIcon: Icon(Icons.location_city_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), size: 20),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accentColor)),
                          ),
                          items: _filteredCities.map<DropdownMenuItem<String>>((city) {
                            return DropdownMenuItem<String>(
                              value: city['id'].toString(),
                              child: Text(city['name'].toString(), overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedCityId = val;
                            });
                          },
                          validator: (v) => v == null ? 'Required' : null,
                        )
                      else
                        _buildTextField(
                          controller: _cityController,
                          hint: 'City',
                          icon: Icons.location_city_outlined,
                          validator: (v) => v!.isEmpty ? 'Required' : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildLabel('Pincode *'),
            _buildTextField(
              controller: _pincodeController,
              hint: 'Pincode',
              icon: Icons.pin_drop_outlined,
              keyboardType: TextInputType.number,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            _buildLabel('Gender Focus *'),
            Row(
              children: [
                _buildGenderToggle('Unisex'),
                const SizedBox(width: 8),
                _buildGenderToggle('Men Only'),
                const SizedBox(width: 8),
                _buildGenderToggle('Women Only'),
              ],
            ),
            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onBack,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppTheme.lightBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Back', style: TextStyle(color: AppTheme.lightTextBody)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).colorScheme.onSurface,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Next'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildGenderToggle(String label) {
    bool isSelected = _genderFocus == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _genderFocus = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentColor.withOpacity(0.1) : Colors.white,
            border: Border.all(color: isSelected ? AppTheme.accentColor : AppTheme.lightBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppTheme.accentColor : AppTheme.lightTextBody,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.26)),
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), size: 20),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accentColor)),
      ),
    );
  }

  /// Offer to pin the salon while the owner is likely standing in it.
  Widget _buildLocationCard() {
    final captured = _latitude != null && _longitude != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: captured
            ? AppTheme.lightSuccessBg
            : AppTheme.accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: captured
              ? AppTheme.lightSuccess.withValues(alpha: 0.4)
              : AppTheme.accentColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(captured ? Icons.check_circle : Icons.place_outlined,
              size: 20,
              color: captured ? AppTheme.lightSuccess : AppTheme.accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  captured ? 'Location captured' : 'Pin your salon (optional)',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  captured
                      ? '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                      : 'Customers see the nearest salons first. Tap while you are '
                          'at the salon — you can also do this later.',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppTheme.lightTextBody),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _locating ? null : _useCurrentLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 16),
                  label: Text(
                    _locating
                        ? 'Finding you…'
                        : captured
                            ? 'Update'
                            : 'Use my current location',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentColor,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
