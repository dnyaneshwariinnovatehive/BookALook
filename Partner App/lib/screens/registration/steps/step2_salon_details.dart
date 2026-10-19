import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import '../../../services/salon_location_api.dart';
import '../../../../theme/app_theme.dart';
import '../../../../services/api_service.dart';
import '../../../widgets/sub_area_dropdown.dart';

class Step2SalonDetails extends StatefulWidget {
  final Function(Map<String, dynamic>) onNext;
  final VoidCallback onBack;
  final Map<String, dynamic>? initialData;

  const Step2SalonDetails({super.key, required this.onNext, required this.onBack, this.initialData});

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

  final List<String> _photoPaths = [];
  int _coverIndex = 0;

  String _commercialModel = 'subscription';
  String? _selectedPlanId;
  final _commissionController = TextEditingController();
  List<dynamic> _subscriptionPlans = [];
  
  List<dynamic> _cities = [];
  List<String> _states = [];
  List<dynamic> _filteredCities = [];
  
  String? _selectedCityId;
  String? _selectedSubAreaId;
  String? _selectedState;
  bool _isLoadingCities = true;

  bool get _useDropdowns => _cities.isNotEmpty && _states.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _salonNameController.text = widget.initialData!['salon_name'] ?? '';
      _descriptionController.text = widget.initialData!['description'] ?? '';
      _addressController.text = widget.initialData!['street_address'] ?? widget.initialData!['address'] ?? '';
      _pincodeController.text = widget.initialData!['pincode'] ?? '';
      if (widget.initialData!['gender_focus'] != null) {
        _genderFocus = widget.initialData!['gender_focus'];
      }
      if (widget.initialData!['preferred_commercial_model'] != null) {
        _commercialModel = widget.initialData!['preferred_commercial_model'];
      }
      if (widget.initialData!['preferred_plan_id'] != null) {
        _selectedPlanId = widget.initialData!['preferred_plan_id']?.toString();
      }
      if (widget.initialData!['requested_commission_percentage'] != null) {
        _commissionController.text = widget.initialData!['requested_commission_percentage'].toString();
      }
    }
    _loadCitiesAndPlans();
  }

  @override
  void dispose() {
    _commissionController.dispose();
    _salonNameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _loadCitiesAndPlans() async {
    final results = await Future.wait([
      ApiService.fetchCities(),
      ApiService.getSubscriptionPlans(),
    ]);

    if (mounted) {
      final cities = results[0];
      final plans = results[1];

      setState(() {
        _cities = cities;
        _subscriptionPlans = plans;
        if (_cities.isNotEmpty) {
          final statesSet = <String>{};
          for (var city in _cities) {
            if (city['state'] != null && city['state'].toString().trim().isNotEmpty) {
              statesSet.add(city['state'].toString().trim());
            }
          }
          _states = statesSet.toList()..sort();

          if (widget.initialData != null && widget.initialData!['city_id'] != null) {
            _selectedCityId = widget.initialData!['city_id']?.toString();
            final city = _cities.firstWhere((c) => c['id'].toString() == _selectedCityId, orElse: () => null);
            if (city != null && city['state'] != null) {
              _selectedState = city['state']?.toString().trim();
              _filteredCities = _cities.where((c) => c['state']?.toString().trim() == _selectedState).toList();
            }
            _selectedSubAreaId = widget.initialData!['sub_area_id']?.toString();
          }
        }
        _isLoadingCities = false;
      });
    }
  }

  void _onStateChanged(String? newState) {
    setState(() {
      _selectedState = newState;
      _selectedCityId = null;
      // The old area belonged to the old city.
      _selectedSubAreaId = null;
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

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), 
      content: Text(position == null
          ? 'Could not read your location. You can add it later from More > Salon Location.'
          : 'Location captured. Nearby customers will see you at the right distance.'),
    ));
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      // Mandatory photo & cover photo check
      final hasExistingCover = widget.initialData?['cover_photo_url'] != null;
      if (_photoPaths.isEmpty && !hasExistingCover) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(milliseconds: 2500),
            content: Text('Please upload at least one salon photo and select a main cover photo.'),
          ),
        );
        return;
      }

      // Commission model validation
      double? reqRate;
      if (_commercialModel == 'commission') {
        final rawRate = _commissionController.text.trim();
        reqRate = double.tryParse(rawRate);
        if (reqRate == null || reqRate < 0 || reqRate > 100) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(milliseconds: 2500),
              content: Text('Please enter a valid requested commission rate between 0% and 100%.'),
            ),
          );
          return;
        }
      }

      // Append state to address to respect the schema
      String stateVal = _useDropdowns ? (_selectedState ?? '') : _stateController.text.trim();
      String fullStreet = _addressController.text.trim();
      if (stateVal.isNotEmpty) {
        fullStreet += ', ' + stateVal;
      }

      if (_useDropdowns && _selectedSubAreaId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Please choose the area your salon is in')),
        );
        return;
      }

      widget.onNext({
        if (widget.initialData?['salon_id'] != null) 'salon_id': widget.initialData!['salon_id'],
        'salon_name': _salonNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'street_address': fullStreet,
        'city_id': _useDropdowns ? _selectedCityId : null,
        'sub_area_id': _selectedSubAreaId,
        if (!_useDropdowns) 'city_name': _cityController.text.trim(),
        'pincode': _pincodeController.text.trim(),
        'gender_focus': _genderFocus,
        if (_latitude != null) 'latitude': _latitude,
        if (_longitude != null) 'longitude': _longitude,
        'preferred_plan_id': _selectedPlanId,
        'preferred_commercial_model': _commercialModel,
        if (_commercialModel == 'commission' && reqRate != null) 'requested_commission_percentage': reqRate,
        'photo_paths': _photoPaths,
        'cover_index': _coverIndex,
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
                              _selectedSubAreaId = null;
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

            if (_useDropdowns) ...[
              _buildLabel('Area *'),
              SubAreaDropdown(
                cityId: _selectedCityId,
                value: _selectedSubAreaId,
                onChanged: (val) => setState(() => _selectedSubAreaId = val),
              ),
              const SizedBox(height: 16),
            ],

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
            const SizedBox(height: 20),

            _buildPhotoSection(),
            const SizedBox(height: 24),

            _buildCommercialSection(),
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

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (picked == null) return;

    if (!mounted) return;
    setState(() {
      _photoPaths.add(picked.path);
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _photoPaths.removeAt(index);
      if (_coverIndex >= _photoPaths.length) {
        _coverIndex = _photoPaths.isEmpty ? 0 : _photoPaths.length - 1;
      }
    });
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildLabel('Salon Photos & Main Cover Photo *'),
            if (_photoPaths.isNotEmpty)
              Text(
                '${_photoPaths.length} photo${_photoPaths.length == 1 ? '' : 's'} added',
                style: const TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Upload photos of your storefront or interior. Tap any photo to select it as the Main Cover Photo.',
          style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _photoPaths.length; i++) _buildPhotoTile(i, _photoPaths[i]),
            if (_photoPaths.length < 10) _buildAddPhotoTile(),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotoTile(int index, String path) {
    final isCover = index == _coverIndex;

    return GestureDetector(
      onTap: () {
        setState(() => _coverIndex = index);
      },
      child: Stack(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCover ? AppTheme.accentColor : AppTheme.lightBorder,
                width: isCover ? 2.5 : 1,
              ),
              image: DecorationImage(
                image: kIsWeb ? NetworkImage(path) as ImageProvider : FileImage(File(path)),
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (isCover)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '★ Cover',
                  style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: () => _removePhoto(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddPhotoTile() => GestureDetector(
        onTap: _addPhoto,
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.lightBorder, style: BorderStyle.solid),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: AppTheme.accentColor, size: 24),
              SizedBox(height: 4),
              Text('Add photo', style: TextStyle(fontSize: 11, color: AppTheme.lightTextBody)),
            ],
          ),
        ),
      );

  Widget _buildCommercialSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Commercial Model *'),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _commercialModel = 'subscription'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _commercialModel == 'subscription' ? AppTheme.accentColor.withOpacity(0.1) : Colors.white,
                    border: Border.all(color: _commercialModel == 'subscription' ? AppTheme.accentColor : AppTheme.lightBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Subscription Plan',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _commercialModel == 'subscription' ? FontWeight.bold : FontWeight.normal,
                      color: _commercialModel == 'subscription' ? AppTheme.accentColor : AppTheme.lightTextBody,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _commercialModel = 'commission'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _commercialModel == 'commission' ? AppTheme.accentColor.withOpacity(0.1) : Colors.white,
                    border: Border.all(color: _commercialModel == 'commission' ? AppTheme.accentColor : AppTheme.lightBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Commission Model',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _commercialModel == 'commission' ? FontWeight.bold : FontWeight.normal,
                      color: _commercialModel == 'commission' ? AppTheme.accentColor : AppTheme.lightTextBody,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildLabel('Preferred Subscription Plan (Optional)'),
        DropdownButtonFormField<String>(
          value: _selectedPlanId,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: 'Select preferred plan',
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.26)),
            prefixIcon: Icon(Icons.card_membership_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), size: 20),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accentColor)),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Not sure yet (Choose after approval)'),
            ),
            ..._subscriptionPlans.map((p) => DropdownMenuItem<String>(
                  value: p['id'].toString(),
                  child: Text('${p['name']} (₹${p['price']} / ${p['validity_days'] ?? p['duration_days'] ?? 30} days)'),
                )),
          ],
          onChanged: (val) => setState(() => _selectedPlanId = val),
        ),
        const SizedBox(height: 6),
        const Text(
          'Preference only — your actual subscription purchase happens after SuperAdmin approval.',
          style: TextStyle(fontSize: 11, color: AppTheme.lightTextBody),
        ),
        const SizedBox(height: 16),

        if (_commercialModel == 'commission') ...[
          _buildLabel('Requested Commission Rate (%) *'),
          _buildTextField(
            controller: _commissionController,
            hint: 'e.g. 15.0',
            icon: Icons.percent,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              if (_commercialModel == 'commission') {
                if (v == null || v.trim().isEmpty) return 'Required for commission model';
                final n = double.tryParse(v.trim());
                if (n == null || n < 0 || n > 100) return 'Must be between 0 and 100';
              }
              return null;
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'Informational request. SuperAdmin will finalize your approved commission rate upon registration review.',
            style: TextStyle(fontSize: 11, color: AppTheme.lightTextBody),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
