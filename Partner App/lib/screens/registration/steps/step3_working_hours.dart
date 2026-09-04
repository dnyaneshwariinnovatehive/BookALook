import 'package:partner_app/theme/app_theme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';

class Step3WorkingHours extends StatefulWidget {
  final Function(Map<String, dynamic>) onNext;
  final VoidCallback onBack;

  const Step3WorkingHours({super.key, required this.onNext, required this.onBack});

  @override
  State<Step3WorkingHours> createState() => _Step3WorkingHoursState();
}

class _Step3WorkingHoursState extends State<Step3WorkingHours> {
  final List<Map<String, dynamic>> _schedule = [
    {'day': 'Sunday', 'day_of_week': 0, 'is_closed': true, 'open_time': const TimeOfDay(hour: 9, minute: 0), 'close_time': const TimeOfDay(hour: 20, minute: 0)},
    {'day': 'Monday', 'day_of_week': 1, 'is_closed': false, 'open_time': const TimeOfDay(hour: 9, minute: 0), 'close_time': const TimeOfDay(hour: 20, minute: 0)},
    {'day': 'Tuesday', 'day_of_week': 2, 'is_closed': false, 'open_time': const TimeOfDay(hour: 9, minute: 0), 'close_time': const TimeOfDay(hour: 20, minute: 0)},
    {'day': 'Wednesday', 'day_of_week': 3, 'is_closed': false, 'open_time': const TimeOfDay(hour: 9, minute: 0), 'close_time': const TimeOfDay(hour: 20, minute: 0)},
    {'day': 'Thursday', 'day_of_week': 4, 'is_closed': false, 'open_time': const TimeOfDay(hour: 9, minute: 0), 'close_time': const TimeOfDay(hour: 20, minute: 0)},
    {'day': 'Friday', 'day_of_week': 5, 'is_closed': false, 'open_time': const TimeOfDay(hour: 9, minute: 0), 'close_time': const TimeOfDay(hour: 20, minute: 0)},
    {'day': 'Saturday', 'day_of_week': 6, 'is_closed': false, 'open_time': const TimeOfDay(hour: 9, minute: 0), 'close_time': const TimeOfDay(hour: 20, minute: 0)},
  ];

  Future<void> _pickTime(int index, bool isOpenTime) async {
    final initialTime = isOpenTime ? _schedule[index]['open_time'] : _schedule[index]['close_time'];
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime as TimeOfDay,
    );

    if (pickedTime != null) {
      setState(() {
        if (isOpenTime) {
          _schedule[index]['open_time'] = pickedTime;
        } else {
          _schedule[index]['close_time'] = pickedTime;
        }
      });
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  void _submit() {
    List<Map<String, dynamic>> finalSchedule = _schedule.map((day) {
      return {
        'day_of_week': day['day_of_week'],
        'is_closed': day['is_closed'],
        'open_time': day['is_closed'] ? null : _formatTime(day['open_time'] as TimeOfDay),
        'close_time': day['is_closed'] ? null : _formatTime(day['close_time'] as TimeOfDay),
      };
    }).toList();

    widget.onNext({
      'working_hours': jsonEncode(finalSchedule),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Working Hours',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set your salon\'s general operating hours.',
                  style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody),
                ),
                const SizedBox(height: 24),
                ..._schedule.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var day = entry.value;
                  return _buildDayRow(idx, day);
                }).toList(),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: const Border(top: BorderSide(color: AppTheme.lightBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.lightBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Back', style: TextStyle(color: AppTheme.lightTextBody)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayRow(int index, Map<String, dynamic> day) {
    bool isClosed = day['is_closed'];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.lightBorder),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(day['day'], style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Text('Closed', style: TextStyle(fontSize: 12, color: AppTheme.lightTextBody)),
                  Switch(
                    value: isClosed,
                    onChanged: (val) {
                      setState(() {
                        _schedule[index]['is_closed'] = val;
                      });
                    },
                    activeColor: AppTheme.accentColor,
                  ),
                ],
              )
            ],
          ),
          if (!isClosed)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _pickTime(index, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.lightBorder),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text((day['open_time'] as TimeOfDay).format(context)),
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('to'),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _pickTime(index, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.lightBorder),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text((day['close_time'] as TimeOfDay).format(context)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
