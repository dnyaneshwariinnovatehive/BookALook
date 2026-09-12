import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../qr_scanner_screen.dart';
import '../../../services/appointment_service.dart';
import '../../../services/staff_api.dart';
import '../../../services/salon_closure_api.dart';
import '../../../models/staff_models.dart';
import '../../../models/leave_models.dart';
import '../services/add_service_flow.dart';
import 'staff/add_staff_screen.dart';
import '../close_day_sheet.dart';

class HomeTab extends StatefulWidget {
  final String salonId;
  final String salonName;

  const HomeTab({
    super.key,
    required this.salonId,
    this.salonName = '',
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _isLoading = true;
  String _errorMessage = '';

  int _todaysAppts = 0;
  int _staffOnDuty = 0;
  int _onLeaveToday = 0;

  List<ProviderLeave> _pendingLeaves = [];
  bool _isClosedToday = false;
  String? _closureReason;

  List<StaffMember> _staff = [];
  Map<String, int> _providerLoads = {};

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchHomeData();
    // Poll every 60 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        _fetchHomeData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchHomeData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      // Fetch all required data concurrently
      final responses = await Future.wait([
        PartnerAppointmentService().getAppointments(widget.salonId, date: todayStr),
        StaffApi.fetchStaff(widget.salonId),
        StaffApi.fetchLeaves(widget.salonId),
        SalonClosureApi.upcomingClosures(widget.salonId),
      ]);

      final appointments = responses[0] as List<dynamic>;
      final staff = responses[1] as List<StaffMember>;
      final leaves = responses[2] as List<ProviderLeave>;
      final closures = responses[3] as List<dynamic>;

      if (!mounted) return;

      int apptsCount = 0;
      Map<String, int> providerLoads = {};
      
      // Calculate appointment stats
      for (var appt in appointments) {
        // Exclude cancelled or no-show if needed, assuming all returned are valid for now or filter by status
        final status = appt['status'];
        if (status != 'cancelled' && status != 'no_show') {
          apptsCount++;
          final pId = appt['appointed_provider_id']?.toString() ?? appt['serving_provider_id']?.toString();
          if (pId != null) {
            providerLoads[pId] = (providerLoads[pId] ?? 0) + 1;
          }
        }
      }

      // Calculate leave stats for today
      int onLeaveTodayCount = 0;
      List<ProviderLeave> pendingLeaves = [];
      
      for (var leave in leaves) {
        if (leave.leaveDate == todayStr && leave.status == 'approved') {
          onLeaveTodayCount++;
        }
        if (leave.status == 'pending') {
          pendingLeaves.add(leave);
        }
      }

      // Calculate staff on duty (active minus those on leave today)
      int staffOnDutyCount = 0;
      for (var member in staff) {
        if (member.isActive) {
          bool isOnLeave = leaves.any((l) => l.providerId == member.id && l.leaveDate == todayStr && l.status == 'approved');
          if (!isOnLeave) {
            staffOnDutyCount++;
          }
        }
      }

      // Check if closed today
      bool isClosedToday = false;
      String? closureReason;
      for (var c in closures) {
        if (c['date'] == todayStr) {
          isClosedToday = true;
          closureReason = c['reason'];
          break;
        }
      }

      setState(() {
        _todaysAppts = apptsCount;
        _staffOnDuty = staffOnDutyCount;
        _onLeaveToday = onLeaveTodayCount;
        _pendingLeaves = pendingLeaves;
        _isClosedToday = isClosedToday;
        _closureReason = closureReason;
        _staff = staff;
        _providerLoads = providerLoads;
        _isLoading = false;
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load dashboard data. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateLeaveStatus(ProviderLeave leave, String newStatus) async {
    try {
      await StaffApi.updateLeaveStatus(widget.salonId, leave.id, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Leave request ${newStatus == 'approved' ? 'approved' : 'rejected'}.')),
        );
        _fetchHomeData(silent: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update leave status: $e')),
        );
      }
    }
  }

  Future<void> _openScanner(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(salonId: widget.salonId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _fetchHomeData(silent: false),
          color: AppTheme.accentColor,
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
              ? ListView(
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.4),
                    Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red))),
                    TextButton(onPressed: () => _fetchHomeData(), child: const Text('Retry'))
                  ],
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      _buildScanCard(),
                      const SizedBox(height: 24),
                      _buildTopStats(),
                      const SizedBox(height: 24),
                      _buildQuickActions(),
                      const SizedBox(height: 24),
                      _buildPendingLeavesOrClosure(),
                      const SizedBox(height: 24),
                      _buildProviderLoad(),
                      const SizedBox(height: 80), // Padding for FAB
                    ],
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openScanner(context),
        backgroundColor: AppTheme.accentColor,
        foregroundColor: Colors.white,
        tooltip: 'Scan customer QR',
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Color(0xFFE0E0E0),
              backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'), // Placeholder for Admin Profile
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hi Admin 👋',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                ),
                Text(
                  widget.salonName,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ]
          ),
          child: IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black87),
            onPressed: () {
              // TODO: Implement notifications sheet/screen
            },
          ),
        )
      ],
    );
  }

  /// Checking a customer in is the thing this screen gets opened for most, so it
  /// sits in the page itself rather than only on the floating button — a FAB is
  /// easy to miss, and on a nested scaffold it is not always where you expect.
  Widget _buildScanCard() {
    return InkWell(
      onTap: () => _openScanner(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scan customer QR',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 3),
                  Text('Check someone in and start their appointment',
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _buildTopStats() {
    return Row(
      children: [
        Expanded(child: _buildStatCard("Today's Appts", _todaysAppts.toString(), const Color(0xFFF3E8FF), const Color(0xFF8B5CF6))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard("Staff on Duty", _staffOnDuty.toString(), const Color(0xFFE0F2FE), const Color(0xFF0284C7))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard("On Leave Today", _onLeaveToday.toString(), const Color(0xFFFFE4E6), const Color(0xFFE11D48))),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionBtn("Add Provider", Icons.person_add_alt_1, const Color(0xFFF5F3FF), const Color(0xFF8B5CF6), () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => AddStaffScreen(salonId: widget.salonId))).then((_) => _fetchHomeData(silent: true));
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionBtn("Add Service", Icons.add_circle_outline, const Color(0xFFF5F3FF), const Color(0xFF8B5CF6), () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => AddServiceFlow(salonId: widget.salonId)));
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionBtn("Mark Closed", Icons.calendar_today, const Color(0xFFFFFBEB), const Color(0xFFD97706), () async {
                final now = DateTime.now();
                final todayStr = DateFormat('yyyy-MM-dd').format(now);
                final closed = await CloseDaySheet.show(context, salonId: widget.salonId, initialDate: now);
                if (closed == true) _fetchHomeData(silent: true);
              }),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildActionBtn(String title, IconData icon, Color bgColor, Color iconColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: iconColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingLeavesOrClosure() {
    if (_isClosedToday) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Today\'s Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFDC2626)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Salon is Marked Closed Today', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF991B1B))),
                      if (_closureReason != null && _closureReason!.isNotEmpty)
                        Text('Reason: $_closureReason', style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B))),
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      );
    }

    if (_pendingLeaves.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Pending Leave Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
            Text('${_pendingLeaves.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
          ],
        ),
        const SizedBox(height: 16),
        ..._pendingLeaves.map((leave) {
          final providerName = leave.provider?['name'] ?? 'Unknown Provider';
          String timeFmt = '';
          if (leave.isFullDay) {
            timeFmt = '${DateFormat('dd MMM yyyy').format(DateTime.parse(leave.leaveDate))} • Full Day';
          } else {
            timeFmt = '${DateFormat('dd MMM yyyy').format(DateTime.parse(leave.leaveDate))} • ${leave.startTime} - ${leave.endTime}';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(providerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(timeFmt, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      if (leave.reason != null && leave.reason!.isNotEmpty)
                        Text(leave.reason!, style: const TextStyle(fontSize: 12, color: Colors.black38)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _updateLeaveStatus(leave, 'approved'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Approve'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _updateLeaveStatus(leave, 'rejected'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Reject'),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildProviderLoad() {
    if (_staff.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Today's Provider Load", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
          ),
          itemCount: _staff.where((s) => s.isActive).length,
          itemBuilder: (context, index) {
            final activeStaff = _staff.where((s) => s.isActive).toList();
            final member = activeStaff[index];
            final load = _providerLoads[member.id] ?? 0;
            final String avatarUrl = member.user?['avatar_url'] ?? 'https://i.pravatar.cc/150?u=${member.id}'; // Fallback

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: NetworkImage(avatarUrl),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(member.user?['name'] ?? 'Unknown', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        if (member.specialization != null)
                          Text(member.specialization!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black45)),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$load', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                      const Text('appts', style: TextStyle(fontSize: 10, color: Colors.black45)),
                    ],
                  )
                ],
              ),
            );
          },
        )
      ],
    );
  }
}
