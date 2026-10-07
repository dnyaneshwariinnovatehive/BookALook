import 'package:partner_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/staff_models.dart';
import '../../../models/leave_models.dart';
import '../../../services/staff_api.dart';
import '../../../theme/app_theme.dart';
import 'staff/add_staff_screen.dart';
import '../../../widgets/wallet_coin_pill.dart';

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

  /// Whoever asked. The two screens that render leaves read the name out of
  /// different shapes of the same payload, so both are tried.
  String _leaveProviderName(ProviderLeave leave) {
    final provider = leave.provider;
    if (provider != null) {
      final user = provider['user'];
      if (user is Map && user['name'] != null) return '${user['name']}';
      if (provider['name'] != null) return '${provider['name']}';
    }
    return 'This staff member';
  }

  /// Label on the left, value on the right — the same row style the other
  /// confirmation dialogs in this app use.
  Widget _dialogRow(String label, String value, Color valueColor) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          Text(value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      );

  /// Approving or rejecting is a permanent write on a staff record, and a
  /// rejection is what payroll picks up as unpaid leave, so the decision and
  /// its pay consequence are named before it is written.
  Future<void> _decideLeave(ProviderLeave leave, String status) async {
    final approving = status == 'approved';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heading = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final body = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final textLight = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;
    final success = isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess;
    final danger = isDark ? AppTheme.darkDanger : AppTheme.lightDanger;
    final dangerBg = isDark ? AppTheme.darkDangerBg : AppTheme.lightDangerBg;
    final softBg = isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft;
    final surface = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

    final name = _leaveProviderName(leave);
    final isUnpaid = leave.leaveType == 'unpaid';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          approving ? 'Approve this leave?' : 'Reject this leave?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: heading),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: heading)),
            const SizedBox(height: 12),
            _dialogRow('When', _formatLeaveTime(leave), heading),
            const SizedBox(height: 6),
            _dialogRow('Leave type', isUnpaid ? 'Unpaid' : 'Paid', body),
            if (leave.reason != null && leave.reason!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _dialogRow('Reason', leave.reason!, body),
            ],
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: approving ? softBg : dangerBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                approving
                    ? '$name is marked away for this period. Any bookings on it still need rescheduling.'
                    : isUnpaid
                        ? 'Rejected unpaid leave is deducted from $name\'s next salary.'
                        : '$name is marked as working this period, so any bookings on it stay as they are.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: approving ? body : danger,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('This cannot be changed from the app afterwards.',
                style: TextStyle(fontSize: 12, color: textLight)),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Go back', style: TextStyle(color: body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              approving ? 'Approve leave' : 'Reject leave',
              style: TextStyle(color: approving ? success : danger, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _updateLeaveStatus(leave.id, status);
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

  Future<void> _refreshAll() async {
    await Future.wait([
      _fetchStaff(),
      _fetchLeaves(),
    ]);
  }

  String _staffFilter = 'all';

  int get _totalStaff => _staff.length;
  int get _activeStaff => _staff.where((s) => s.isActive).length;
  
  int get _onLeaveStaff {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    int count = 0;
    for (var member in _staff) {
      if (_leaves.any((l) => l.providerId == member.id && l.leaveDate == todayStr && l.status == 'approved')) {
        count++;
      }
    }
    return count;
  }
  
  int get _pendingLeaveRequests => _leaves.where((l) => l.status == 'pending').length;

  Widget _buildSummaryRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final totalBg = isDark ? const Color(0xFF3B285E) : const Color(0xFFF3E8FF);
    final totalIconColor = isDark ? const Color(0xFFD8B4FE) : const Color(0xFF9C27B0);
    
    final activeBg = isDark ? const Color(0xFF1B3B22) : const Color(0xFFE8F5E9);
    final activeIconColor = isDark ? const Color(0xFF81C784) : const Color(0xFF4CAF50);
    
    final leaveBg = isDark ? const Color(0xFF4A3419) : const Color(0xFFFFF3E0);
    final leaveIconColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFFF9800);

    if (_isLoadingStaff || _isLoadingLeaves) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: List.generate(3, (index) => Expanded(
            child: Container(
              height: 60,
              margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          )),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(child: _buildSummaryCard('Total Staff', _totalStaff, Icons.people_alt, totalBg, totalIconColor, isDark, () {
            _tabController.animateTo(0);
            setState(() => _staffFilter = 'all');
          })),
          const SizedBox(width: 8),
          Expanded(child: _buildSummaryCard('Active', _activeStaff, Icons.person, activeBg, activeIconColor, isDark, () {
            _tabController.animateTo(0);
            setState(() => _staffFilter = 'active');
          })),
          const SizedBox(width: 8),
          Expanded(child: _buildSummaryCard('On Leave', _onLeaveStaff, Icons.event_busy, leaveBg, leaveIconColor, isDark, () {
            _tabController.animateTo(1);
            setState(() => _leaveFilter = 'approved');
          })),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, int count, IconData icon, Color bgColor, Color iconColor, bool isDark, VoidCallback onTap) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          decoration: BoxDecoration(
            border: Border.all(color: iconColor.withOpacity(0.15)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: iconColor),
                  const SizedBox(width: 4),
                  Text(count.toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87, height: 1.0)),
                ],
              ),
              const SizedBox(height: 6),
              Text(title, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black54, height: 1.0), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildStaffFilterChip(String value, String label) {
    final selected = _staffFilter == value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _staffFilter = value),
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
                      onTap: () => _decideLeave(leave, 'approved'),
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
                      onTap: () => _decideLeave(leave, 'rejected'),
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

  List<StaffMember> get _filteredStaff {
    if (_staffFilter == 'active') {
      return _staff.where((s) => s.isActive).toList();
    }
    return _staff;
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
          WalletCoinPill(salonId: widget.salonId, compact: true),
          const SizedBox(width: 8),
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
          _buildSummaryRow(),
          // Segmented Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              tabs: [
                Tab(text: _isLoadingStaff ? 'All Staff' : 'All Staff ($_totalStaff)'),
                Tab(text: _isLoadingLeaves ? 'Leave Requests' : 'Leave Requests ($_pendingLeaveRequests)'),
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
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                child: Row(
                                  children: [
                                    _buildStaffFilterChip('all', 'All Staff'),
                                    const SizedBox(width: 8),
                                    _buildStaffFilterChip('active', 'Active'),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _staff.isEmpty
                                    ? RefreshIndicator(
                                        onRefresh: _refreshAll,
                                        color: AppTheme.accentColor,
                                        child: ListView(
                                          physics: const AlwaysScrollableScrollPhysics(),
                                          children: const [
                                            SizedBox(height: 100),
                                            Center(child: Text('No staff added yet.')),
                                          ],
                                        ),
                                      )
                                    : RefreshIndicator(
                                        onRefresh: _refreshAll,
                                        color: AppTheme.accentColor,
                                        child: _filteredStaff.isEmpty
                                            ? ListView(
                                                physics: const AlwaysScrollableScrollPhysics(),
                                                children: const [
                                                  SizedBox(height: 100),
                                                  Center(child: Text('No active staff found.')),
                                                ],
                                              )
                                            : ListView.builder(
                                                physics: const AlwaysScrollableScrollPhysics(),
                                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                                itemCount: _filteredStaff.length,
                                                itemBuilder: (context, index) => _buildStaffCard(_filteredStaff[index]),
                                              ),
                                      ),
                              ),
                            ],
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
                                child: RefreshIndicator(
                                  onRefresh: _refreshAll,
                                  color: AppTheme.accentColor,
                                  child: _filteredLeaves.isEmpty
                                      ? ListView(
                                          physics: const AlwaysScrollableScrollPhysics(),
                                          children: [
                                            const SizedBox(height: 100),
                                            Center(
                                              child: Text(
                                                _leaves.isEmpty
                                                    ? 'No leave requests found.'
                                                    : 'No $_leaveFilter leave requests.',
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : ListView.builder(
                                          physics: const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          itemCount: _filteredLeaves.length,
                                          itemBuilder: (context, index) =>
                                              _buildLeaveCard(_filteredLeaves[index]),
                                        ),
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
