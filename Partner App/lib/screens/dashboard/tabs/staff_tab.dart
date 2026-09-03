import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/staff_models.dart';
import '../../../models/leave_models.dart';
import '../../../services/staff_api.dart';
import '../../../theme/app_theme.dart';
import 'staff/add_staff_screen.dart';

class StaffTab extends StatefulWidget {
  final String salonId;
  const StaffTab({super.key, required this.salonId});

  @override
  State<StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<StaffTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  bool _isLoadingStaff = true;
  List<StaffMember> _staff = [];
  String? _staffError;

  bool _isLoadingLeaves = true;
  List<ProviderLeave> _leaves = [];
  String? _leaveError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchStaff();
    _fetchLeaves();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchStaff() async {
    setState(() {
      _isLoadingStaff = true;
      _staffError = null;
    });
    try {
      final staffList = await StaffApi.fetchStaff(widget.salonId);
      setState(() {
        _staff = staffList;
        _isLoadingStaff = false;
      });
    } catch (e) {
      setState(() {
        _staffError = e.toString();
        _isLoadingStaff = false;
      });
    }
  }

  Future<void> _fetchLeaves() async {
    setState(() {
      _isLoadingLeaves = true;
      _leaveError = null;
    });
    try {
      final leavesList = await StaffApi.fetchLeaves(widget.salonId);
      setState(() {
        _leaves = leavesList;
        _isLoadingLeaves = false;
      });
    } catch (e) {
      setState(() {
        _leaveError = e.toString();
        _isLoadingLeaves = false;
      });
    }
  }

  Future<void> _updateLeaveStatus(String leaveId, String status) async {
    try {
      await StaffApi.updateLeaveStatus(widget.salonId, leaveId, status);
      // Update local state without full refetch
      setState(() {
        final index = _leaves.indexWhere((l) => l.id == leaveId);
        if (index != -1) {
          _leaves[index].status = status;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Leave $status successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update leave: $e')));
      }
    }
  }

  String _formatLeaveTime(ProviderLeave leave) {
    try {
      DateTime date = DateTime.parse(leave.leaveDate);
      String formattedDate = DateFormat('dd MMM yyyy').format(date);

      if (leave.isFullDay) {
        return '$formattedDate • Full Day';
      } else if (leave.startTime != null && leave.endTime != null) {
        // Parse time
        final startParts = leave.startTime!.split(':');
        final endParts = leave.endTime!.split(':');
        
        final start = TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1]));
        final end = TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1]));

        String _formatTOD(TimeOfDay t) {
          int h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
          String period = t.hour >= 12 ? 'PM' : 'AM';
          return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
        }

        return '$formattedDate • ${_formatTOD(start)} - ${_formatTOD(end)}';
      }
      return formattedDate;
    } catch (e) {
      return leave.leaveDate;
    }
  }

  Widget _buildStaffCard(StaffMember member) {
    // Generate subtitle from services
    String subtitle = 'Service Provider';
    List<String> serviceNames = [];
    if (member.user != null && member.user!['services'] != null) {
        // Services are nested in the raw API response or we need to extract them if they are in 'services' relation
    }
    // Let's assume services are available in the JSON directly under 'services' 
    // Wait, the index API returns `ServiceProvider::with(['user', 'services'])`
    // We should parse it, but for now we'll just mock it or extract if possible

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.accentColor.withOpacity(0.1),
            child: const Icon(Icons.person, color: AppTheme.accentColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member.user?['name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(width: 8),
                    if (member.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Active', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  member.specialization ?? subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 8),
                // Chips - static for now since services might need complex extraction
                Wrap(
                  spacing: 8,
                  children: [
                    _buildChip('General'),
                  ],
                )
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppTheme.accentColor, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildLeaveCard(ProviderLeave leave) {
    Color statusColor;
    String statusText = leave.status.capitalize();
    
    if (leave.status == 'approved') {
      statusColor = Colors.green;
    } else if (leave.status == 'rejected') {
      statusColor = Colors.red;
    } else {
      statusColor = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.orange.shade50,
            child: Icon(Icons.person_outline, color: Colors.orange.shade300),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leave.provider?['user']?['name'] ?? 'Unknown Provider',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatLeaveTime(leave),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  leave.reason ?? 'No reason provided',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                statusText,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (leave.status == 'pending') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _updateLeaveStatus(leave.id, 'approved'),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.check, color: Colors.white, size: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _updateLeaveStatus(leave.id, 'rejected'),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ]
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('Staff', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: AppTheme.lightBg,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AddStaffScreen(salonId: widget.salonId)),
                );
                if (result == true) {
                  _fetchStaff();
                }
              },
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Segmented Tab Bar
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(30),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                ]
              ),
              labelColor: Colors.black,
              unselectedLabelColor: AppTheme.accentColor,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'All Staff'),
                Tab(text: 'Leave Requests'),
              ],
            ),
          ),
          
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // All Staff View
                _isLoadingStaff
                    ? const Center(child: CircularProgressIndicator())
                    : _staffError != null
                        ? Center(child: Text(_staffError!))
                        : _staff.isEmpty
                            ? const Center(child: Text('No staff added yet.'))
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _staff.length,
                                itemBuilder: (context, index) => _buildStaffCard(_staff[index]),
                              ),

                // Leave Requests View
                _isLoadingLeaves
                    ? const Center(child: CircularProgressIndicator())
                    : _leaveError != null
                        ? Center(child: Text(_leaveError!))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Text(
                                  'Leave Calendar — Sep 2026',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              // Static Weekday Header
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
                                      .map((day) => Text(day, style: const TextStyle(color: Colors.grey, fontSize: 12)))
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _leaves.isEmpty
                                    ? const Center(child: Text('No leave requests found.'))
                                    : ListView.builder(
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        itemCount: _leaves.length,
                                        itemBuilder: (context, index) => _buildLeaveCard(_leaves[index]),
                                      ),
                              ),
                            ],
                          ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
    String capitalize() {
      if (isEmpty) {
        return this;
      }
      return "${this[0].toUpperCase()}${substring(1)}";
    }
}
