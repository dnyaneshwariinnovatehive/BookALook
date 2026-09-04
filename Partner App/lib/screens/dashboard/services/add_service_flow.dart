import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../../models/service_models.dart';
import '../../../../services/service_management_api.dart';

class AddServiceFlow extends StatefulWidget {
  final String salonId;
  const AddServiceFlow({super.key, required this.salonId});

  @override
  State<AddServiceFlow> createState() => _AddServiceFlowState();
}

class _AddServiceFlowState extends State<AddServiceFlow> {
  bool _isLoading = true;
  List<ServiceCategory> _masterCategories = [];
  String? _error;

  // Selected state
  ServiceCategory? _selectedCategory;
  ServiceTemplate? _selectedTemplate;
  bool _isCustom = false;

  // Controllers for custom and pricing
  final _customCategoryController = TextEditingController();
  final _customTemplateController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController(); // For custom
  final _advanceController = TextEditingController(text: '20'); // Added advance controller

  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchMasterCatalog();
  }

  Future<void> _fetchMasterCatalog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final categories = await ServiceManagementApi.getMasterCatalog(widget.salonId);
      setState(() {
        _masterCategories = categories;
        if (_selectedCategory == null && _masterCategories.isNotEmpty) {
          _selectedCategory = _masterCategories.first;
          if (_selectedCategory!.templates != null && _selectedCategory!.templates!.isNotEmpty) {
            _selectedTemplate = _selectedCategory!.templates!.first;
            _isCustom = false;
          } else {
            _selectedTemplate = null;
            _isCustom = true;
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveService() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() { _isSaving = true; });

    try {
      await ServiceManagementApi.addService(
        salonId: widget.salonId,
        isCustom: _isCustom,
        templateId: _selectedTemplate?.id,
        price: double.parse(_priceController.text),
        description: _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
        categoryId: _selectedCategory?.id ?? 'new_custom',
        customCategoryName: _isCustom && _customCategoryController.text.isNotEmpty ? _customCategoryController.text : null,
        customTemplateName: _isCustom && _customTemplateController.text.isNotEmpty ? _customTemplateController.text : null,
        estimatedDurationMinutes: _isCustom && _durationController.text.isNotEmpty ? int.parse(_durationController.text) : null,
        advancePercentage: _advanceController.text.isNotEmpty ? double.tryParse(_advanceController.text) : null,
        genderFocus: _genderFocus,
        willRefundAdvanceIfCancelled: _refundAdvance,
      );

      if (mounted) {
        Navigator.pop(context, true); // true indicates success
      }
    } catch (e) {
      setState(() { _isSaving = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Add Service', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Text(_error!))
          : _buildForm(),
    );
  }

  int _duration = 30;
  String _genderFocus = 'Unisex';
  bool _refundAdvance = false;

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLabel('Category'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ServiceCategory>(
                isExpanded: true,
                value: _selectedCategory ?? (_masterCategories.isNotEmpty ? _masterCategories.first : null),
                items: _masterCategories.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCategory = val;
                    if (val != null && val.templates != null && val.templates!.isNotEmpty) {
                      _selectedTemplate = val.templates!.first;
                      _isCustom = false;
                    } else {
                      _selectedTemplate = null;
                      _isCustom = true;
                    }
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          _buildLabel('Template'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ServiceTemplate?>(
                isExpanded: true,
                value: _isCustom ? null : _selectedTemplate,
                items: [
                  if (_selectedCategory?.templates != null)
                    ..._selectedCategory!.templates!.map((t) => DropdownMenuItem(value: t, child: Text(t.name))),
                  const DropdownMenuItem(value: null, child: Text('➕ Create Custom Service', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                onChanged: (val) {
                  setState(() {
                    if (val == null) {
                      _isCustom = true;
                      _selectedTemplate = null;
                    } else {
                      _isCustom = false;
                      _selectedTemplate = val;
                    }
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_isCustom) ...[
            _buildLabel('Name'),
            _buildTextField(_customTemplateController),
            const SizedBox(height: 16),
          ],

          
          _buildLabel('Description'),
          _buildTextField(_descriptionController),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Price (₹)'),
                    _buildTextField(_priceController, isNumber: true),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Duration (min)'),
                    if (_isCustom)
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove, size: 18),
                              onPressed: () {
                                if (_duration > 30) setState(() => _duration -= 30);
                              },
                            ),
                            Text('$_duration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(
                              icon: Icon(Icons.add, size: 18),
                              onPressed: () {
                                setState(() => _duration += 30);
                              },
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 48,
                        width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${_selectedTemplate?.estimatedDurationMinutes ?? 30}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildLabel('Min Advance %'),
          _buildTextField(_advanceController, isNumber: true),
          const SizedBox(height: 16),
          
          // Category dropdown was moved up
          
          _buildLabel('Gender Focus'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _genderFocus,
                items: ['Unisex', 'Men Only', 'Women Only'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (val) {
                  setState(() => _genderFocus = val!);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _refundAdvance,
                  onChanged: (val) => setState(() => _refundAdvance = val!),
                  activeColor: AppTheme.accentColor,
                ),
              ),
              const SizedBox(width: 8),
              Text('Refund advance if cancelled', style: TextStyle(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 32),
          
          ElevatedButton(
            onPressed: _isSaving ? null : () {
              // Ensure we save properly using the single form data
              if (_isCustom) {
                _durationController.text = _duration.toString();
              }
              _saveService();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E1E2C), // Dark solid button
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _isSaving 
              ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.surface, strokeWidth: 2)) 
              : Text('Add Service', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Builder(
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).textTheme.bodyLarge?.color ?? Theme.of(context).colorScheme.onSurface.withOpacity(0.87))),
        );
      }
    );
  }

  Widget _buildTextField(TextEditingController controller, {bool isNumber = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.accentColor),
        ),
      ),
      validator: (v) => v!.isEmpty ? 'Required' : null,
    );
  }
}
