import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../widgets/initials_avatar.dart';
import '../../../widgets/wallet_coin_pill.dart';
import '../../notifications_screen.dart';
import '../../../services/notification_service.dart';
import '../../qr_scanner_screen.dart';
import '../../../services/appointment_service.dart';
import '../../../services/staff_api.dart';
import '../../../services/salon_closure_api.dart';
import '../../../models/staff_models.dart';
import '../../../models/leave_models.dart';
import '../services/add_service_flow.dart';
import 'staff/add_staff_screen.dart';
import 'settings/salon_timings_screen.dart';
import '../close_day_sheet.dart';
import '../../../services/salon_settings_api.dart';
import '../../../services/insights_api.dart';

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
  bool _needsWorkingHours = false;
  SalonInsights? _insights;

  int _unreadNotifications = 0;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchHomeData();
    _refreshUnreadCount();
    // Poll every 60 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        _fetchHomeData(silent: true);
        _refreshUnreadCount();
      }
    });
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final count = await PartnerNotificationService.unreadCount();
      if (mounted && count != _unreadNotifications) {
        setState(() => _unreadNotifications = count);
      }
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (mounted) _refreshUnreadCount();
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
        SalonSettingsApi.fetchWorkingHours(widget.salonId),
      ]);
      
      SalonInsights? insights;
      try {
        insights = await InsightsApi.fetch(widget.salonId);
      } catch (_) {}

      final appointments = responses[0] as List<dynamic>;
      final staff = responses[1] as List<StaffMember>;
      final leaves = responses[2] as List<ProviderLeave>;
      final closures = responses[3] as List<dynamic>;
      final workingHoursResponse = responses[4] as Map<String, dynamic>;

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
        _needsWorkingHours = workingHoursResponse['is_default'] == true;
        _insights = insights;
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

  /// Whoever asked. The staff tab reads the name out of `provider.user.name`
  /// while this one reads `provider.name`, so both shapes are tried.
  String _leaveProviderName(ProviderLeave leave) {
    final provider = leave.provider;
    if (provider != null) {
      final user = provider['user'];
      if (user is Map && user['name'] != null) return '${user['name']}';
      if (provider['name'] != null) return '${provider['name']}';
    }
    return 'This staff member';
  }

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
    final when = leave.isFullDay
        ? '${DateFormat('dd MMM yyyy').format(DateTime.parse(leave.leaveDate))} • Full Day'
        : '${DateFormat('dd MMM yyyy').format(DateTime.parse(leave.leaveDate))} • ${leave.startTime} - ${leave.endTime}';

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
            Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: heading)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('When', style: TextStyle(fontSize: 14, color: body)),
                Flexible(
                  child: Text(when,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: heading)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Leave type', style: TextStyle(fontSize: 14, color: body)),
                Text(isUnpaid ? 'Unpaid' : 'Paid',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: body)),
              ],
            ),
            if (leave.reason != null && leave.reason!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Reason', style: TextStyle(fontSize: 14, color: body)),
                  Flexible(
                    child: Text(leave.reason!,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: body)),
                  ),
                ],
              ),
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
                style: TextStyle(fontSize: 12.5, height: 1.4, color: approving ? body : danger),
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

    await _updateLeaveStatus(leave, status);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                       _buildHeader(isDark),
                       if (_needsWorkingHours) ...[
                         const SizedBox(height: 16),
                         _buildWorkingHoursPrompt(),
                       ],
                       const SizedBox(height: 24),
                       _buildScanCard(),
                       const SizedBox(height: 24),
                       _buildTopStats(isDark),
                       if (_insights != null) ...[
                         const SizedBox(height: 24),
                         _buildBasicAnalytics(isDark),
                         if (_insights!.advanced && _insights!.peakHours != null) ...[
                           const SizedBox(height: 24),
                           _buildPeakHoursInsights(isDark),
                         ],
                       ],
                       const SizedBox(height: 24),
                       _buildQuickActions(isDark),
                       const SizedBox(height: 24),
                       _buildPendingLeavesOrClosure(isDark),
                       const SizedBox(height: 24),
                       _buildProviderLoad(isDark),
                       const SizedBox(height: 80), // Padding for bottom nav
                     ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final headingColor = isDark ? AppTheme.darkTextHeading : const Color(0xFF1A1A1A);
    final subColor = isDark ? AppTheme.darkTextBody : Colors.grey;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final iconColor = isDark ? AppTheme.darkTextHeading : Colors.black87;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Flexible now that the right-hand side is wider: a long salon name
        // should shorten rather than overflow the row.
        Flexible(
          child: Row(
            children: [
              const InitialsAvatar(
                name: 'Admin',
                radius: 24,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hi Admin 👋',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: headingColor),
                    ),
                    Text(
                      widget.salonName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: subColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Grouped so the row still has two sides to space apart. The balance
        // sits left of the bell: it is something the owner glances at, while
        // the bell is something they act on, and the control they act on stays
        // nearest the thumb.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WalletCoinPill(salonId: widget.salonId, compact: true),
            const SizedBox(width: 6),
            Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ]
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(
                  _unreadNotifications > 0
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none,
                  color: iconColor,
                  size: 26,
                ),
                onPressed: _openNotifications,
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: 4,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWorkingHoursPrompt() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED), // orange-50
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)), // orange-200
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time, color: Color(0xFFEA580C)), // orange-600
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Working Hours Not Set',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF9A3412)), // orange-800
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Your salon has no working hours configured. Set them now to avoid missing out on bookings.',
            style: TextStyle(fontSize: 13, color: Color(0xFF9A3412), height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => SalonTimingsScreen(salonId: widget.salonId)))
                    .then((_) => _fetchHomeData(silent: true));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEA580C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Set Timings'),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildScanCard() {
    return InkWell(
      onTap: () => _openScanner(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.accentColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentColor.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            )
          ]
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scan customer QR',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 4),
                  Text('Check someone in and start their appointment',
                      style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _buildTopStats(bool isDark) {
    // Pastel colors adapted for dark mode
    final apptsBg = isDark ? const Color(0xFF3B285E) : const Color(0xFFF3E8FF);
    final apptsText = isDark ? const Color(0xFFD8B4FE) : const Color(0xFF7C3AED);

    final staffBg = isDark ? const Color(0xFF1E3A5F) : const Color(0xFFE0F2FE);
    final staffText = isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7);

    final leaveBg = isDark ? const Color(0xFF4C1D2F) : const Color(0xFFFFE4E6);
    final leaveText = isDark ? const Color(0xFFFDA4AF) : const Color(0xFFE11D48);

    return Row(
      children: [
        Expanded(child: _buildStatCard("Today's Appts", _todaysAppts.toString(), apptsBg, apptsText, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard("Staff on Duty", _staffOnDuty.toString(), staffBg, staffText, isDark)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard("On Leave Today", _onLeaveToday.toString(), leaveBg, leaveText, isDark)),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color bgColor, Color textColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? Colors.white70 : Colors.black54)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor)),
        ],
      ),
    );
  }

  Widget _buildBasicAnalytics(bool isDark) {
    final titleColor = isDark ? AppTheme.darkTextHeading : const Color(0xFF1A1A1A);
    final cardBg = isDark ? AppTheme.darkSurface : Colors.white;
    final accent = AppTheme.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Performance Overview (30d)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 10, offset: const Offset(0, 4)
              )
            ]
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAnalyticsMetric('Revenue', '₹${_insights!.overview.revenue.toStringAsFixed(0)}', accent, isDark),
              Container(width: 1, height: 40, color: isDark ? Colors.white24 : Colors.grey[200]),
              _buildAnalyticsMetric('Visits', '${_insights!.overview.totalVisits}', Colors.blue, isDark),
              Container(width: 1, height: 40, color: isDark ? Colors.white24 : Colors.grey[200]),
              _buildAnalyticsMetric('Avg. Bill', '₹${_insights!.overview.averageBill.toStringAsFixed(0)}', Colors.orange, isDark),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildAnalyticsMetric(String label, String value, Color color, bool isDark) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
      ],
    );
  }

  Widget _buildPeakHoursInsights(bool isDark) {
    final titleColor = isDark ? AppTheme.darkTextHeading : const Color(0xFF1A1A1A);
    final cardBg = isDark ? AppTheme.darkSurface : Colors.white;
    final accentBg = isDark ? const Color(0xFF3B285E) : const Color(0xFFF5F3FF);
    final accentText = isDark ? const Color(0xFFD8B4FE) : const Color(0xFF7C3AED);
    
    final busiest = _insights!.peakHours!.busiest ?? 'Unknown';
    final quietestDay = _insights!.peakHours!.quietestDay ?? 'Unknown';
    final quietestTime = _insights!.peakHours!.quietest ?? 'Unknown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Peak Hour Insights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('GROWTH PLAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
            )
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 10, offset: const Offset(0, 4)
              )
            ]
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: accentBg, shape: BoxShape.circle),
                    child: Icon(Icons.insights, color: accentText),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Busiest Time', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54)),
                        const SizedBox(height: 4),
                        Text(busiest, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: titleColor)),
                        const SizedBox(height: 12),
                        Text('Your Quietest Time', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54)),
                        const SizedBox(height: 4),
                        Text('$quietestDay at $quietestTime', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: titleColor)),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, color: Color(0xFF0284C7), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tip: Try creating a discount or happy hour on $quietestDay around $quietestTime to drive more bookings.',
                        style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7)),
                      ),
                    )
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildQuickActions(bool isDark) {
    final titleColor = isDark ? AppTheme.darkTextHeading : const Color(0xFF1A1A1A);
    final cardBg = isDark ? AppTheme.darkSurface : Colors.white;
    // Add provider uses light purple in demo
    final pBg = isDark ? const Color(0xFF2E2248) : const Color(0xFFF5F3FF);
    final pColor = isDark ? const Color(0xFFA78BFA) : const Color(0xFF8B5CF6);
    
    // Add service uses lighter purple/pink or blue in demo (we use similar to provider)
    final sBg = isDark ? const Color(0xFF2E2248) : const Color(0xFFF5F3FF);
    final sColor = isDark ? const Color(0xFFA78BFA) : const Color(0xFF8B5CF6);

    // Mark closed uses orange
    final cBg = isDark ? const Color(0xFF422E1A) : const Color(0xFFFFFBEB);
    final cColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionBtn("Add Provider", Icons.person_add_alt_1, pBg, pColor, () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => AddStaffScreen(salonId: widget.salonId))).then((_) => _fetchHomeData(silent: true));
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionBtn("Add Service", Icons.add_circle_outline, sBg, sColor, () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => AddServiceFlow(salonId: widget.salonId)));
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionBtn("Mark Closed", Icons.calendar_today, cBg, cColor, () async {
                final now = DateTime.now();
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
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: iconColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingLeavesOrClosure(bool isDark) {
    final titleColor = isDark ? AppTheme.darkTextHeading : const Color(0xFF1A1A1A);

    if (_isClosedToday) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Today\'s Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF4C1D2F) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF9F1239) : const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: isDark ? const Color(0xFFFDA4AF) : const Color(0xFFDC2626)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Salon is Marked Closed Today', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFFDA4AF) : const Color(0xFF991B1B))),
                      if (_closureReason != null && _closureReason!.isNotEmpty)
                        Text('Reason: $_closureReason', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFFFECDD3) : const Color(0xFF991B1B))),
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
            Text('Pending Leave Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor)),
            Text('${_pendingLeaves.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
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
              color: isDark ? AppTheme.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(providerName, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: titleColor)),
                      const SizedBox(height: 4),
                      Text(timeFmt, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
                      if (leave.reason != null && leave.reason!.isNotEmpty)
                        Text(leave.reason!, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black38)),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _decideLeave(leave, 'approved'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    minimumSize: const Size(0, 32),
                    elevation: 0,
                  ),
                  child: const Text('Approve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _decideLeave(leave, 'rejected'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    minimumSize: const Size(0, 32),
                    elevation: 0,
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildProviderLoad(bool isDark) {
    if (_staff.isEmpty) return const SizedBox.shrink();
    
    final titleColor = isDark ? AppTheme.darkTextHeading : const Color(0xFF1A1A1A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Today's Provider Load", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.3,
          ),
          itemCount: _staff.where((s) => s.isActive).length,
          itemBuilder: (context, index) {
            final activeStaff = _staff.where((s) => s.isActive).toList();
            final member = activeStaff[index];
            final load = _providerLoads[member.id] ?? 0;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              ),
              child: Row(
                children: [
                  InitialsAvatar(
                    name: member.user?['name'] ?? 'Unknown',
                    radius: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(member.user?['name'] ?? 'Unknown', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: titleColor)),
                        if (member.specialization != null)
                          Text(member.specialization!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.black45)),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$load', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.accentColor)),
                      Text('appts', style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black45, fontWeight: FontWeight.w600)),
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
