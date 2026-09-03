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
  
  void _showMultiSelectDropdown() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Services'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: _availableServices.map((service) {
                    final isSelected = _selectedServices.any((s) => s['service_id'] == service.id);
                    return CheckboxListTile(
                      title: Text('${service.template?.name} (\u20B9${service.price.toStringAsFixed(0)})'),
                      value: isSelected,
                      onChanged: (val) {
                        setDialogState(() {
                          setState(() {
                            if (val == true) {
                              _selectedServices.add({
                                'service_id': service.id,
                                'special_price': service.price,
                              });
                            } else {
                              _selectedServices.removeWhere((s) => s['service_id'] == service.id);
                            }
                          });
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
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
          
          OutlinedButton.icon(
            onPressed: _showMultiSelectDropdown,
            icon: const Icon(Icons.arrow_drop_down),
            label: const Text('Select Services from Dropdown'),
          ),
          const SizedBox(height: 16),
          
          ..._selectedServices.asMap().entries.map((entry) {
            int idx = entry.key;
            Map<String, dynamic> item = entry.value;
            final selectedService = _availableServices.firstWhere((s) => s.id == item['service_id']);
            
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selectedService.template?.name} (Original: \u20B9${selectedService.price.toStringAsFixed(0)})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
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
        ],
      ),
    );
  }
}
