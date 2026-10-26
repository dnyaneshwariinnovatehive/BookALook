import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../../../../models/salon_working_hour.dart';
import '../../../../../services/salon_settings_api.dart';
import '../../../../../models/staff_models.dart';
import '../../../../../services/staff_api.dart';
import '../../../../../widgets/staff_hours_review_sheet.dart';

class SalonTimingsScreen extends StatefulWidget {
  final String salonId;
  const SalonTimingsScreen({super.key, required this.salonId});

  @override
  State<SalonTimingsScreen> createState() => _SalonTimingsScreenState();
}

class _SalonTimingsScreenState extends State<SalonTimingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<SalonWorkingHour> _workingHours = [];

  /// The week as loaded, so a save can tell which days actually changed.
  List<SalonWorkingHour> _savedHours = [];
  String? _error;

  final List<String> _daysOfWeek = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];

  @override
  void initState() {
    super.initState();
    _fetchWorkingHours();
  }

  Future<void> _fetchWorkingHours() async {
    try {
      final response = await SalonSettingsApi.fetchWorkingHours(widget.salonId);
      final hours = response['hours'] as List<SalonWorkingHour>;
      if (mounted) {
        setState(() {
          _workingHours = hours;
          _savedHours = hours.map(_copyHour).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  SalonWorkingHour _copyHour(SalonWorkingHour h) => SalonWorkingHour(
        dayOfWeek: h.dayOfWeek,
        isClosed: h.isClosed,
        openTime: h.openTime,
        closeTime: h.closeTime,
      );

  Future<void> _saveWorkingHours() async {
    for (final hour in _workingHours) {
      if (!hour.isClosed) {
        if (hour.openTime == null || hour.closeTime == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(milliseconds: 2500),
              content: Text('Please set opening and closing hours for ${_daysOfWeek[hour.dayOfWeek]}.'),
            ),
          );
          return;
        }

        final openParts = hour.openTime!.split(':');
        final closeParts = hour.closeTime!.split(':');
        if (openParts.length >= 2 && closeParts.length >= 2) {
          final openMinutes = (int.tryParse(openParts[0]) ?? 0) * 60 + (int.tryParse(openParts[1]) ?? 0);
          final closeMinutes = (int.tryParse(closeParts[0]) ?? 0) * 60 + (int.tryParse(closeParts[1]) ?? 0);
          if (closeMinutes <= openMinutes) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(milliseconds: 2500),
                content: Text('Closing time must be after opening time for ${_daysOfWeek[hour.dayOfWeek]}.'),
              ),
            );
            return;
          }
        }
      }
    }

    setState(() => _isSaving = true);
    try {
      final changes = salonHourChanges(_savedHours, _workingHours);
      final result = await SalonSettingsApi.updateWorkingHours(widget.salonId, _workingHours);
      if (!mounted) return;

      // Staff on salon hours were moved by the server. Staff on their own
      // hours are asked about just the days that changed. A staff list that
      // will not load never blocks the save itself.
      List<StaffMember> staff = const [];
      if (changes.isNotEmpty) {
        try {
          staff = (await StaffApi.fetchStaff(widget.salonId)).where((s) => s.isActive).toList();
        } catch (_) {}
        if (!mounted) return;
      }

      int? updated;
      if (changes.isNotEmpty && staffHoursSheetNeeded(changes: changes, staff: staff, result: result)) {
        setState(() => _isSaving = false);
        updated = await showStaffHoursReviewSheet(
          context,
          salonId: widget.salonId,
          staff: staff,
          changes: changes,
          result: result,
        );
        if (!mounted) return;
      }

      final following = staff.where((s) => s.useSalonHours).length;
      final message = (updated ?? 0) > 0
          ? 'Salon hours saved · $updated staff schedule${updated == 1 ? '' : 's'} updated.'
          : following > 0
              ? 'Salon hours saved · $following staff moved to the new hours.'
              : 'Working hours updated successfully!';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), content: Text(message)));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.startsWith('Exception: ')) {
          msg = msg.substring(11);
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), content: Text(msg)));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _selectTime(BuildContext context, SalonWorkingHour hour, bool isOpenTime) async {
    TimeOfDay initialTime = const TimeOfDay(hour: 9, minute: 0);
    
    String? currentTimeStr = isOpenTime ? hour.openTime : hour.closeTime;
    if (currentTimeStr != null && currentTimeStr.isNotEmpty) {
      final parts = currentTimeStr.split(':');
      if (parts.length >= 2) {
        initialTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0);
      }
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      final formattedTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
      setState(() {
        if (isOpenTime) {
          hour.openTime = formattedTime;
        } else {
          hour.closeTime = formattedTime;
        }
      });
    }
  }

  String _formatTimeDisplay(String? timeStr) {
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

  void _applyToAll(SalonWorkingHour sourceHour) {
    setState(() {
      for (var hour in _workingHours) {
        if (hour.dayOfWeek != sourceHour.dayOfWeek) {
          hour.isClosed = sourceHour.isClosed;
          hour.openTime = sourceHour.openTime;
          hour.closeTime = sourceHour.closeTime;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(milliseconds: 2500), 
        content: Text('Copied ${_daysOfWeek[sourceHour.dayOfWeek]}\'s schedule to all days'),
        backgroundColor: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Change Salon Timings'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _workingHours.length,
                        itemBuilder: (context, index) {
                          final hour = _workingHours[index];
                          return _buildDayCard(hour);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveWorkingHours,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: _isSaving
                            ? CircularProgressIndicator(color: Theme.of(context).colorScheme.surface)
                            : Text('Save Timings', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildDayCard(SalonWorkingHour hour) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: hour.isClosed ? Theme.of(context).dividerColor : AppTheme.accentColor.withOpacity(0.3), width: 1.5),
      ),
      color: hour.isClosed ? Theme.of(context).dividerColor : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      _daysOfWeek[hour.dayOfWeek],
                      style: TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        color: hour.isClosed ? Theme.of(context).colorScheme.onSurface.withOpacity(0.5) : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (!hour.isClosed) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.copy_all, color: AppTheme.accentColor, size: 20),
                        tooltip: 'Apply to all days',
                        onPressed: () => _applyToAll(hour),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ]
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: hour.isClosed ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger).withOpacity(0.1) : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        hour.isClosed ? 'Closed' : 'Open', 
                        style: TextStyle(
                          color: hour.isClosed ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger) : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess), 
                          fontWeight: FontWeight.bold,
                          fontSize: 12
                        )
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: !hour.isClosed,
                      activeColor: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess),
                      onChanged: (val) {
                        setState(() {
                          hour.isClosed = !val;
                          if (hour.isClosed) {
                            hour.openTime = null;
                            hour.closeTime = null;
                          } else {
                            hour.openTime = '09:00:00';
                            hour.closeTime = '18:00:00';
                          }
                        });
                      },
                    ),
                  ],
                )
              ],
            ),
            if (!hour.isClosed) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectTime(context, hour, true),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withOpacity(0.05),
                          border: Border.all(color: AppTheme.accentColor.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wb_sunny_outlined, size: 18, color: AppTheme.accentColor),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Opens At', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                                Text(_formatTimeDisplay(hour.openTime), style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectTime(context, hour, false),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withOpacity(0.05),
                          border: Border.all(color: AppTheme.accentColor.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.nights_stay_outlined, size: 18, color: AppTheme.accentColor),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Closes At', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                                Text(_formatTimeDisplay(hour.closeTime), style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                              ],
                            ),
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
      ),
    );
  }
}
