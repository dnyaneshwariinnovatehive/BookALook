import 'package:partner_app/theme/app_theme.dart';
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

  /// Which leave status is shown in the Leave Requests view. Defaults to the
  /// most actionable bucket — the ones still waiting for a decision.
  String _leaveFilter = 'pending';

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

  /// Leaves the current filter shows, sorted with the newest leave date first.
  List<ProviderLeave> get _filteredLeaves {
    final matching = _leaveFilter == 'all'
        ? List<ProviderLeave>.of(_leaves)
        : _leaves.where((l) => l.status == _leaveFilter).toList();

    matching.sort((a, b) {
      final aDate = DateTime.tryParse(a.leaveDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse(b.leaveDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return matching;
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
    
    // For UI demonstration as requested, using default chips if services are not yet fetched
    List<String> mockServices = ['Haircut', 'Hair Colour', 'combos'];
    if (member.specialization != null && member.specialization!.toLowerCase().contains('skin')) {
      mockServices = ['Facial', 'Spa'];
    } else if (member.specialization != null && member.specialization!.toLowerCase().contains('nail')) {
      mockServices = ['Nails'];
    } else if (member.specialization != null && member.specialization!.toLowerCase().contains('makeup')) {
      mockServices = ['Makeup', 'Bridal'];
    } else if (member.specialization != null && member.specialization!.toLowerCase().contains('massage')) {
      mockServices = ['Spa'];
    }

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddStaffScreen(salonId: widget.salonId, existingStaff: member),
          ),
        );
        if (result == true) {
          _fetchStaff();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).dividerColor : Theme.of(context).dividerColor),
          boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.02), blurRadius: 8, offset: Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(context).dividerColor,
              // Placeholder for image, using Icon as fallback
              child: Icon(Icons.person, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), size: 32),
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
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      if (member.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('Active', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess), fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    member.specialization ?? subtitle,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: mockServices.map((s) => _buildChip(s)).toList(),
                  )
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5), // Light purple
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: Color(0xFF9C27B0), fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildLeaveFilterChip(String value, String label) {
    final selected = _leaveFilter == value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _leaveFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentColor : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.accentColor : theme.dividerColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : (isDark ? theme.colorScheme.onSurface : const Color(0xFF6B7280)),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveCard(ProviderLeave leave) {
    Color statusColor;
    Color statusBg;
    String statusText;
    IconData statusIcon;

    switch (leave.status) {
      case 'approved':
        statusColor = (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess);
        statusBg = (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccessBg : AppTheme.lightSuccessBg);
        statusText = 'Approved';
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger);
        statusBg = (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDangerBg : AppTheme.lightDangerBg);
        statusText = 'Rejected';
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkWarning : AppTheme.lightWarning);
        statusBg = (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkWarningBg : AppTheme.lightWarningBg);
        statusText = 'Pending';
        statusIcon = Icons.schedule;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).dividerColor : Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: statusBg,
            child: Icon(statusIcon, color: statusColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leave.provider?['user']?['name'] ?? 'Unknown Provider',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatLeaveTime(leave),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                ),
                if (leave.reason != null && leave.reason!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    leave.reason!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              if (leave.status == 'pending') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _updateLeaveStatus(leave.id, 'approved'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.check, color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess), size: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _updateLeaveStatus(leave.id, 'rejected'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.close, color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkDanger : AppTheme.lightDanger), size: 18),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Staff', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
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
              icon: Icon(Icons.person_add_alt_1, size: 18),
              label: Text('Add'),
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
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.05), blurRadius: 4, offset: Offset(0, 2))
                ]
              ),
              labelColor: Theme.of(context).textTheme.bodyLarge?.color,
              unselectedLabelColor: AppTheme.accentColor,
              labelStyle: TextStyle(fontWeight: FontWeight.bold),
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
                              // Status filters — default to the pending bucket.
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                child: Row(
                                  children: [
                                    _buildLeaveFilterChip('pending', 'Pending'),
                                    const SizedBox(width: 8),
                                    _buildLeaveFilterChip('approved', 'Approved'),
                                    const SizedBox(width: 8),
                                    _buildLeaveFilterChip('rejected', 'Rejected'),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _filteredLeaves.isEmpty
                                    ? Center(
                                        child: Text(
                                          _leaves.isEmpty
                                              ? 'No leave requests found.'
                                              : 'No ${_leaveFilter} leave requests.',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                            fontSize: 14,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        itemCount: _filteredLeaves.length,
                                        itemBuilder: (context, index) =>
                                            _buildLeaveCard(_filteredLeaves[index]),
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
