import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../../services/service_management_api.dart';
import '../../../../models/service_models.dart';

class AddComboScreen extends StatefulWidget {
  final String salonId;
  final Map<String, dynamic>? existingCombo;
  const AddComboScreen({super.key, required this.salonId, this.existingCombo});

  @override
  State<AddComboScreen> createState() => _AddComboScreenState();
}

class _AddComboScreenState extends State<AddComboScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _advanceController = TextEditingController(text: '25'); // Default matching backend
  bool _refundAdvance = false;
  
  bool _isLoading = true;
  String? _error;
  List<SalonService> _availableServices = [];
  
  // Selected services and their special prices
  final List<Map<String, dynamic>> _selectedServices = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingCombo != null) {
      _nameController.text = widget.existingCombo!['name'] ?? '';
      _advanceController.text = (widget.existingCombo!['advance_percentage'] ?? 25).toString();
      final refundVal = widget.existingCombo!['will_refund_advance_if_cancelled'];
      _refundAdvance = refundVal == 1 || refundVal == true;

      final servicesList = widget.existingCombo!['services'] as List?;
      if (servicesList != null) {
        for (var s in servicesList) {
          _selectedServices.add({
            'service_id': s['id'],
            'special_price': double.tryParse(s['pivot']['combo_special_price']?.toString() ?? '0') ?? 0.0,
          });
        }
      }
    }
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
      if (widget.existingCombo != null) {
        await ServiceManagementApi.updateCombo(
          salonId: widget.salonId,
          comboId: widget.existingCombo!['id'],
          name: _nameController.text,
          services: validServices,
          advancePercentage: double.tryParse(_advanceController.text),
          willRefundAdvanceIfCancelled: _refundAdvance,
        );
      } else {
        await ServiceManagementApi.createCombo(
          salonId: widget.salonId,
          name: _nameController.text,
          services: validServices,
          advancePercentage: double.tryParse(_advanceController.text),
          willRefundAdvanceIfCancelled: _refundAdvance,
        );
      }
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
        title: Text(widget.existingCombo != null ? 'Edit Combo' : 'Add Combo'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (widget.existingCombo != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Combo'),
                    content: const Text('Are you sure you want to delete this combo?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  setState(() => _isLoading = true);
                  try {
                    await ServiceManagementApi.deleteCombo(widget.salonId, widget.existingCombo!['id']);
                    if (mounted) Navigator.pop(context, true);
                  } catch (e) {
                    setState(() => _isLoading = false);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
            ),
        ],
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
          child: _isSaving ? CircularProgressIndicator(color: Theme.of(context).colorScheme.surface) : Text(widget.existingCombo != null ? 'Save Changes' : 'Create Combo', style: TextStyle(fontSize: 16)),
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
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _advanceController,
            decoration: const InputDecoration(labelText: 'Min Advance %', border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
            validator: (v) => v!.isEmpty ? 'Required' : null,
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
              const Text('Refund advance if cancelled', style: TextStyle(fontSize: 14)),
            ],
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
