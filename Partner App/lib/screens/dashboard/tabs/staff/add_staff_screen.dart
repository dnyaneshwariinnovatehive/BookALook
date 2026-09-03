import 'package:flutter/material.dart';
import '../../../../models/staff_models.dart';
import '../../../../models/service_models.dart';
import '../../../../services/staff_api.dart';
import '../../../../services/service_management_api.dart';
import '../../../../services/salon_settings_api.dart';
import '../../../../models/salon_working_hour.dart';
import '../../../../theme/app_theme.dart';

class AddStaffScreen extends StatefulWidget {
  final String salonId;
  const AddStaffScreen({super.key, required this.salonId});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  // Form Fields
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _salaryController = TextEditingController();
  final _commissionController = TextEditingController();

  // Services
  List<Map<String, dynamic>> _salonServicesGrouped = [];
  final Set<String> _selectedServiceIds = {};

  // Working Hours
  bool _useSalonWorkingHours = true;
  List<SalonWorkingHour> _salonWorkingHours = [];
  final List<StaffWorkingHour> _workingHours = List.generate(7, (index) => StaffWorkingHour(
    dayOfWeek: index,
    isWeeklyOff: index == 0, // Sunday off by default
    shiftStart: index == 0 ? null : '09:00:00',
    shiftEnd: index == 0 ? null : '18:00:00',
  ));

  final List<String> _daysOfWeek = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      final services = await ServiceManagementApi.getSalonServices(widget.salonId);
      final hours = await SalonSettingsApi.fetchWorkingHours(widget.salonId);
      setState(() {
        _salonServicesGrouped = services;
        _salonWorkingHours = hours;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load data: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveStaff() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    try {
      await StaffApi.addStaff(
        salonId: widget.salonId,
        name: _nameController.text,
        phone: _phoneController.text,
        email: _emailController.text.isNotEmpty ? _emailController.text : null,
        specialization: null,
        baseSalary: double.tryParse(_salaryController.text) ?? 0,
        commissionPercentage: double.tryParse(_commissionController.text) ?? 0,
        serviceIds: _selectedServiceIds.toList(),
        workingHours: _useSalonWorkingHours 
            ? _salonWorkingHours.map((h) => StaffWorkingHour(
                dayOfWeek: h.dayOfWeek,
                isWeeklyOff: h.isClosed,
                shiftStart: h.openTime,
                shiftEnd: h.closeTime,
              )).toList()
            : _workingHours,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff added successfully')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _selectTime(StaffWorkingHour hour, bool isStart) async {
    TimeOfDay initialTime = const TimeOfDay(hour: 9, minute: 0);
    String? currentStr = isStart ? hour.shiftStart : hour.shiftEnd;
    
    if (currentStr != null && currentStr.isNotEmpty) {
      final parts = currentStr.split(':');
      if (parts.length >= 2) {
        initialTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0);
      }
    }

    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: initialTime);
    if (picked != null) {
      final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
      setState(() {
        if (isStart) hour.shiftStart = formatted;
        else hour.shiftEnd = formatted;
      });
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'Select';
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      int h = int.tryParse(parts[0]) ?? 0;
      int m = int.tryParse(parts[1]) ?? 0;
      final tod = TimeOfDay(hour: h, minute: m);
      String period = tod.hour >= 12 ? 'PM' : 'AM';
      int displayHour = tod.hour > 12 ? tod.hour - 12 : (tod.hour == 0 ? 12 : tod.hour);
      return '${displayHour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')} $period';
    }
    return timeStr;
  }

  void _showServicesModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Select Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                if (_selectedServiceIds.isEmpty) {
                                  // Select all
                                  for (var group in _salonServicesGrouped) {
                                    for (var svc in group['services']) {
                                      _selectedServiceIds.add(svc['id'].toString());
                                    }
                                  }
                                } else {
                                  // Deselect all
                                  _selectedServiceIds.clear();
                                }
                              });
                              setState(() {});
                            },
                            child: Text(_selectedServiceIds.isEmpty ? 'Select All' : 'Deselect All'),
                          )
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: _salonServicesGrouped.map((group) {
                          return ExpansionTile(
                            title: Text(group['category']['name'] ?? 'Category'),
                            children: (group['services'] as List).map<Widget>((svc) {
                              final serviceId = svc['id'].toString();
                              final isSelected = _selectedServiceIds.contains(serviceId);
                              return CheckboxListTile(
                                title: Text(svc['template']?['name'] ?? svc['name'] ?? 'Service'),
                                subtitle: Text('₹${svc['price']}'),
                                value: isSelected,
                                onChanged: (val) {
                                  setModalState(() {
                                    if (val == true) _selectedServiceIds.add(serviceId);
                                    else _selectedServiceIds.remove(serviceId);
                                  });
                                  setState(() {});
                                },
                              );
                            }).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text('Done', style: TextStyle(fontSize: 16)),
                      ),
                    )
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Service Provider')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Service Provider'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Basic Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email (Optional)', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _salaryController,
                    decoration: const InputDecoration(labelText: 'Base Salary (₹)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _commissionController,
                    decoration: const InputDecoration(labelText: 'Commission (%)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            const Text('Assigned Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedServiceIds.length} services selected',
                    style: const TextStyle(fontSize: 16),
                  ),
                  ElevatedButton(
                    onPressed: _salonServicesGrouped.isEmpty ? null : _showServicesModal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Select Services'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            const Text('Working Hours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('Use same working hours as salon'),
              value: _useSalonWorkingHours,
              onChanged: (val) {
                setState(() => _useSalonWorkingHours = val ?? true);
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            if (!_useSalonWorkingHours) ...[
              const SizedBox(height: 16),
              const Text('Advanced Customization', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._workingHours.map((hour) => _buildDayRow(hour)),
            ],
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _isSaving ? null : _saveStaff,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save Provider', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildDayRow(StaffWorkingHour hour) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_daysOfWeek[hour.dayOfWeek], style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Text(hour.isWeeklyOff ? 'Off' : 'Working', style: TextStyle(color: hour.isWeeklyOff ? Colors.red : Colors.green)),
                  Switch(
                    value: !hour.isWeeklyOff,
                    activeColor: Colors.green,
                    onChanged: (val) {
                      setState(() {
                        hour.isWeeklyOff = !val;
                        if (hour.isWeeklyOff) {
                          hour.shiftStart = null;
                          hour.shiftEnd = null;
                        } else {
                          hour.shiftStart = '09:00:00';
                          hour.shiftEnd = '18:00:00';
                        }
                      });
                    },
                  ),
                ],
              )
            ],
          ),
          if (!hour.isWeeklyOff)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectTime(hour, true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Shift Start', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(_formatTime(hour.shiftStart), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectTime(hour, false),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Shift End', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(_formatTime(hour.shiftEnd), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
