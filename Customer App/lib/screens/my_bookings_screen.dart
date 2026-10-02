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
import 'appointment_details_screen.dart';
import 'qr_code_screen.dart';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel this booking?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${booking['salon']['name']} · ${DateFormat('EEE, MMM d').format(DateTime.parse(booking['appointment_date']))} at ${booking['start_time']}',
              style: GoogleFonts.outfit(color: context.colors.textSecondary),
            ),
            SizedBox(height: 16),
            if (advance > 0) ...[
              _dialogRow(
                'Advance paid',
                '₹${advance.toStringAsFixed(2)}',
                context.colors.textPrimary,
              ),
              SizedBox(height: 6),
              _dialogRow(
                'Refundable',
                '₹${refundable.toStringAsFixed(2)}',
                context.colors.success,
              ),
              if (forfeited > 0) ...[
                SizedBox(height: 6),
                _dialogRow(
                  'Non-refundable',
                  '₹${forfeited.toStringAsFixed(2)}',
                  context.colors.danger,
                ),
              ],
              SizedBox(height: 12),
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

      // One confirmation, not two stacked SnackBars where the second hides
      // the first. The same-day penalty is the half that matters.
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
      _setCardMessage(booking, describeError(e, fallback: 'Could not cancel this booking. Please try again.'));
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

  /// Dials the salon, if it published a number to call.
  ///
  /// The appointment payload's salon phone is the business line, so this is a
  /// call to the shop. A salon with none gets a plain refusal rather than a
  /// button that silently does nothing.
  Future<void> _callSalon(Map<String, dynamic> booking) async {
    final raw = booking['salon']?['phone']?.toString().trim() ?? '';

    // Dialled verbatim, so anything but a real number is refused here rather
    // than handed to the dialer.
    if (raw.isEmpty || !RegExp(r'^\+?[\d\s\-()]{6,20}$').hasMatch(raw)) {
      _setCardMessage(booking, 'This salon has not published a contact number.', kind: StatusKind.info);
      return;
    }

    final uri = Uri(scheme: 'tel', path: raw.replaceAll(RegExp(r'[^\d+]'), ''));

    try {
      if (!await canLaunchUrl(uri) ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _setCardMessage(booking, 'Could not open the dialler.');
      }
    } catch (_) {
      _setCardMessage(booking, 'Could not open the dialler.');
    }
  }

  /// Opens turn-by-turn navigation to the salon.
  ///
  /// Prefers the salon's pin when it has one, and falls back to searching the
  /// address — a salon at its city centre has no pin, but the address is still
  /// enough for a maps app to find it.
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

  /// The four square actions on an upcoming booking.
  ///
  /// Laid out as a 2x2 grid rather than capsules: four verbs need a scannable
  /// block, and a grid keeps them the same size whether or not one of them is
  /// currently disabled.
  Widget _buildActionGrid(
    Map<String, dynamic> booking,
    {
    required bool canCancel,
    required bool canReschedule,
    required bool freeReschedule,
  }) {
    final salon = booking['salon'] as Map<String, dynamic>? ?? const {};
    final hasPhone = (salon['phone']?.toString().trim() ?? '').isNotEmpty;
    final canNavigate =
        hasPhone || (salon['address']?.toString().trim() ?? '').isNotEmpty;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSquareAction(
                icon: Icons.phone_outlined,
                label: 'Call',
                enabled: hasPhone,
                onTap: () => _callSalon(booking),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSquareAction(
                icon: Icons.directions_outlined,
                label: 'Directions',
                enabled: canNavigate,
                onTap: () => _openDirections(booking),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSquareAction(
                icon: Icons.edit_calendar_outlined,
                label: freeReschedule ? 'Reschedule Free' : 'Reschedule',
                enabled: canReschedule,
                onTap: () => _openReschedule(booking),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSquareAction(
                icon: Icons.close_rounded,
                label: 'Cancel',
                enabled: canCancel,
                danger: true,
                onTap: () => _confirmCancel(booking),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// One action: a rounded square holding an icon above its label.
  ///
  /// The label is never dropped or truncated away, because an icon-only button
  /// makes the customer guess between a calendar and a phone.
  Widget _buildSquareAction({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final borderColor = context.colors.cardBorder;

    final Color background;
    final Color foreground;

    if (!enabled) {
      background = context.colors.disabledFillSoft;
      foreground = Colors.grey.shade500;
    } else if (danger) {
      background = context.colors.dangerSoft;
      foreground = context.colors.danger;
    } else {
      background = context.colors.actionTile;
      foreground = AppTheme.accentColor;
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.75,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled
              ? () {
                  AppHaptics.lightImpact();
                  onTap();
                }
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 78,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: enabled && danger
                    ? context.colors.dangerOutline
                    : borderColor,
                width: 1.3,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(height: 6),
                // Scales down rather than wrapping or ellipsising, so
                // "Reschedule Free" stays readable on a narrow card and every
                // label in the row is the same height.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
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
        style: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary),
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

  /// Confirmations only, e.g. "Booking cancelled." — they may vanish.
  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// A problem with one booking's action (cancel, call, directions), shown
  /// inside that booking's card, above its buttons — not in a SnackBar over
  /// the bottom of the list, which may be nowhere near the card that was
  /// tapped. Keyed by booking id; dismissed by the customer or replaced by
  /// the next message for the same card.
  final Map<String, ({String text, StatusKind kind})> _cardMessages = {};

  void _setCardMessage(
    Map<String, dynamic> booking,
    String text, {
    StatusKind kind = StatusKind.error,
  }) {
    if (!mounted) return;
    setState(() => _cardMessages[booking['id'].toString()] = (text: text, kind: kind));
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final headingColor = context.colors.textPrimary;

    return Scaffold(
      backgroundColor: context.colors.pageNeutral,
      appBar: AppBar(
        backgroundColor: context.colors.pageNeutral,
        elevation: 0,
        title: Text(
          'My Bookings',
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: headingColor,
          ),
        ),
        centerTitle: false,
      ),
      body: _isLoading
          ? SkeletonList(
              count: 3,
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottomClearance(context)),
              itemBuilder: (_) => const BookingCardSkeleton(),
            )
          : _error.isNotEmpty
          ? _buildError()
          : Column(
              children: [
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.colors.imagePlaceholder,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: AppTheme.accentColor,
                    unselectedLabelColor: AppTheme.accentColor.withValues(alpha: 0.6),
                    labelStyle: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    tabs: const [
                      Tab(text: 'Upcoming'),
                      Tab(text: 'History'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(_upcoming, isUpcoming: true),
                      _buildList(_past, isUpcoming: false),
                    ],
                  ),
                ),
              ],
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
          // Back to the skeleton while it retries, so the tap visibly does
          // something even on a slow connection.
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
                  message: 'Visits you have completed or cancelled appear here.',
                ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentColor,
      onRefresh: _loadBookings,
      child: ListView.builder(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomClearance(context)),
        itemCount: isUpcoming ? list.length + 1 : list.length,
        itemBuilder: (context, index) {
          if (isUpcoming && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Bookings can be cancelled up to $_cancelCutoffMinutes minutes or rescheduled up to $_rescheduleCutoffMinutes minutes before the start time.',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildCard(
              list[isUpcoming ? index - 1 : index],
              isUpcoming: isUpcoming,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> booking, {required bool isUpcoming}) {
    final date = DateTime.parse(booking['appointment_date']);
    final services = (booking['services'] as List?) ?? [];
    final addedServices = (booking['added_services'] as List?) ?? [];
    final total = _toDouble(booking['total_amount']);
    final advance = _toDouble(booking['advance_paid']);
    final balance = _toDouble(booking['balance_amount']);
    final freeReschedule = booking['free_reschedule'] == true;
    final needsReschedule = booking['needs_reschedule'] == true;
    final canCancel = booking['can_cancel'] == true;
    final canReschedule = booking['can_reschedule'] == true;
    final canGenerateQr = booking['can_generate_qr'] == true;
    final cancelBlockedReason = booking['cancel_blocked_reason'];
    final rescheduleBlockedReason = booking['reschedule_blocked_reason'];

    String serviceNames = services.map((s) => s['name']).join(', ');
    if (serviceNames.isEmpty) serviceNames = 'Service';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final borderColor = context.colors.cardBorder;
    final surfaceColor = context.colors.surface;
    final bgGradient = isDark
        ? null
        : const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFF3EBFE), Color(0xFFF0E5FE), Color(0xFFE9D9FC)],
            stops: [0.0, 0.5, 1.0],
          );

    return InkWell(
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => AppointmentDetailsScreen(
              booking: booking,
              isUpcoming: isUpcoming,
            ),
          ),
        );
        if (changed == true) {
          _loadBookings();
        }
      },
      borderRadius: BorderRadius.circular(26),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: surfaceColor,
          gradient: bgGradient,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: needsReschedule ? context.colors.warning : borderColor,
            width: needsReschedule ? 2 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentColor.withValues(alpha: 0.02),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative glow in upper-right corner
            if (!isDark)
              Positioned(
                top: -50,
                right: -50,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFCBA4F2).withValues(alpha: 0.45),
                        const Color(0xFFCBA4F2).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          booking['salon']?['cover_image'] ??
                              booking['salon']?['cover_photo_url'] ??
                              booking['salon']?['logo_image'] ??
                              '',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 48,
                            height: 48,
                            color: context.colors.imagePlaceholder,
                            child: Icon(
                              Icons.storefront,
                              color: AppTheme.accentColor,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              booking['salon']?['name'] ?? 'Salon',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: headingColor,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              serviceNames,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: bodyColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _statusChip(booking['status'].toString(), isDark),
                    ],
                  ),

                  SizedBox(height: 16),
                  _DashedDivider(),
                  SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date & Time',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: bodyColor,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '$formattedDate · ${booking['start_time']}',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: headingColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isUpcoming)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Preferred Stylist',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: bodyColor,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                booking['provider_name'] ?? 'Staff',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: headingColor,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Payment',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: bodyColor,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '₹${total.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: headingColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  if (isUpcoming) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.pageNeutral,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Advance Paid: ',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: bodyColor,
                                ),
                              ),
                              Text(
                                '₹${advance.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: headingColor,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                'Pay at Salon: ',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: bodyColor,
                                ),
                              ),
                              Text(
                                '₹${balance.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: headingColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_cardMessages[booking['id'].toString()] case final note?) ...[
                    SizedBox(height: 12),
                    InlineStatus(
                      message: note.text,
                      kind: note.kind,
                      onDismiss: () => setState(() => _cardMessages.remove(booking['id'].toString())),
                    ),
                  ],

                  if (isUpcoming && needsReschedule) ...[
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: canReschedule
                            ? () => _openReschedule(booking)
                            : null,
                        style: TextButton.styleFrom(
                          backgroundColor: canReschedule
                              ? context.colors.actionFill
                              : context.colors.disabledFill,
                          foregroundColor: canReschedule
                              ? Colors.white
                              : Colors.grey.shade500,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Pick a new time — free',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: canCancel
                            ? () => _confirmCancel(booking)
                            : null,
                        style: TextButton.styleFrom(
                          backgroundColor: canCancel
                              ? context.colors.dangerSoft
                              : context.colors.disabledFillSoft,
                          foregroundColor: canCancel
                              ? context.colors.danger
                              : Colors.grey.shade500,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Cancel and refund ₹${_toDouble(booking['refundable_advance']).toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ] else if (isUpcoming) ...[
                    const SizedBox(height: 14),
                    _buildActionGrid(
                      booking,
                      canCancel: canCancel,
                      canReschedule: canReschedule,
                      freeReschedule: freeReschedule,
                    ),
                  ],

                  if (!isUpcoming) ...[
                    SizedBox(height: 12),
                    InvoiceLinkButton(booking: booking),
                  ],

                  if (!isUpcoming)
                    ..._buildReviewSection(
                      booking,
                      headingColor,
                      bodyColor,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildReviewSection(
    Map<String, dynamic> booking,
    Color headingColor,
    Color bodyColor,
  ) {
    final review = booking['review'] as Map<String, dynamic>?;
    final canReview = booking['can_review'] == true;
    final blockedReason = booking['review_blocked_reason']?.toString();

    if (review != null) {
      return [
        SizedBox(height: 14),
        Divider(
          color: context.colors.border,
          height: 1,
        ),
        SizedBox(height: 12),
        _buildGivenRating(
          review,
          bodyColor,
          context.colors.textTertiary,
        ),
      ];
    }

    if (canReview) {
      return [
        SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _rateVisit(booking),
            icon: Icon(Icons.star_rounded, size: 19),
            label: Text('Rate your visit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.actionFill,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ];
    }

    if (blockedReason != null && booking['status'] == 'completed') {
      return [
        SizedBox(height: 12),
        Text(
          blockedReason,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: context.colors.textTertiary,
          ),
        ),
      ];
    }

    return const [];
  }

  Widget _buildGivenRating(
    Map<String, dynamic> review,
    Color bodyColor,
    Color lightColor,
  ) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'You rated this visit',
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: bodyColor,
              ),
            ),
            SizedBox(width: 8),
            StarRow(rating: rating.toDouble(), size: 15),
            Spacer(),
            Text(
              review['age_label']?.toString() ?? '',
              style: GoogleFonts.outfit(fontSize: 11.5, color: lightColor),
            ),
          ],
        ),
        if (comment.isNotEmpty) ...[
          SizedBox(height: 6),
          Text(
            '“$comment”',
            style: GoogleFonts.outfit(
              fontSize: 13,
              height: 1.4,
              color: bodyColor,
            ),
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

  Widget _moneyRow(String label, double amount, Color color) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: GoogleFonts.outfit(fontSize: 13, color: context.colors.textSecondary),
      ),
      Text(
        '₹${amount.toStringAsFixed(2)}',
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ],
  );

  Widget _statusChip(String status, bool isDark) {
    final color = _getStatusColor(status);
    final text = status.replaceAll('_', ' ').toUpperCase();
    final displayText = text.isNotEmpty
        ? text[0] + text.substring(1).toLowerCase()
        : '';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        displayText,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'scheduled':
      case 'confirmed':
        return context.colors.info;
      case 'pending_payment':
      case 'in_progress':
      case 'rescheduled':
      case 'awaiting_reschedule':
        return context.colors.warning;
      case 'completed':
        return context.colors.success;
      case 'cancelled':
      case 'no_show':
        return context.colors.danger;
      default:
        return context.colors.textSecondary;
    }
  }
}

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.dashLine,
                ),
              ),
            );
          }),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
        );
      },
    );
  }
}
