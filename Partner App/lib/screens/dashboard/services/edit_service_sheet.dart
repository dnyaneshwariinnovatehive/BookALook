import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../../models/service_models.dart';
import '../../../../services/service_management_api.dart';
import '../../../../services/insights_api.dart';
import 'manage_staff_screen.dart';

class EditServiceSheet extends StatefulWidget {
  final String salonId;
  final SalonService service;

  const EditServiceSheet({super.key, required this.salonId, required this.service});

  @override
  State<EditServiceSheet> createState() => _EditServiceSheetState();
}

class _EditServiceSheetState extends State<EditServiceSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _priceController;
  late TextEditingController _descriptionController;
  bool _isSaving = false;
  bool _isDeleting = false;

  List<SalonService> _allServices = [];
  List<String> _linkedServiceIds = [];
  SalonInsights? _insights;
  bool _isLoadingExtra = true;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: widget.service.price.toStringAsFixed(0));
    _descriptionController = TextEditingController(text: widget.service.description ?? '');
    _loadExtraData();
  }

  Future<void> _loadExtraData() async {
    try {
      final groupedServices = await ServiceManagementApi.getSalonServices(widget.salonId);
      final List<SalonService> flatServices = [];
      for (var group in groupedServices) {
        if (group['services'] != null) {
          for (var s in group['services']) {
             flatServices.add(SalonService.fromJson(s));
          }
        }
      }
      SalonInsights? insights;
      try {
        insights = await InsightsApi.fetch(widget.salonId);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _allServices = flatServices;
          _insights = insights;
          _isLoadingExtra = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingExtra = false);
    }
  }

  Future<void> _updateService() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSaving = true; });

    try {
      await ServiceManagementApi.updateService(
        salonId: widget.salonId,
        serviceId: widget.service.id,
        price: double.parse(_priceController.text),
        description: _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
        linkedServiceIds: _linkedServiceIds.isNotEmpty ? _linkedServiceIds : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _isSaving = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteService() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Service'),
        content: Text('Are you sure you want to remove this service from your menu?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger)))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() { _isDeleting = true; });

    try {
      await ServiceManagementApi.deleteService(widget.salonId, widget.service.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _isDeleting = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit ${widget.service.template?.name}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _priceController,
              decoration: InputDecoration(labelText: 'Price (₹)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(labelText: 'Description (Optional)', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            if (_isLoadingExtra)
              const Center(child: CircularProgressIndicator())
            else
              _buildLinkedAddonsSection(),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _updateService,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving ? CircularProgressIndicator(color: Theme.of(context).colorScheme.surface) : Text('Update Service', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ManageStaffScreen(
                      salonId: widget.salonId,
                      serviceId: widget.service.id,
                      serviceName: widget.service.template?.name ?? 'Service',
                    ),
                  ),
                );
              },
              icon: Icon(Icons.people),
              label: Text('Manage Assigned Staff'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isDeleting ? null : _deleteService,
              style: TextButton.styleFrom(foregroundColor: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger)),
              child: _isDeleting ? const CircularProgressIndicator() : Text('Delete Service'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedAddonsSection() {
    final theme = Theme.of(context);
    final isAdvanced = _insights?.advanced == true;
    final templateName = widget.service.template?.name ?? '';
    
    // Find smart suggestions
    final List<UpsellTip> smartTips = [];
    if (isAdvanced && _insights != null && templateName.isNotEmpty) {
      smartTips.addAll(_insights!.upsell.where((u) => u.from.toLowerCase() == templateName.toLowerCase()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Linked Add-ons (Upsell)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          'Recommend these services to customers when they book this one.',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6)),
        ),
        const SizedBox(height: 12),
        
        if (isAdvanced && smartTips.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 16),
                    const SizedBox(width: 8),
                    const Text('Smart Suggestions', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6D28D9), fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                ...smartTips.map((tip) {
                  final matchingService = _allServices.where((s) => (s.template?.name.toLowerCase() == tip.to.toLowerCase())).firstOrNull;
                  if (matchingService == null) return const SizedBox.shrink();
                  
                  final isSelected = _linkedServiceIds.contains(matchingService.id);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: Text(tip.to, style: const TextStyle(fontSize: 14)),
                    subtitle: Text('Usually boosts revenue by ${(tip.uplift * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    trailing: isSelected 
                      ? const Icon(Icons.check_circle, color: Color(0xFF8B5CF6))
                      : OutlinedButton(
                          onPressed: () => setState(() => _linkedServiceIds.add(matchingService.id)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF8B5CF6),
                            side: const BorderSide(color: Color(0xFF8B5CF6)),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Add'),
                        ),
                  );
                }).toList(),
              ],
            ),
          ),
          
        // Manual selection
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Select manual add-ons...'),
              value: null,
              items: _allServices
                  .where((s) => s.id != widget.service.id && !_linkedServiceIds.contains(s.id))
                  .map((s) {
                return DropdownMenuItem(
                  value: s.id,
                  child: Text(s.template?.name ?? 'Custom Service'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _linkedServiceIds.add(val));
                }
              },
            ),
          ),
        ),
        
        if (_linkedServiceIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _linkedServiceIds.map((id) {
                final s = _allServices.firstWhere((s) => s.id == id, orElse: () => SalonService(id: id, salonId: '', templateId: '', price: 0));
                return Chip(
                  label: Text(s.template?.name ?? 'Unknown', style: const TextStyle(fontSize: 12)),
                  onDeleted: () => setState(() => _linkedServiceIds.remove(id)),
                  backgroundColor: theme.colorScheme.surface,
                  side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.2)),
                );
              }).toList(),
            ),
          )
      ],
    );
  }
}
