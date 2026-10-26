import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/staff_models.dart';
import '../../../models/leave_models.dart';
import '../../../models/service_models.dart';
import '../../../services/staff_api.dart';
import '../../../services/service_management_api.dart';
import '../../../theme/app_theme.dart';
import 'staff/add_staff_screen.dart';
import 'staff/admin_provider_config_sheet.dart';
import '../../../models/admin_provider_models.dart';
import '../../../services/admin_provider_api.dart';
import '../../../widgets/wallet_coin_pill.dart';
import '../../../widgets/unassigned_services_warning_banner.dart';
import '../../../widgets/assign_service_staff_sheet.dart';

class StaffTab extends StatefulWidget {
  final String salonId;
  const StaffTab({super.key, required this.salonId});

  @override
  State<StaffTab> createState() => StaffTabState();
}

class StaffTabState extends State<StaffTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  bool _isLoadingStaff = true;
  bool get isLoading => _isLoadingStaff || _isLoadingLeaves;
  Future<void>? loadFuture;
  List<StaffMember> _staff = [];
  String? _staffError;
  List<UnassignedServiceItem> _unassignedServices = [];
  bool _isActiveTab = false;

  bool _isLoadingLeaves = true;
  List<ProviderLeave> _leaves = [];
  String? _leaveError;

  AdminProviderStatus? _adminStatus;
  bool _isLoadingAdminStatus = true;
  bool _isTogglingAdmin = false;

  /// Which leave status is shown in the Leave Requests view. Defaults to the
  /// most actionable bucket — the ones still waiting for a decision.
  String _leaveFilter = 'pending';

  @visibleForTesting
  void setTestData({
    List<StaffMember>? staff,
    List<ProviderLeave>? leaves,
    AdminProviderStatus? adminStatus,
    List<UnassignedServiceItem>? unassignedServices,
  }) {
    setState(() {
      if (staff != null) {
        _staff = staff;
        _isLoadingStaff = false;
        _staffError = null;
      }
      if (leaves != null) {
        _leaves = leaves;
        _isLoadingLeaves = false;
        _leaveError = null;
      }
      if (adminStatus != null) {
        _adminStatus = adminStatus;
        _isLoadingAdminStatus = false;
      }
      if (unassignedServices != null) {
        _unassignedServices = unassignedServices;
      }
    });
  }

  void setActive(bool active) {
    if (_isActiveTab == active) return;
    _isActiveTab = active;
    if (active && !_isLoadingStaff) {
      _silentRefreshUnassigned();
    }
  }

  Future<void> _silentRefreshUnassigned() async {
    try {
      final unassigned = await ServiceManagementApi.getUnassignedServices(widget.salonId);
      if (mounted) {
        setState(() {
          _unassignedServices = unassigned;
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    loadFuture = Future.wait([
      _fetchStaff(),
      _fetchLeaves(),
      _fetchAdminStatus(),
    ]);
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
      final result = await StaffApi.fetchStaffDetailed(widget.salonId);
      if (mounted) {
        setState(() {
          _staff = result.staff;
          _unassignedServices = result.unassignedServices;
          _isLoadingStaff = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _staffError = e.toString();
          _isLoadingStaff = false;
        });
      }
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

  Future<void> _fetchAdminStatus() async {
    setState(() => _isLoadingAdminStatus = true);
    try {
      final status = await AdminProviderApi.getStatus(widget.salonId);
      if (mounted) {
        setState(() {
          _adminStatus = status;
          _isLoadingAdminStatus = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAdminStatus = false);
    }
  }

  Future<void> _handleAdminToggle(bool enable) async {
    if (!enable) {
      final upcomingCount = _adminStatus?.upcomingAppointmentsCount ?? 0;
      if (upcomingCount > 0) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) {
            final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Disable Service Provider Mode?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You have $upcomingCount upcoming appointment(s) assigned to you.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'When disabled, customers will no longer be able to select you or book new appointments with you.\n\nYour existing appointments, service assignments, and working hours will be safely preserved for future reactivation.',
                    style: TextStyle(fontSize: 13, color: isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody, height: 1.4),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('Keep Active'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  child: const Text('Disable'),
                ),
              ],
            );
          },
        );
        if (confirmed != true) return;
      }
    }

    setState(() => _isTogglingAdmin = true);
    try {
      final newStatus = await AdminProviderApi.toggle(
        salonId: widget.salonId,
        enabled: enable,
      );
      if (mounted) {
        setState(() {
          _adminStatus = newStatus;
          _isTogglingAdmin = false;
        });
        _refreshAll();

        if (enable && !newStatus.setupValidation.isReadyForBooking) {
          AdminProviderConfigSheet.show(
            context,
            salonId: widget.salonId,
            initialStatus: newStatus,
          ).then((updated) {
            if (updated == true) _refreshAll();
          });
        }
      }
    } on ProviderElsewhereException catch (e) {
      // Became a provider at another salon since this screen loaded: show
      // the explanation in place of the switch.
      if (mounted) {
        setState(() => _isTogglingAdmin = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 4), content: Text(e.message)),
        );
        _fetchAdminStatus();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTogglingAdmin = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 2500),
            content: Text('Failed to update provider mode: $e'),
          ),
        );
      }
    }
  }

  /// Shown instead of the switch when the owner is a service provider at
  /// another of their salons.
  Widget _buildProviderElsewhereCard(ProviderElsewhere elsewhere) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      key: const ValueKey('admin_provider_elsewhere'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.dividerColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.person_pin, color: theme.colorScheme.onSurface.withOpacity(0.5), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Service provider at ${elsewhere.salonName}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  elsewhere.message,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: theme.colorScheme.onSurface.withOpacity(0.65)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminProviderCard() {
    if (_isLoadingAdminStatus) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        height: 80,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
      );
    }

    final elsewhere = _adminStatus?.providerElsewhere;
    if (elsewhere != null) {
      return _buildProviderElsewhereCard(elsewhere);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEnabled = _adminStatus?.isProviderEnabled ?? false;
    final validation = _adminStatus?.setupValidation;
    final isReady = validation?.isReadyForBooking ?? false;
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final cardBg = theme.colorScheme.surface;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled
              ? (isReady ? AppTheme.accentColor.withOpacity(0.4) : Colors.orange.withOpacity(0.4))
              : theme.dividerColor,
          width: isEnabled ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isEnabled
                      ? AppTheme.accentColor.withOpacity(0.12)
                      : theme.dividerColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.person_pin,
                  color: isEnabled ? AppTheme.accentColor : theme.colorScheme.onSurface.withOpacity(0.5),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Also work as a service provider',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: headingColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEnabled
                          ? 'You can receive customer bookings'
                          : 'Accept personal client bookings as owner',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isTogglingAdmin)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch(
                  value: isEnabled,
                  activeColor: AppTheme.accentColor,
                  onChanged: _handleAdminToggle,
                ),
            ],
          ),
          if (isEnabled) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isReady
                        ? (isDark ? AppTheme.darkSuccessBg : AppTheme.lightSuccessBg)
                        : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isReady ? Icons.check_circle : Icons.warning_amber_rounded,
                        size: 14,
                        color: isReady
                            ? (isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess)
                            : const Color(0xFFEA580C),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isReady ? 'Ready for Bookings' : 'Setup Incomplete',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isReady
                              ? (isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess)
                              : const Color(0xFFEA580C),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_adminStatus?.provider?.specialization != null)
                  Expanded(
                    child: Text(
                      _adminStatus!.provider!.specialization!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assigned Services', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                        const SizedBox(height: 2),
                        Text(
                          '${_adminStatus?.provider?.servicesCount ?? 0} Selected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: (_adminStatus?.setupValidation.servicesAssigned ?? false)
                                ? headingColor
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Working Hours', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5))),
                        const SizedBox(height: 2),
                        Text(
                          (_adminStatus?.setupValidation.adminHoursConfigured ?? false)
                              ? 'Configured'
                              : 'Missing',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: (_adminStatus?.setupValidation.adminHoursConfigured ?? false)
                                ? headingColor
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final updated = await AdminProviderConfigSheet.show(
                    context,
                    salonId: widget.salonId,
                    initialStatus: _adminStatus,
                  );
                  if (updated == true) {
                    _refreshAll();
                  }
                },
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Configure Services & Schedule'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentColor,
                  side: const BorderSide(color: AppTheme.accentColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Leave $status successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), content: Text('Failed to update leave: $e')));
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
      _fetchAdminStatus(),
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

        String formatTOD(TimeOfDay t) {
          int h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
          String period = t.hour >= 12 ? 'PM' : 'AM';
          return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
        }

        return '$formattedDate • ${formatTOD(start)} - ${formatTOD(end)}';
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
                      Flexible(
                        child: Text(
                          member.user?['name'] ?? 'Unknown',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
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
    final nonAdmin = _staff.where((s) => !s.isAdminProvider).toList();
    if (_staffFilter == 'active') {
      return nonAdmin.where((s) => s.isActive).toList();
    }
    return nonAdmin;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: AppTheme.accentColor,
        child: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: _buildSummaryRow(),
              ),
              if (_unassignedServices.isNotEmpty)
                SliverToBoxAdapter(
                  child: UnassignedServicesWarningBanner(
                    unassignedServices: _unassignedServices,
                    actionLabel: 'Assign to Staff',
                    onActionPressed: () async {
                      if (_unassignedServices.isNotEmpty) {
                        final updated = await AssignServiceStaffSheet.show(
                          context,
                          salonId: widget.salonId,
                          serviceId: _unassignedServices.first.id,
                          serviceName: _unassignedServices.first.name,
                          unassignedServices: _unassignedServices,
                        );
                        if (updated == true) {
                          _refreshAll();
                        }
                      }
                    },
                    onServicePressed: (service) async {
                      final updated = await AssignServiceStaffSheet.show(
                        context,
                        salonId: widget.salonId,
                        serviceId: service.id,
                        serviceName: service.name,
                        unassignedServices: _unassignedServices,
                      );
                      if (updated == true) {
                        _refreshAll();
                      }
                    },
                  ),
                ),
              // Segmented Tab Bar
              SliverToBoxAdapter(
                child: Container(
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
                        BoxShadow(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(
                            Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.05,
                          ),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    labelColor: Theme.of(context).textTheme.bodyLarge?.color,
                    unselectedLabelColor: AppTheme.accentColor,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: [
                      Tab(text: _isLoadingStaff ? 'All Staff' : 'All Staff ($_totalStaff)'),
                      Tab(text: _isLoadingLeaves ? 'Leave Requests' : 'Leave Requests ($_pendingLeaveRequests)'),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              // All Staff View
              _buildAllStaffTab(context),

              // Leave Requests View
              _buildLeaveRequestsTab(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllStaffTab(BuildContext context) {
    if (_isLoadingStaff) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_staffError != null) {
      return Center(child: Text(_staffError!));
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _buildAdminProviderCard(),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _buildStaffFilterChip('all', 'All Staff'),
                const SizedBox(width: 8),
                _buildStaffFilterChip('active', 'Active'),
              ],
            ),
          ),
        ),
        if (_staff.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No staff added yet.')),
          )
        else if (_filteredStaff.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No active staff found.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _filteredStaff.length) return null;
                  return _buildStaffCard(_filteredStaff[index]);
                },
                childCount: _filteredStaff.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLeaveRequestsTab(BuildContext context) {
    if (_isLoadingLeaves) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_leaveError != null) {
      return Center(child: Text(_leaveError!));
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Status filters — default to the pending bucket.
        SliverToBoxAdapter(
          child: Padding(
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
        ),
        if (_filteredLeaves.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
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
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _filteredLeaves.length) return null;
                  return _buildLeaveCard(_filteredLeaves[index]);
                },
                childCount: _filteredLeaves.length,
              ),
            ),
          ),
      ],
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
