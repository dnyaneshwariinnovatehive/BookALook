import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../models/leave_models.dart';
import '../../../services/staff_api.dart';

class ProviderLeavesScreen extends StatefulWidget {
  final Map<String, dynamic> salon;

  const ProviderLeavesScreen({
    super.key,
    required this.salon,
  });

  @override
  State<ProviderLeavesScreen> createState() => _ProviderLeavesScreenState();
}

class _ProviderLeavesScreenState extends State<ProviderLeavesScreen> {
  bool _isLoading = true;
  List<ProviderLeave> _leaves = [];

  @override
  void initState() {
    super.initState();
    _fetchLeaves();
  }

  Future<void> _fetchLeaves() async {
    setState(() => _isLoading = true);
    try {
      final leaves = await StaffApi.fetchMyLeaves(widget.salon['id']);
      if (mounted) {
        setState(() {
          _leaves = leaves;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load leaves: $e'), backgroundColor: AppTheme.darkDanger),
        );
      }
    }
  }

  void _requestLeave(BuildContext context) {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    bool isFullDay = true;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    final reasonController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: selectedDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setModalState(() => selectedDate = picked);
              }
            }

            Future<void> pickTime(bool isStart) async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: isStart 
                    ? (startTime ?? const TimeOfDay(hour: 9, minute: 0))
                    : (endTime ?? const TimeOfDay(hour: 17, minute: 0)),
              );
              if (picked != null) {
                setModalState(() {
                  if (isStart) startTime = picked;
                  else endTime = picked;
                });
              }
            }

            Future<void> submitLeave() async {
              if (!isFullDay && (startTime == null || endTime == null)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select start and end time for partial day leave.'), backgroundColor: AppTheme.darkDanger),
                );
                return;
              }
              if (!isFullDay && startTime != null && endTime != null) {
                final startMin = startTime!.hour * 60 + startTime!.minute;
                final endMin = endTime!.hour * 60 + endTime!.minute;
                if (endMin <= startMin) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('End time must be after start time.'), backgroundColor: AppTheme.darkDanger),
                  );
                  return;
                }
              }

              setModalState(() => isSubmitting = true);
              try {
                final data = {
                  'leave_date': DateFormat('yyyy-MM-dd').format(selectedDate),
                  'is_full_day': isFullDay,
                  if (!isFullDay) 'start_time': '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}:00',
                  if (!isFullDay) 'end_time': '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}:00',
                  if (reasonController.text.isNotEmpty) 'reason': reasonController.text,
                };
                
                final response = await StaffApi.requestLeave(widget.salon['id'], data);
                
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  final isAutoApproved = response['auto_approved'] == true;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isAutoApproved ? 'Leave approved automatically.' : 'Leave requested successfully. Waiting for admin approval.'),
                      backgroundColor: AppTheme.accentColor,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                  _fetchLeaves();
                }
              } catch (e) {
                if (ctx.mounted) {
                  setModalState(() => isSubmitting = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.darkDanger),
                  );
                }
              }
            }

            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Request Time Off',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  InkWell(
                    onTap: pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Date', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(DateFormat('MMM dd, yyyy').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                            ],
                          ),
                          const Icon(Icons.calendar_today, color: AppTheme.accentColor),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: isFullDay,
                        activeColor: AppTheme.accentColor,
                        onChanged: (val) => setModalState(() => isFullDay = val ?? true),
                      ),
                      const Text('Full Day Off'),
                    ],
                  ),
                  if (!isFullDay) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => pickTime(true),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Start Time', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(startTime?.format(context) ?? 'Select', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: () => pickTime(false),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('End Time', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(endTime?.format(context) ?? 'Select', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(
                      labelText: 'Reason (Optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isSubmitting ? null : submitLeave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSubmitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Submit Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return AppTheme.lightSuccess;
      case 'rejected': return AppTheme.darkDanger;
      case 'pending': return Colors.orange;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Leaves'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _requestLeave(context),
        backgroundColor: AppTheme.accentColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Request Leave', style: TextStyle(color: Colors.white)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _leaves.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy, size: 64, color: isDark ? Colors.grey[700] : Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('No leaves requested yet', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 80),
                  itemCount: _leaves.length,
                  itemBuilder: (context, index) {
                    final leave = _leaves[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: Theme.of(context).cardColor,
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today, size: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Text(
                                      DateFormat('MMM dd, yyyy').format(DateTime.parse(leave.leaveDate)),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(leave.status).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _getStatusColor(leave.status).withOpacity(0.5)),
                                  ),
                                  child: Text(
                                    leave.status.toUpperCase(),
                                    style: TextStyle(
                                      color: _getStatusColor(leave.status),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildBadge(
                                  leave.isFullDay ? 'Full Day' : 'Partial Day', 
                                  AppTheme.accentColor, 
                                  isDark
                                ),
                                const SizedBox(width: 8),
                                _buildBadge(
                                  leave.leaveType.toUpperCase(),
                                  leave.leaveType == 'paid' ? AppTheme.lightSuccess : Colors.grey,
                                  isDark
                                ),
                              ],
                            ),
                            if (!leave.isFullDay && leave.startTime != null && leave.endTime != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 14, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_formatTime(leave.startTime!)} - ${_formatTime(leave.endTime!)}',
                                    style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                            if (leave.reason != null && leave.reason!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.grey[850] : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Reason: ${leave.reason}',
                                  style: TextStyle(
                                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatTime(String timeString) {
    try {
      final parts = timeString.split(':');
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
      return DateFormat('h:mm a').format(dt);
    } catch (e) {
      return timeString;
    }
  }

  Widget _buildBadge(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? color : color.withOpacity(0.9),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
