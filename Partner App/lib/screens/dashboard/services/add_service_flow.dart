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
        customCategoryName: _customCategoryController.text.isNotEmpty ? _customCategoryController.text : null,
        customTemplateName: _customTemplateController.text.isNotEmpty ? _customTemplateController.text : null,
        estimatedDurationMinutes: _durationController.text.isNotEmpty ? int.parse(_durationController.text) : null,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Service'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Text(_error!))
          : _buildFlow(),
    );
  }

  Widget _buildFlow() {
    // Step 1: Pick Category
    if (_selectedCategory == null && !_isCustom) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('1. Pick a Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ..._masterCategories.map((c) => ListTile(
            title: Text(c.name),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              setState(() {
                _selectedCategory = c;
              });
            },
          )),
          const Divider(),
          ListTile(
            title: const Text('Create Custom Category', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.add, color: AppTheme.accentColor),
            onTap: () {
              setState(() {
                _isCustom = true;
              });
            },
          )
        ],
      );
    }

    // Step 2: Pick Template
    if (_selectedCategory != null && _selectedTemplate == null && !_isCustom) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('2. Select a Service under ${_selectedCategory!.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...(_selectedCategory!.templates ?? []).map((t) => ListTile(
            title: Text(t.name),
            subtitle: Text('${t.estimatedDurationMinutes} mins'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              setState(() {
                _selectedTemplate = t;
              });
            },
          )),
          const Divider(),
          ListTile(
            title: const Text('Create Custom Service here', style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.add, color: AppTheme.accentColor),
            onTap: () {
              setState(() {
                _isCustom = true;
              });
            },
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: () => setState(() => _selectedCategory = null), child: const Text('Back to Categories'))
        ],
      );
    }

    // Step 3: Set Price & Details (Standard or Custom)
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_isCustom ? 'Create Custom Service' : 'Set Price for ${_selectedTemplate!.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),

          if (_isCustom) ...[
            if (_selectedCategory == null) ...[
              TextFormField(
                controller: _customCategoryController,
                decoration: const InputDecoration(labelText: 'New Category Name', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text('Category: ${_selectedCategory!.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
            ],
            
            TextFormField(
              controller: _customTemplateController,
              decoration: const InputDecoration(labelText: 'Service Name', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _durationController,
              decoration: const InputDecoration(labelText: 'Estimated Duration (minutes)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
          ],

          TextFormField(
            controller: _priceController,
            decoration: const InputDecoration(labelText: 'Price (₹)', border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
            validator: (v) => v!.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Description (Optional)', border: OutlineInputBorder()),
            maxLines: 3,
          ),
          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: _isSaving ? null : _saveService,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Service', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              setState(() {
                if (_isCustom) {
                  _isCustom = false;
                  if (_selectedTemplate == null) _selectedCategory = null;
                } else {
                  _selectedTemplate = null;
                }
              });
            }, 
            child: const Text('Back')
          )
        ],
      ),
    );
  }
}
