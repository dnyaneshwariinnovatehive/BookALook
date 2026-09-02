import 'package:flutter/material.dart';
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
  
  String _genderFocus = 'Unisex';
  
  List<dynamic> _cities = [];
  String? _selectedCityId;
  bool _isLoadingCities = true;

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
        _isLoadingCities = false;
      });
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      // Append state to address to respect the schema
      String fullStreet = _addressController.text.trim();
      if (_stateController.text.trim().isNotEmpty) {
        fullStreet += ', ' + _stateController.text.trim();
      }

      widget.onNext({
        'salon_name': _salonNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'street_address': fullStreet,
        'city_id': _selectedCityId,
        'pincode': _pincodeController.text.trim(),
        'gender_focus': _genderFocus,
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
            const Text(
              'Salon Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tell us about your salon.',
              style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
            ),
            const SizedBox(height: 24),

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
                hintStyle: const TextStyle(color: Colors.black26),
                prefixIcon: const Icon(Icons.description_outlined, color: Colors.black38, size: 20),
                filled: true,
                fillColor: Colors.white,
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
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('City *'),
                      if (_isLoadingCities)
                        const Center(child: CircularProgressIndicator())
                      else
                        DropdownButtonFormField<String>(
                          value: _selectedCityId,
                          decoration: InputDecoration(
                            hintText: 'City',
                            hintStyle: const TextStyle(color: Colors.black26),
                            prefixIcon: const Icon(Icons.location_city_outlined, color: Colors.black38, size: 20),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accentColor)),
                          ),
                          items: _cities.map<DropdownMenuItem<String>>((city) {
                            return DropdownMenuItem<String>(
                              value: city['id'],
                              child: Text(city['name'] + (city['state'] != null ? ' (\${city['state']})' : '')),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedCityId = val;
                            });
                          },
                          validator: (v) => v == null ? 'Required' : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('State *'),
                      _buildTextField(
                        controller: _stateController,
                        hint: 'State',
                        icon: Icons.map_outlined,
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
                    child: const Text('Back', style: TextStyle(color: AppTheme.lightTextBody)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Next'),
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
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
        hintStyle: const TextStyle(color: Colors.black26),
        prefixIcon: Icon(icon, color: Colors.black38, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.lightBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.accentColor)),
      ),
    );
  }
}
