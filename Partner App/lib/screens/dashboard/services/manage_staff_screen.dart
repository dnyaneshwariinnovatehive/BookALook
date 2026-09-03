import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../../services/service_management_api.dart';

class ManageStaffScreen extends StatefulWidget {
  final String salonId;
  final String serviceId;
  final String serviceName;

  const ManageStaffScreen({
    super.key,
    required this.salonId,
    required this.serviceId,
    required this.serviceName,
  });

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _allStaff = [];
  Set<String> _assignedStaffIds = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchStaff();
  }

  Future<void> _fetchStaff() async {
    try {
      final data = await ServiceManagementApi.getServiceStaff(widget.salonId, widget.serviceId);
      setState(() {
        _allStaff = data['all_staff'];
        _assignedStaffIds = Set<String>.from(data['assigned_staff_ids']);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveStaff() async {
    setState(() { _isSaving = true; });
    try {
      await ServiceManagementApi.assignServiceStaff(
        widget.salonId,
        widget.serviceId,
        _assignedStaffIds.toList(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff updated successfully')));
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
        title: Text('Manage Staff: ${widget.serviceName}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _buildBody(),
      bottomNavigationBar: _allStaff.isNotEmpty && !_isLoading ? Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _isSaving ? null : _saveStaff,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Changes', style: TextStyle(fontSize: 16)),
        ),
      ) : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));
    if (_allStaff.isEmpty) return const Center(child: Text('No staff members found in this salon.'));

    return ListView.builder(
      itemCount: _allStaff.length,
      itemBuilder: (context, index) {
        final staff = _allStaff[index];
        final isAssigned = _assignedStaffIds.contains(staff['id']);
        
        return CheckboxListTile(
          title: Text(staff['user']['first_name'] + ' ' + staff['user']['last_name']),
          subtitle: Text(staff['specialization'] ?? 'Staff'),
          value: isAssigned,
          activeColor: AppTheme.accentColor,
          onChanged: (bool? val) {
            setState(() {
              if (val == true) {
                _assignedStaffIds.add(staff['id']);
              } else {
                _assignedStaffIds.remove(staff['id']);
              }
            });
          },
        );
      },
    );
  }
}
