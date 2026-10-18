import 'package:flutter/material.dart';
import '../../../../models/admin_provider_models.dart';
import '../../../../models/salon_working_hour.dart';
import '../../../../models/staff_models.dart';
import '../../../../services/admin_provider_api.dart';
import '../../../../services/salon_settings_api.dart';
import '../../../../services/service_management_api.dart';
import '../../../../theme/app_theme.dart';

class AdminProviderConfigSheet extends StatefulWidget {
  final String salonId;
  final AdminProviderStatus? initialStatus;
  final List<Map<String, dynamic>>? initialServices;
  final List<SalonWorkingHour>? initialSalonHours;

  const AdminProviderConfigSheet({
    super.key,
    required this.salonId,
    this.initialStatus,
    this.initialServices,
    this.initialSalonHours,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String salonId,
    AdminProviderStatus? initialStatus,
  }) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminProviderConfigSheet(
          salonId: salonId,
          initialStatus: initialStatus,
        ),
      ),
    );
  }

  @override
  State<AdminProviderConfigSheet> createState() => _AdminProviderConfigSheetState();
}

class _AdminProviderConfigSheetState extends State<AdminProviderConfigSheet> {
  final _formKey = GlobalKey<FormState>();
  final _specializationController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  List<Map<String, dynamic>> _salonServicesGrouped = [];
  final Set<String> _selectedServiceIds = {};

  bool _useSalonHours = true;
  List<SalonWorkingHour> _salonWorkingHours = [];
  List<StaffWorkingHour> _workingHours = List.generate(
    7,
    (index) => StaffWorkingHour(
      dayOfWeek: index,
      isWeeklyOff: index == 0,
      shiftStart: index == 0 ? null : '09:00:00',
      shiftEnd: index == 0 ? null : '18:00:00',
    ),
  );

  final List<String> _daysOfWeek = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday'
  ];

  @override
  void initState() {
    super.initState();
    _initFromStatus(widget.initialStatus);
    _loadData();
  }

  void _initFromStatus(AdminProviderStatus? status) {
    final profile = status?.provider;
    if (profile != null) {
      _specializationController.text = profile.specialization ?? 'Owner & Specialist';
      _selectedServiceIds.clear();
      for (final s in profile.services) {
        _selectedServiceIds.add(s.id);
      }
      if (profile.workingHours.length == 7) {
        _workingHours = profile.workingHours.map((h) => h.copy()).toList();
      }
    } else {
      _specializationController.text = 'Owner & Specialist';
    }
  }

  Future<void> _loadData() async {
    if (widget.initialServices != null && widget.initialSalonHours != null) {
      if (!mounted) return;
      setState(() {
        _salonServicesGrouped = widget.initialServices!;
        _salonWorkingHours = widget.initialSalonHours!;
        if (widget.initialStatus?.provider != null && widget.initialStatus!.provider!.workingHours.isNotEmpty) {
          _useSalonHours = _matchesSalonHours();
        } else {
          _useSalonHours = true;
        }
        _isLoading = false;
      });
      return;
    }

    try {
      final services = await ServiceManagementApi.getSalonServices(widget.salonId);
      final hoursResponse = await SalonSettingsApi.fetchWorkingHours(widget.salonId);
      final salonHours = (hoursResponse['hours'] as List<SalonWorkingHour>?) ?? [];

      if (!mounted) return;

      setState(() {
        _salonServicesGrouped = services;
        _salonWorkingHours = salonHours;

        if (widget.initialStatus?.provider != null && widget.initialStatus!.provider!.workingHours.isNotEmpty) {
          _useSalonHours = _matchesSalonHours();
        } else {
          _useSalonHours = true;
        }

        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 2500),
            content: Text('Failed to load services and timings: $e'),
          ),
        );
      }
    }
  }

  bool _matchesSalonHours() {
    if (_salonWorkingHours.length != 7) return false;
    for (int i = 0; i < 7; i++) {
      final sh = _salonWorkingHours.firstWhere((h) => h.dayOfWeek == i);
      final wh = _workingHours.firstWhere((h) => h.dayOfWeek == i);
      if (sh.isClosed != wh.isWeeklyOff) return false;
      if (!sh.isClosed) {
        if (wh.shiftStart == null || wh.shiftEnd == null) return false;
        final shStart = StaffWorkingHour.normaliseTime(sh.openTime);
        final shEnd = StaffWorkingHour.normaliseTime(sh.closeTime);
        if (wh.shiftStart != shStart || wh.shiftEnd != shEnd) return false;
      }
    }
    return true;
  }

  void _applySalonHoursToLocal() {
    if (_salonWorkingHours.length == 7) {
      for (final sh in _salonWorkingHours) {
        final wh = _workingHours.firstWhere((h) => h.dayOfWeek == sh.dayOfWeek);
        wh.isWeeklyOff = sh.isClosed;
        wh.shiftStart = sh.isClosed ? null : StaffWorkingHour.normaliseTime(sh.openTime);
        wh.shiftEnd = sh.isClosed ? null : StaffWorkingHour.normaliseTime(sh.closeTime);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedServiceIds.isEmpty) {
      final proceedWithoutServices = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Services Selected'),
          content: const Text(
            'You have not selected any services. Customers will not be able to book you until services are assigned. Save anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go Back'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );
      if (proceedWithoutServices != true) return;
    }

    setState(() => _isSaving = true);
    try {
      await AdminProviderApi.toggle(
        salonId: widget.salonId,
        enabled: true,
        specialization: _specializationController.text.trim(),
        serviceIds: _selectedServiceIds.toList(),
        useSalonHours: _useSalonHours,
        workingHours: _useSalonHours ? null : _workingHours,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(milliseconds: 2500),
            content: Text('Admin provider settings saved successfully.'),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 2500),
            content: Text('Failed to save settings: $e'),
          ),
        );
      }
    }
  }

  void _openServicePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;

            int allServicesCount = 0;
            for (final g in _salonServicesGrouped) {
              allServicesCount += (g['services'] as List).length;
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (_, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Select Services (${_selectedServiceIds.length}/$allServicesCount)',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  if (_selectedServiceIds.length < allServicesCount) {
                                    for (final g in _salonServicesGrouped) {
                                      for (final s in (g['services'] as List)) {
                                        _selectedServiceIds.add(s['id'].toString());
                                      }
                                    }
                                  } else {
                                    _selectedServiceIds.clear();
                                  }
                                });
                                setState(() {});
                              },
                              child: Text(
                                _selectedServiceIds.length < allServicesCount ? 'Select All' : 'Deselect All',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
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
                              initiallyExpanded: true,
                              title: Text(
                                group['category']['name'] ?? 'Category',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              children: (group['services'] as List).map<Widget>((svc) {
                                final sId = svc['id'].toString();
                                final isSelected = _selectedServiceIds.contains(sId);
                                return CheckboxListTile(
                                  title: Text(svc['template']?['name'] ?? svc['name'] ?? 'Service'),
                                  subtitle: Text('₹${svc['price']}'),
                                  value: isSelected,
                                  activeColor: AppTheme.accentColor,
                                  onChanged: (val) {
                                    setModalState(() {
                                      if (val == true) {
                                        _selectedServiceIds.add(sId);
                                      } else {
                                        _selectedServiceIds.remove(sId);
                                      }
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
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentColor,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Done', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      )
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _selectTime(StaffWorkingHour hour, bool isStart) async {
    TimeOfDay initial = const TimeOfDay(hour: 9, minute: 0);
    final currentStr = isStart ? hour.shiftStart : hour.shiftEnd;
    if (currentStr != null && currentStr.isNotEmpty) {
      final parts = currentStr.split(':');
      if (parts.length >= 2) {
        initial = TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0);
      }
    }

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
      setState(() {
        if (isStart) {
          hour.shiftStart = formatted;
        } else {
          hour.shiftEnd = formatted;
        }
      });
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '--:--';
    try {
      final parts = timeStr.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:${minute.toString().padLeft(2, '0')} $period';
    } catch (_) {
      return timeStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final cardBg = theme.colorScheme.surface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Provider Mode Setup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.accentColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: AppTheme.accentColor, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Configure the services you personally perform and your working timetable. Customers will be able to book appointments with you accordingly.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Specialization
                  Text('Specialization / Title', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: headingColor)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _specializationController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Master Stylist, Grooming Expert',
                      filled: true,
                      fillColor: cardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.dividerColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.dividerColor)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
                  ),
                  const SizedBox(height: 24),

                  // Services Card
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.content_cut, color: AppTheme.accentColor, size: 20),
                                const SizedBox(width: 8),
                                Text('Services Offered', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: headingColor)),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: _openServicePicker,
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Manage'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_selectedServiceIds.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No services assigned. You will not receive bookings.',
                                    style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Text(
                            '${_selectedServiceIds.length} service(s) selected',
                            style: TextStyle(fontSize: 14, color: isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Working Hours Card
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.schedule, color: AppTheme.accentColor, size: 20),
                            const SizedBox(width: 8),
                            Text('Working Hours & Shifts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: headingColor)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Material(
                          color: Colors.transparent,
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Use Salon Working Hours', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: const Text('Automatically sync your availability with the salon schedule'),
                            value: _useSalonHours,
                            activeColor: AppTheme.accentColor,
                            onChanged: (val) {
                              setState(() {
                                _useSalonHours = val;
                                if (val) {
                                  _applySalonHoursToLocal();
                                }
                              });
                            },
                          ),
                        ),
                        if (!_useSalonHours) ...[
                          const Divider(height: 24),
                          Text('Custom Schedule (7 Days)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: headingColor)),
                          const SizedBox(height: 12),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: 7,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (_, index) {
                              final hour = _workingHours.firstWhere((h) => h.dayOfWeek == index);
                              return _buildDayRow(hour, index);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Save Button
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Save & Apply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildDayRow(StaffWorkingHour hour, int dayIndex) {
    final theme = Theme.of(context);
    final dayName = _daysOfWeek[dayIndex];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Row(
                children: [
                  const Text('Weekly Off', style: TextStyle(fontSize: 12)),
                  Checkbox(
                    value: hour.isWeeklyOff,
                    activeColor: AppTheme.accentColor,
                    onChanged: (val) {
                      setState(() {
                        hour.isWeeklyOff = val ?? false;
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
              ),
            ],
          ),
          if (!hour.isWeeklyOff) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectTime(hour, true),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Shift Start', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                          const SizedBox(height: 4),
                          Text(_formatTime(hour.shiftStart), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectTime(hour, false),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Shift End', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                          const SizedBox(height: 4),
                          Text(_formatTime(hour.shiftEnd), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
