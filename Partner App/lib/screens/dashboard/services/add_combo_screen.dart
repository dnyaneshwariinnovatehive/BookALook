import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../../services/service_management_api.dart';
import '../../../../models/service_models.dart';

class AddComboScreen extends StatefulWidget {
  final String salonId;
  const AddComboScreen({super.key, required this.salonId});

  @override
  State<AddComboScreen> createState() => _AddComboScreenState();
}

class _AddComboScreenState extends State<AddComboScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  bool _isLoading = true;
  String? _error;
  List<SalonService> _availableServices = [];
  
  // Selected services and their special prices
  final List<Map<String, dynamic>> _selectedServices = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  Future<void> _fetchServices() async {
    try {
      final grouped = await ServiceManagementApi.getSalonServices(widget.salonId);
      final List<SalonService> allServices = [];
      for (var group in grouped) {
        final servicesList = group['services'] as List;
        allServices.addAll(servicesList.map((s) => SalonService.fromJson(s)));
      }
      setState(() {
        _availableServices = allServices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }
  
  void _addServiceRow() {
    setState(() {
      _selectedServices.add({'service_id': null, 'special_price': 0.0});
    });
  }

  Future<void> _saveCombo() async {
    if (!_formKey.currentState!.validate()) return;
    
    final validServices = _selectedServices.where((s) => s['service_id'] != null).toList();
    if (validServices.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least 2 services for a combo')));
      return;
    }

    setState(() { _isSaving = true; });
    try {
      await ServiceManagementApi.createCombo(
        salonId: widget.salonId,
        name: _nameController.text,
        services: validServices,
      );
      if (mounted) {
        Navigator.pop(context, true);
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
        title: const Text('Add Combo'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _buildBody(),
      bottomNavigationBar: _isLoading ? null : Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _isSaving ? null : _saveCombo,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Create Combo', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Combo Name', border: OutlineInputBorder()),
            validator: (v) => v!.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 24),
          const Text('Services Included:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          
          ..._selectedServices.asMap().entries.map((entry) {
            int idx = entry.key;
            Map<String, dynamic> item = entry.value;
            
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Select Service'),
                      value: item['service_id'],
                      items: _availableServices.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text('${s.template?.name} (\u20B9${s.price.toStringAsFixed(0)})'),
                      )).toList(),
                      onChanged: (val) {
                        setState(() {
                          item['service_id'] = val;
                          final selectedService = _availableServices.firstWhere((s) => s.id == val);
                          item['special_price'] = selectedService.price; // Default to original price
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (item['service_id'] != null)
                      TextFormField(
                        decoration: const InputDecoration(labelText: 'Combo Price (\u20B9)', prefixIcon: Icon(Icons.currency_rupee, size: 16)),
                        initialValue: item['special_price'].toString(),
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          item['special_price'] = double.tryParse(val) ?? 0.0;
                        },
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() { _selectedServices.removeAt(idx); });
                        },
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text('Remove', style: TextStyle(color: Colors.red)),
                      ),
                    )
                  ],
                ),
              ),
            );
          }),
          
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _addServiceRow,
            icon: const Icon(Icons.add),
            label: const Text('Add Service to Combo'),
          )
        ],
      ),
    );
  }
}
