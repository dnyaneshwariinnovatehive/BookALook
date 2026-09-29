import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../services/salon_settings_api.dart';

class EditSalonProfileScreen extends StatefulWidget {
  final Map<String, dynamic> salonData;

  const EditSalonProfileScreen({super.key, required this.salonData});

  @override
  State<EditSalonProfileScreen> createState() => _EditSalonProfileScreenState();
}

class _EditSalonProfileScreenState extends State<EditSalonProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _descriptionController;
  late TextEditingController _addressController;
  late TextEditingController _pincodeController;
  String _selectedGenderFocus = 'Unisex';
  
  final List<String> _genderOptions = ['Unisex', 'Male', 'Female'];
  
  bool _isLoading = false;
  File? _selectedImage;
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.salonData['name']?.toString() ?? '');
    
    final phone = widget.salonData['phone'] ?? widget.salonData['phone_number'] ?? widget.salonData['contact_number'] ?? '';
    _phoneController = TextEditingController(text: phone.toString());
    
    _descriptionController = TextEditingController(text: widget.salonData['description']?.toString() ?? '');
    _addressController = TextEditingController(text: widget.salonData['address']?.toString() ?? '');
    _pincodeController = TextEditingController(text: widget.salonData['pincode']?.toString() ?? '');
    
    final gender = widget.salonData['gender_focus']?.toString() ?? 'Unisex';
    if (_genderOptions.contains(gender)) {
      _selectedGenderFocus = gender;
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      await SalonSettingsApi.updateSalonProfile(
        salonId: widget.salonData['id'].toString(),
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        description: _descriptionController.text.trim(),
        address: _addressController.text.trim(),
        pincode: _pincodeController.text.trim(),
        genderFocus: _selectedGenderFocus,
        imagePath: _selectedImage?.path,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Edit Basic Details'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image Picker
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: isDark ? theme.dividerColor : theme.dividerColor.withOpacity(0.5),
                      shape: BoxShape.circle,
                      image: _selectedImage != null
                          ? (!kIsWeb ? DecorationImage(
                              image: FileImage(_selectedImage!),
                              fit: BoxFit.cover,
                            ) : null)
                          : (widget.salonData['cover_image'] != null
                              ? DecorationImage(
                                  image: NetworkImage(widget.salonData['cover_image']),
                                  fit: BoxFit.cover,
                                )
                              : null),
                    ),
                    child: _selectedImage == null && widget.salonData['cover_image'] == null
                        ? Icon(Icons.storefront, size: 60, color: theme.colorScheme.onSurface.withOpacity(0.3))
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.scaffoldBackgroundColor, width: 3),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Form Fields
            _buildTextField('Salon Name', _nameController, isRequired: true),
            const SizedBox(height: 20),
            _buildTextField('Phone Number', _phoneController, keyboardType: TextInputType.phone),
            const SizedBox(height: 20),
            _buildTextField('Description', _descriptionController, maxLines: 3),
            const SizedBox(height: 20),
            _buildTextField('Street Address', _addressController, maxLines: 2),
            const SizedBox(height: 20),
            _buildTextField('Pincode', _pincodeController, keyboardType: TextInputType.number),
            const SizedBox(height: 20),
            _buildDropdown('Gender Focus', _selectedGenderFocus, _genderOptions, (val) {
              setState(() {
                _selectedGenderFocus = val!;
              });
            }),
            
            const SizedBox(height: 40),

            // Save Button
            ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(color: theme.colorScheme.surface, strokeWidth: 2),
                    )
                  : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isRequired = false, int maxLines = 1, TextInputType keyboardType = TextInputType.text, bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (isRequired)
              const Text(' *', style: TextStyle(color: Colors.red, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          readOnly: readOnly,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            filled: true,
            fillColor: readOnly ? Theme.of(context).disabledColor.withOpacity(0.1) : Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options, void Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: options.map((String option) {
                return DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
