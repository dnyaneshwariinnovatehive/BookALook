import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';
import '../utils/app_haptics.dart';
import '../widgets/invoice_actions.dart';
import '../widgets/rating_bars.dart';
import '../widgets/review_prompt_sheet.dart';
import '../widgets/complaint_bottom_sheet.dart';
import 'appointment_details_screen.dart';
import 'reschedule_screen.dart';
import '../theme/app_colors.dart';
import '../services/explore_request_bus.dart';
import '../utils/error_text.dart';
import '../widgets/feedback_states.dart';
import '../widgets/skeleton.dart';
import '../utils/bottom_clearance.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => MyBookingsScreenState();
}

class MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AppointmentService _appointmentService = AppointmentService();

  List<dynamic> _upcoming = [];
  List<dynamic> _past = [];
  bool _isLoading = true;
  String _error = '';
  int _cancelCutoffMinutes = 90;
  int _rescheduleCutoffMinutes = 90;

  String _historyFilter = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> loadBookings() => _loadBookings();

  Future<void> _loadBookings() async {
    setState(() => _error = '');

    try {
      final data = await _appointmentService.getMyBookings();
      if (!mounted) return;
      setState(() {
        _upcoming = data['upcoming'] ?? [];
        _past = data['past'] ?? [];
        _cancelCutoffMinutes =
            (data['cancellation_cutoff_minutes'] ?? 90) as int;
        _rescheduleCutoffMinutes =
            (data['reschedule_cutoff_minutes'] ?? 90) as int;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, fallback: 'We could not load your bookings.');
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmCancel(Map<String, dynamic> booking) async {
    final refundable = _toDouble(booking['refundable_advance']);
    final forfeited = _toDouble(booking['forfeited_advance']);
    final advance = _toDouble(booking['advance_paid']);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: dialogContext.colors.border, width: 1),
        ),
        title: Text(
          'Cancel this booking?',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: dialogContext.colors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${booking['salon']['name']} · ${DateFormat('EEE, MMM d').format(DateTime.parse(booking['appointment_date']))} at ${booking['start_time']}',
              style: GoogleFonts.outfit(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (advance > 0) ...[
              _dialogRow(
                'Advance paid',
                '₹${advance.toStringAsFixed(2)}',
                context.colors.textPrimary,
              ),
              const SizedBox(height: 6),
              _dialogRow(
                'Refundable',
                '₹${refundable.toStringAsFixed(2)}',
                context.colors.success,
              ),
              if (forfeited > 0) ...[
                const SizedBox(height: 6),
                _dialogRow(
                  'Non-refundable',
                  '₹${forfeited.toStringAsFixed(2)}',
                  context.colors.danger,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                booking['released_by_salon'] == true
                    ? 'The salon closed this day, so your whole advance comes back. '
                          'You can also keep the booking and just pick a new time.'
                    : 'Refunds follow each service\'s own refund policy.',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: context.colors.textTertiary,
                ),
              ),
            ] else
              Text(
                'Nothing has been paid for this booking yet.',
                style: GoogleFonts.outfit(color: context.colors.textSecondary),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Keep booking',
              style: GoogleFonts.outfit(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Cancel booking',
              style: GoogleFonts.outfit(
                color: context.colors.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _appointmentService.cancelAppointment(
        booking['id'].toString(),
      );
      final refund = result['refund'] ?? {};
      final refunded = _toDouble(refund['refundable']);

      final cancelled = refunded > 0
          ? 'Booking cancelled. ₹${refunded.toStringAsFixed(2)} will be refunded.'
          : 'Booking cancelled.';

      final requirement = result['payment_requirement'];
      if (requirement != null && requirement['full_upfront'] == true) {
        _toast(
          '$cancelled You have changed ${requirement['changes_used']} bookings for that day, '
          'so further bookings that day need full payment upfront.',
        );
      } else {
        _toast(cancelled);
      }

      _loadBookings();
    } catch (e) {
      AppHaptics.error();
      _setCardMessage(
        booking,
        describeError(
          e,
          fallback: 'Could not cancel this booking. Please try again.',
        ),
      );
      _loadBookings();
    }
  }

  Future<void> _openReschedule(Map<String, dynamic> booking) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RescheduleScreen(
          appointmentId: booking['id'].toString(),
          freeReschedule: booking['free_reschedule'] == true,
        ),
      ),
    );

    if (changed == true) _loadBookings();
  }

  /// Shows a modal to call the service provider or salon if their number is available.
  Future<void> _callProvider(Map<String, dynamic> booking) async {
    final salon = booking['salon'] as Map<String, dynamic>? ?? const {};
    final salonPhone = salon['phone']?.toString().trim() ?? '';
    final providerPhone = booking['provider_phone']?.toString().trim() ?? '';
    final raw = providerPhone.isNotEmpty ? providerPhone : salonPhone;
    final name = providerPhone.isNotEmpty
        ? (booking['provider_name']?.toString().trim() ?? 'Your provider')
        : (salon['name']?.toString().trim() ?? 'Salon');

    if (raw.isEmpty || !RegExp(r'^\+?[\d\s\-()]{6,20}$').hasMatch(raw)) {
      _setCardMessage(
        booking,
        'Provider contact details are not available yet.',
        kind: StatusKind.info,
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: isDark ? BorderSide(color: context.colors.border, width: 1) : BorderSide.none,
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? context.colors.border : Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? context.colors.accentSoft : const Color(0xFFF5EFFF),
                  shape: BoxShape.circle,
                  border: isDark ? Border.all(color: context.colors.border, width: 1) : null,
                ),
                child: const Icon(
                  Icons.person,
                  size: 36,
                  color: AppTheme.accentColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                raw,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.phone),
                  label: Text(
                    'Call Now',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    final uri = Uri(
                      scheme: 'tel',
                      path: raw.replaceAll(RegExp(r'[^\d+]'), ''),
                    );
                    try {
                      if (!await canLaunchUrl(uri) ||
                          !await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          )) {
                        _setCardMessage(booking, 'Could not open the dialler.');
                      }
                    } catch (_) {
                      _setCardMessage(booking, 'Could not open the dialler.');
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  /// Opens turn-by-turn navigation to the salon.
  Future<void> _openDirections(Map<String, dynamic> booking) async {
    final salon = booking['salon'] as Map<String, dynamic>? ?? const {};
    final lat = (salon['latitude'] as num?)?.toDouble();
    final lng = (salon['longitude'] as num?)?.toDouble();
    final address = salon['address']?.toString().trim() ?? '';
    final name = salon['name']?.toString().trim() ?? 'Salon';

    final query = lat != null && lng != null
        ? '$lat,$lng'
        : (address.isNotEmpty
              ? Uri.encodeComponent('$name, $address')
              : Uri.encodeComponent(name));

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );

    try {
      if (!await canLaunchUrl(uri) ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _setCardMessage(booking, 'Could not open maps.');
      }
    } catch (_) {
      _setCardMessage(booking, 'Could not open maps.');
    }
  }

  /// Action button component for the upcoming booking card (Call, Directions, Reschedule, Cancel)
  Widget _buildCardActionButton({
    required IconData icon,
    required String label,
    required Color iconColor,
    required VoidCallback onTap,
    bool isEnabled = true,
  }) {
    final effectiveColor = isEnabled ? iconColor : context.colors.textTertiary;
    final effectiveTextColor = isEnabled ? context.colors.textPrimary : context.colors.textTertiary;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: effectiveColor),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: effectiveTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogRow(String label, String value, Color valueColor) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 14,
          color: context.colors.textSecondary,
        ),
      ),
      Text(
        value,
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: valueColor,
        ),
      ),
    ],
  );

  void _toast(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  final Map<String, ({String text, StatusKind kind})> _cardMessages = {};

  void _setCardMessage(
    Map<String, dynamic> booking,
    String text, {
    StatusKind kind = StatusKind.error,
  }) {
    if (!mounted) return;
    setState(
      () => _cardMessages[booking['id'].toString()] = (text: text, kind: kind),
    );
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: context.colors.surfaceMuted,
      body: Stack(
        children: [
          // Background decorative waves inspired by reference screenshot
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _BookingBackgroundPainter(isDark: isDark),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isDark),
                _buildTabBar(isDark),
                const SizedBox(height: 4),
                Expanded(
                  child: _isLoading
                      ? SkeletonList(
                          count: 3,
                          padding: EdgeInsets.fromLTRB(
                            20,
                            16,
                            20,
                            bottomClearance(context),
                          ),
                          itemBuilder: (_) => const BookingCardSkeleton(),
                        )
                      : _error.isNotEmpty
                      ? _buildError()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildList(_upcoming, isUpcoming: true),
                            _buildHistoryList(isDark),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Screen Header with prominent "My Bookings", subtitle, and 3D Calendar illustration
  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Bookings',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Manage your appointments',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          _buildCalendarIllustration(isDark),
        ],
      ),
    );
  }

  /// 3D-styled Calendar/Checklist illustration in the upper right
  Widget _buildCalendarIllustration(bool isDark) {
    return Transform.rotate(
      angle: 0.06,
      child: Container(
        width: 58,
        height: 60,
        decoration: BoxDecoration(
          color: isDark ? context.colors.surface : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isDark ? context.colors.border : const Color(0xFFEEE3FD),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9850F1).withValues(alpha: isDark ? 0.25 : 0.16),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Purple binder bar
            Container(
              height: 16,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF9850F1), Color(0xFF7B32EC)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBinderRing(),
                  _buildBinderRing(),
                  _buildBinderRing(),
                ],
              ),
            ),
            // Sheet with checkmark
            Expanded(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Container(
                            height: 1.5,
                            color: isDark
                                ? context.colors.border.withValues(alpha: 0.7)
                                : const Color(0xFFF3EBFE),
                          ),
                          Container(
                            height: 1.5,
                            color: isDark
                                ? context.colors.border.withValues(alpha: 0.7)
                                : const Color(0xFFF3EBFE),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_rounded,
                      size: 24,
                      color: Color(0xFF9850F1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBinderRing() => Container(
    width: 4,
    height: 7,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  /// Redesigned Segmented Control for Upcoming and History Tabs
  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? context.colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? context.colors.border : const Color(0xFFECEAF2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppTheme.accentColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentColor.withValues(alpha: 0.28),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: isDark
            ? context.colors.textSecondary
            : const Color(0xFF4A4553),
        labelStyle: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(text: 'Upcoming'),
          Tab(text: 'History'),
        ],
      ),
    );
  }

  /// Cancellation and Rescheduling Policy Banner
  Widget _buildPolicyBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? context.colors.accentSoft : const Color(0xFFF6F0FE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? context.colors.border : const Color(0xFFEEE3FD),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            child: const Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: Color(0xFF9850F1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bookings can be cancelled up to $_cancelCutoffMinutes minutes or rescheduled up to $_rescheduleCutoffMinutes minutes before the start time.',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: isDark ? context.colors.textSecondary : const Color(0xFF6A5E82),
                height: 1.4,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(bool isDark) {
    List<dynamic> filtered = _past;
    if (_historyFilter != 'All') {
      filtered = _past.where((b) {
        String status = (b['status'] ?? '').toString().toLowerCase();
        if (_historyFilter == 'Completed' && status == 'completed') return true;
        if (_historyFilter == 'Cancelled' && status == 'cancelled') return true;
        if (_historyFilter == 'Rescheduled' && status == 'rescheduled') {
          return true;
        }
        if (_historyFilter == 'No Show' && status == 'no_show') return true;
        return false;
      }).toList();
    }

    return Column(
      children: [
        _buildFilterCapsules(isDark),
        Expanded(child: _buildList(filtered, isUpcoming: false)),
      ],
    );
  }

  Widget _buildFilterCapsules(bool isDark) {
    final filters = ['All', 'Completed', 'Cancelled', 'Rescheduled', 'No Show'];
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _historyFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _historyFilter = filter);
                }
              },
              backgroundColor: isDark ? context.colors.surface : Colors.white,
              selectedColor: isDark
                  ? AppTheme.accentColor.withValues(alpha: 0.22)
                  : AppTheme.accentColor.withValues(alpha: 0.12),
              checkmarkColor: isDark
                  ? const Color(0xFFEEE3FD)
                  : AppTheme.accentColor,
              labelStyle: GoogleFonts.outfit(
                color: isSelected
                    ? (isDark ? const Color(0xFFEEE3FD) : AppTheme.accentColor)
                    : context.colors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? AppTheme.accentColor
                      : context.colors.border,
                  width: isSelected ? 1.4 : 1.0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildError() => RefreshIndicator(
    color: AppTheme.accentColor,
    onRefresh: _loadBookings,
    child: ScrollableStateView(
      bottomInset: bottomClearance(context),
      child: ErrorState(
        title: 'Could not load your bookings',
        message: _error,
        onRetry: () {
          setState(() => _isLoading = true);
          _loadBookings();
        },
      ),
    ),
  );

  Widget _buildList(List<dynamic> list, {required bool isUpcoming}) {
    if (list.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.accentColor,
        onRefresh: _loadBookings,
        child: ScrollableStateView(
          bottomInset: bottomClearance(context),
          child: isUpcoming
              ? EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No upcoming appointments',
                  message: 'When you book a salon, it shows up here.',
                  actionLabel: 'Explore salons',
                  onAction: ExploreRequestBus.instance.showAll,
                )
              : const EmptyState(
                  icon: Icons.history_rounded,
                  title: 'No past appointments',
                  message:
                      'Visits you have completed or cancelled appear here.',
                ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentColor,
      onRefresh: _loadBookings,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomClearance(context)),
        itemCount: isUpcoming ? list.length + 1 : list.length,
        itemBuilder: (context, index) {
          if (isUpcoming && index == 0) {
            return _buildPolicyBanner(Theme.of(context).brightness == Brightness.dark);
          }

          final booking = list[isUpcoming ? index - 1 : index];

          if (!isUpcoming) {
            return _buildCompactHistoryCard(booking);
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildUpcomingCard(booking),
          );
        },
      ),
    );
  }

  /// Redesigned Upcoming Booking Card
  Widget _buildUpcomingCard(Map<String, dynamic> booking) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final date =
        DateTime.tryParse(booking['appointment_date']?.toString() ?? '') ??
        DateTime.now();
    final services = (booking['services'] as List?) ?? [];
    final total = _toDouble(booking['total_amount']);
    final advance = _toDouble(booking['advance_paid']);
    final balance = _toDouble(booking['balance_amount']);
    final needsReschedule = booking['needs_reschedule'] == true;
    final isAlreadyRescheduled = booking['rescheduled_from_id'] != null;
    final canCancel = !isAlreadyRescheduled && booking['can_cancel'] == true;
    final canReschedule = !isAlreadyRescheduled && booking['can_reschedule'] == true;
    final cancelBlockedReason = isAlreadyRescheduled
        ? 'Rescheduled appointments cannot be cancelled.'
        : booking['cancel_blocked_reason']?.toString();
    final rescheduleBlockedReason = isAlreadyRescheduled
        ? 'This appointment has already been rescheduled once.'
        : booking['reschedule_blocked_reason']?.toString();
    final salon = booking['salon'] as Map<String, dynamic>? ?? const {};
    final salonPhone = salon['phone']?.toString().trim() ?? '';
    final providerPhone = booking['provider_phone']?.toString().trim() ?? '';
    final hasPhone = providerPhone.isNotEmpty || salonPhone.isNotEmpty;
    final canNavigate =
        salonPhone.isNotEmpty ||
        (salon['address']?.toString().trim() ?? '').isNotEmpty;

    String serviceNames = services.map((s) => s['name']).join(', ');
    if (serviceNames.isEmpty) serviceNames = 'Service';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final bookingDate = DateTime(date.year, date.month, date.day);

    String datePrefix = '';
    if (bookingDate == today) {
      datePrefix = 'Today, ';
    } else if (bookingDate == tomorrow) {
      datePrefix = 'Tomorrow, ';
    } else {
      datePrefix = DateFormat('EEE, ').format(date);
    }
    final formattedDate = '$datePrefix${DateFormat('d MMM').format(date)}';

    final status = (booking['status'] ?? '').toString();
    final imageUrl =
        booking['salon']?['cover_image'] ??
        booking['salon']?['cover_photo_url'] ??
        booking['salon']?['logo_image'] ??
        '';

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: needsReschedule
              ? context.colors.warning
              : context.colors.border,
          width: needsReschedule ? 1.8 : 1.0,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF9850F1).withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () async {
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => AppointmentDetailsScreen(
                  booking: booking,
                  isUpcoming: true,
                ),
              ),
            );
            if (changed == true || mounted) {
              _loadBookings();
            }
          },
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top: Salon and service details + Status badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDark
                            ? context.colors.accentSoft
                            : const Color(0xFFF5EFFF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? context.colors.border
                              : const Color(0xFFEEE3FD),
                          width: 1.0,
                        ),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                    Icons.storefront_outlined,
                                    color: Color(0xFF9850F1),
                                    size: 24,
                                  ),
                            )
                          : const Icon(
                              Icons.storefront_outlined,
                              color: Color(0xFF9850F1),
                              size: 24,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking['salon']?['name'] ?? 'Salon',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: context.colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            serviceNames,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: context.colors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildUpcomingStatusBadge(
                      status,
                      isRescheduled: isAlreadyRescheduled,
                      isDark: isDark,
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(
                  color: context.colors.border,
                  height: 1,
                  thickness: 1,
                ),
                const SizedBox(height: 14),

                // Middle: Appointment Details (Date & Time + Stylist)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date & Time
                    Expanded(
                      flex: 5,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 20,
                            color: Color(0xFF9850F1),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Date & Time',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11.5,
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formattedDate,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: context.colors.textPrimary,
                                  ),
                                ),
                                Text(
                                  booking['start_time'] ?? '',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Divider
                    Container(
                      width: 1,
                      height: 42,
                      color: context.colors.border,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                    ),

                    // Stylist
                    Expanded(
                      flex: 5,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 22,
                            color: Color(0xFF9850F1),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stylist',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11.5,
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  booking['provider_name']
                                              ?.toString()
                                              .isNotEmpty ==
                                          true
                                      ? booking['provider_name']
                                      : 'Any Staff',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: context.colors.textPrimary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (total > 0 || advance > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? context.colors.accentSoft
                          : const Color(0xFFF7F4FD),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: context.colors.border,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Advance Paid: ₹${advance.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Pay at Salon: ₹${balance.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Total Payment: ₹${total.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: context.colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_cardMessages[booking['id'].toString()]
                    case final note?) ...[
                  const SizedBox(height: 10),
                  InlineStatus(
                    message: note.text,
                    kind: note.kind,
                    onDismiss: () => setState(
                      () => _cardMessages.remove(booking['id'].toString()),
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // 4 Action Buttons Row: Call, Directions, Reschedule, Cancel
                Row(
                  children: [
                    _buildCardActionButton(
                      icon: Icons.call_outlined,
                      label: 'Call',
                      iconColor: const Color(0xFF9850F1),
                      onTap: () {
                        AppHaptics.lightImpact();
                        if (hasPhone) {
                          _callProvider(booking);
                        } else {
                          _toast(
                            'Provider contact details will be available before your appointment.',
                          );
                        }
                      },
                    ),
                    Container(
                      width: 1,
                      height: 26,
                      color: context.colors.border,
                    ),
                    _buildCardActionButton(
                      icon: Icons.directions_outlined,
                      label: 'Directions',
                      iconColor: const Color(0xFF9850F1),
                      onTap: () {
                        AppHaptics.lightImpact();
                        if (canNavigate) {
                          _openDirections(booking);
                        } else {
                          _toast('This salon has no address on record.');
                        }
                      },
                    ),
                    Container(
                      width: 1,
                      height: 26,
                      color: context.colors.border,
                    ),
                    _buildCardActionButton(
                      icon: Icons.edit_calendar_outlined,
                      label: 'Reschedule',
                      iconColor: const Color(0xFF9850F1),
                      isEnabled: canReschedule,
                      onTap: () {
                        AppHaptics.lightImpact();
                        if (canReschedule) {
                          _openReschedule(booking);
                        } else if (rescheduleBlockedReason != null &&
                            rescheduleBlockedReason.isNotEmpty) {
                          _toast(rescheduleBlockedReason);
                        } else {
                          _toast(
                            'Rescheduling is not available for this appointment.',
                          );
                        }
                      },
                    ),
                    Container(
                      width: 1,
                      height: 26,
                      color: context.colors.border,
                    ),
                    _buildCardActionButton(
                      icon: Icons.cancel_outlined,
                      label: 'Cancel',
                      iconColor: context.colors.danger,
                      isEnabled: canCancel,
                      onTap: () {
                        AppHaptics.lightImpact();
                        if (canCancel) {
                          _confirmCancel(booking);
                        } else if (cancelBlockedReason != null &&
                            cancelBlockedReason.isNotEmpty) {
                          _toast(cancelBlockedReason);
                        } else {
                          _toast('This booking cannot be cancelled.');
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Status badge palette generator for light and dark modes
  ({Color bg, Color text, Color border}) _getStatusBadgeColors(
    String status, {
    required bool isDark,
    bool isRescheduled = false,
  }) {
    if (isRescheduled) {
      return (
        bg: isDark ? const Color(0xFF28183B) : const Color(0xFFF5EFFF),
        text: isDark ? const Color(0xFFC084FC) : const Color(0xFF9850F1),
        border: isDark ? const Color(0xFF4D2B75) : const Color(0xFFEEE3FD),
      );
    }

    final lower = status.toLowerCase();
    switch (lower) {
      case 'scheduled':
      case 'confirmed':
        return (
          bg: isDark ? const Color(0xFF142E1F) : const Color(0xFFE8F8EE),
          text: isDark ? const Color(0xFF4ADE80) : const Color(0xFF1B873F),
          border: isDark ? const Color(0xFF225934) : const Color(0xFFC8E6C9),
        );
      case 'in_progress':
      case 'pending_payment':
      case 'awaiting_reschedule':
        return (
          bg: isDark ? const Color(0xFF33200D) : const Color(0xFFFFF3E0),
          text: isDark ? const Color(0xFFFBBF24) : const Color(0xFFEF6C00),
          border: isDark ? const Color(0xFF5A3912) : const Color(0xFFFFE0B2),
        );
      case 'completed':
        return (
          bg: isDark ? const Color(0xFF142E1F) : const Color(0xFFE8F5E9),
          text: isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32),
          border: isDark ? const Color(0xFF225934) : const Color(0xFFC8E6C9),
        );
      case 'rescheduled':
        return (
          bg: isDark ? const Color(0xFF28183B) : const Color(0xFFF5EFFF),
          text: isDark ? const Color(0xFFC084FC) : const Color(0xFF9850F1),
          border: isDark ? const Color(0xFF4D2B75) : const Color(0xFFEEE3FD),
        );
      case 'cancelled':
      case 'no_show':
        return (
          bg: isDark ? const Color(0xFF381519) : const Color(0xFFFFEBEE),
          text: isDark ? const Color(0xFFF87171) : const Color(0xFFC62828),
          border: isDark ? const Color(0xFF6B2228) : const Color(0xFFFFCDD2),
        );
      default:
        return (
          bg: isDark ? const Color(0xFF24202D) : const Color(0xFFF2EFF6),
          text: isDark ? const Color(0xFFA7A1B8) : const Color(0xFF7C758D),
          border: isDark ? const Color(0xFF3A3048) : const Color(0xFFE0E0E0),
        );
    }
  }

  Widget _buildUpcomingStatusBadge(
    String status, {
    bool isRescheduled = false,
    required bool isDark,
  }) {
    final colors = _getStatusBadgeColors(
      status,
      isDark: isDark,
      isRescheduled: isRescheduled,
    );

    final displayText = isRescheduled
        ? 'Rescheduled'
        : (status.toLowerCase() == 'scheduled' || status.toLowerCase() == 'confirmed')
            ? 'Scheduled'
            : status
                .replaceAll('_', ' ')
                .split(' ')
                .map((s) => s.isNotEmpty ? s[0].toUpperCase() + s.substring(1).toLowerCase() : '')
                .join(' ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.text,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            displayText,
            style: GoogleFonts.outfit(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHistoryCard(Map<String, dynamic> booking) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final date =
        DateTime.tryParse(booking['appointment_date']?.toString() ?? '') ??
        DateTime.now();
    final services = (booking['services'] as List?) ?? [];
    final total = _toDouble(booking['total_amount']);

    String serviceNames = services.map((s) => s['name']).join(', ');
    if (serviceNames.isEmpty) serviceNames = 'Service';

    final formattedDate = DateFormat('d MMM yyyy').format(date);
    final timeStr = booking['start_time'] ?? '';

    final status = (booking['status'] ?? '').toString();
    final statusText = status
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (s) => s.isNotEmpty
              ? s[0].toUpperCase() + s.substring(1).toLowerCase()
              : '',
        )
        .join(' ');

    final imageUrl =
        booking['salon']?['cover_image'] ??
        booking['salon']?['cover_photo_url'] ??
        booking['salon']?['logo_image'] ??
        '';

    final badgeColors = _getStatusBadgeColors(status, isDark: isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 1.0),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: AppTheme.accentColor.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: InkWell(
        onTap: () async {
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  AppointmentDetailsScreen(booking: booking, isUpcoming: false),
            ),
          );
          if (changed == true || mounted) {
            _loadBookings();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark
                          ? context.colors.accentSoft
                          : const Color(0xFFF5EFFF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? context.colors.border
                            : const Color(0xFFEEE3FD),
                        width: 1.0,
                      ),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.storefront_outlined,
                                  color: AppTheme.accentColor,
                                  size: 20,
                                ),
                          )
                        : const Icon(
                            Icons.storefront_outlined,
                            color: AppTheme.accentColor,
                            size: 20,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking['salon']?['name'] ?? 'Salon',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: context.colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          serviceNames,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: context.colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$formattedDate • $timeStr',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: context.colors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₹${total.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: context.colors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColors.bg,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: badgeColors.border,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                statusText,
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: badgeColors.text,
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
              ..._buildCompactReviewAndInvoiceSection(booking, isDark),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCompactReviewAndInvoiceSection(
    Map<String, dynamic> booking,
    bool isDark,
  ) {
    final review = booking['review'] as Map<String, dynamic>?;
    final canReview = booking['can_review'] == true;
    final blockedReason = booking['review_blocked_reason']?.toString();
    final isPast = ['completed', 'cancelled', 'no_show']
        .contains(booking['status']?.toString().toLowerCase());

    final bool mightHaveInvoice =
        booking['invoice'] is Map && booking['status'] == 'completed';

    if (!mightHaveInvoice &&
        review == null &&
        !canReview &&
        !isPast &&
        (blockedReason == null || booking['status'] != 'completed')) {
      return const [];
    }

    return [
      const SizedBox(height: 12),
      Divider(color: context.colors.border, height: 1),
      const SizedBox(height: 4),
      InvoiceLinkButton(booking: booking),
      if (review != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _buildCompactGivenRating(review),
        ),
        if (isPast)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () => _reportProblem(booking),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.report_problem_outlined,
                        size: 13,
                        color: isDark ? context.colors.textSecondary : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Report issue',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? context.colors.textSecondary : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ] else if (canReview)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: InkWell(
                  onTap: () => _rateVisit(booking),
                  borderRadius: BorderRadius.circular(30),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_outline_rounded,
                          size: 16,
                          color: AppTheme.accentColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Rate your visit',
                            style: GoogleFonts.outfit(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _reportProblem(booking),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.report_problem_outlined,
                        size: 13,
                        color: isDark ? context.colors.textSecondary : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Report issue',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? context.colors.textSecondary : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )
      else if (isPast)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (blockedReason != null && booking['status'] == 'completed')
                Expanded(
                  child: Text(
                    blockedReason,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                )
              else
                const Spacer(),
              InkWell(
                onTap: () => _reportProblem(booking),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.report_problem_outlined,
                        size: 13,
                        color: isDark ? context.colors.textSecondary : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Report issue',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? context.colors.textSecondary : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildCompactGivenRating(Map<String, dynamic> review) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Rated',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            StarRow(rating: rating.toDouble(), size: 12),
            const Spacer(),
            Text(
              review['age_label']?.toString() ?? '',
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '“$comment”',
            style: GoogleFonts.outfit(
              fontSize: 12,
              height: 1.3,
              color: context.colors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Future<void> _rateVisit(Map<String, dynamic> booking) async {
    final visitedOn = DateTime.tryParse(
      booking['appointment_date']?.toString() ?? '',
    );

    final submitted = await ReviewPromptSheet.show(context, {
      'appointment_id': booking['id'],
      'salon_name': booking['salon']?['name'],
      'provider_name': booking['provider_name'],
      'appointment_date': booking['appointment_date'],
      'visited_label': visitedOn == null
          ? ''
          : 'On ${DateFormat('d MMM yyyy').format(visitedOn)}',
    });

    if (submitted && mounted) await _loadBookings();
  }

  Future<void> _reportProblem(Map<String, dynamic> booking) async {
    final submitted = await ComplaintBottomSheet.show(context, booking);
    if (submitted && mounted) await _loadBookings();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'scheduled':
      case 'confirmed':
        return const Color(0xFF1B873F);
      case 'pending_payment':
      case 'in_progress':
      case 'rescheduled':
      case 'awaiting_reschedule':
        return const Color(0xFFEF6C00);
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'cancelled':
      case 'no_show':
        return const Color(0xFFC62828);
      default:
        return const Color(0xFF7C758D);
    }
  }
}

/// Subtle Curved Wave Background painter for the royal-purple theme
class _BookingBackgroundPainter extends CustomPainter {
  final bool isDark;

  const _BookingBackgroundPainter({this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (isDark) return;

    // Soft top-right ambient lavender glow under the calendar illustration
    final topPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.85, -0.9),
        radius: 0.75,
        colors: [
          const Color(0xFFEEE3FD).withValues(alpha: 0.65),
          const Color(0xFFFCFAFF).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.45));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.45),
      topPaint,
    );

    // Wave 1: Deeper organic background curve near bottom
    final wave1Paint = Paint()
      ..color = const Color(0xFFF3EBFE).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.moveTo(0, size.height * 0.78);
    path1.cubicTo(
      size.width * 0.35,
      size.height * 0.72,
      size.width * 0.65,
      size.height * 0.85,
      size.width,
      size.height * 0.76,
    );
    path1.lineTo(size.width, size.height);
    path1.lineTo(0, size.height);
    path1.close();
    canvas.drawPath(path1, wave1Paint);

    // Wave 2: Foreground smooth lavender sweep curve near bottom
    final wave2Paint = Paint()
      ..color = const Color(0xFFEEE3FD).withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(0, size.height * 0.84);
    path2.cubicTo(
      size.width * 0.25,
      size.height * 0.89,
      size.width * 0.55,
      size.height * 0.79,
      size.width,
      size.height * 0.86,
    );
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();
    canvas.drawPath(path2, wave2Paint);
  }

  @override
  bool shouldRepaint(covariant _BookingBackgroundPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
