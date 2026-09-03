import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../../models/service_models.dart';
import '../../../../services/service_management_api.dart';
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

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: widget.service.price.toStringAsFixed(0));
    _descriptionController = TextEditingController(text: widget.service.description ?? '');
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
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _isSaving = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteService() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Service'),
        content: const Text('Are you sure you want to remove this service from your menu?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
            Text('Edit ${widget.service.template?.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
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
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _updateService,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Update Service', style: TextStyle(fontSize: 16)),
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
              icon: const Icon(Icons.people),
              label: const Text('Manage Assigned Staff'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isDeleting ? null : _deleteService,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: _isDeleting ? const CircularProgressIndicator() : const Text('Delete Service'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
