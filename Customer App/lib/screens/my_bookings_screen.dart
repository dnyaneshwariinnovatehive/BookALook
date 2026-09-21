import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';
import '../widgets/rating_bars.dart';
import '../widgets/review_prompt_sheet.dart';
import 'qr_code_screen.dart';
import 'reschedule_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> with SingleTickerProviderStateMixin {
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

  Future<void> _loadBookings() async {
    setState(() => _error = '');

    try {
      final data = await _appointmentService.getMyBookings();
      if (!mounted) return;
      setState(() {
        _upcoming = data['upcoming'] ?? [];
        _past = data['past'] ?? [];
        _cancelCutoffMinutes = (data['cancellation_cutoff_minutes'] ?? 90) as int;
        _rescheduleCutoffMinutes = (data['reschedule_cutoff_minutes'] ?? 90) as int;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
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
        title: Text('Cancel this booking?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${booking['salon']['name']} · ${DateFormat('EEE, MMM d').format(DateTime.parse(booking['appointment_date']))} at ${booking['start_time']}',
              style: GoogleFonts.outfit(color: AppTheme.lightTextBody),
            ),
            SizedBox(height: 16),
            if (advance > 0) ...[
              _dialogRow('Advance paid', '₹${advance.toStringAsFixed(2)}', AppTheme.lightTextHeading),
              SizedBox(height: 6),
              _dialogRow('Refundable', '₹${refundable.toStringAsFixed(2)}', AppTheme.lightSuccess),
              if (forfeited > 0) ...[
                SizedBox(height: 6),
                _dialogRow('Non-refundable', '₹${forfeited.toStringAsFixed(2)}', AppTheme.lightDanger),
              ],
              SizedBox(height: 12),
              Text(
                booking['released_by_salon'] == true
                    ? 'The salon closed this day, so your whole advance comes back. '
                        'You can also keep the booking and just pick a new time.'
                    : 'Refunds follow each service\'s own refund policy.',
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextLight),
              ),
            ] else
              Text('Nothing has been paid for this booking yet.',
                  style: GoogleFonts.outfit(color: AppTheme.lightTextBody)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Keep booking', style: GoogleFonts.outfit(color: AppTheme.lightTextBody)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Cancel booking',
                style: GoogleFonts.outfit(color: AppTheme.lightDanger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await _appointmentService.cancelAppointment(booking['id'].toString());
      final refund = result['refund'] ?? {};
      final refunded = _toDouble(refund['refundable']);

      _showMessage(refunded > 0
          ? 'Booking cancelled. ₹${refunded.toStringAsFixed(2)} will be refunded.'
          : 'Booking cancelled.');

      // Warn when the same-day change penalty has kicked in.
      final requirement = result['payment_requirement'];
      if (requirement != null && requirement['full_upfront'] == true) {
        _showMessage(
          'You have changed ${requirement['changes_used']} bookings for that day. '
          'Further bookings that day need full payment upfront.',
        );
      }

      _loadBookings();
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
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

  Widget _dialogRow(String label, String value, Color valueColor) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
          Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      );

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F9FC),
        elevation: 0,
        title: Text('My Bookings', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
        centerTitle: false,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _error.isNotEmpty
              ? _buildError()
              : Column(
                  children: [
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F0FF),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                          ],
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: AppTheme.accentColor,
                        unselectedLabelColor: AppTheme.accentColor.withOpacity(0.6),
                        labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
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

  Widget _buildError() => Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 56, color: AppTheme.lightTextLight),
              SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center, style: GoogleFonts.outfit(color: AppTheme.lightTextBody)),
              SizedBox(height: 16),
              ElevatedButton(onPressed: _loadBookings, child: Text('Try again')),
            ],
          ),
        ),
      );

  Widget _buildList(List<dynamic> list, {required bool isUpcoming}) {
    if (list.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.accentColor,
        onRefresh: _loadBookings,
        child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: 140),
            Icon(Icons.event_busy, size: 72, color: AppTheme.lightTextBody),
            SizedBox(height: 16),
            Center(
              child: Text(
                isUpcoming ? 'No upcoming appointments.' : 'No past appointments.',
                style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentColor,
      onRefresh: _loadBookings,
      child: ListView.builder(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 100),
        itemCount: isUpcoming ? list.length + 1 : list.length,
        itemBuilder: (context, index) {
          if (isUpcoming && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Bookings can be cancelled up to $_cancelCutoffMinutes minutes or rescheduled up to $_rescheduleCutoffMinutes minutes before the start time.',
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildCard(list[isUpcoming ? index - 1 : index], isUpcoming: isUpcoming),
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

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFF3EBFE),
            Color(0xFFF0E5FE),
            Color(0xFFE9D9FC),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: needsReschedule ? AppTheme.lightWarning : AppTheme.lightPurpleBorder,
          width: needsReschedule ? 2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withOpacity(0.02),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circle in upper-right corner
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE4D0FA).withOpacity(0.7),
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
                  booking['salon']?['cover_image'] ?? booking['salon']?['logo_image'] ?? '',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 48,
                    height: 48,
                    color: const Color(0xFFF3F0FF),
                    child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 24),
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
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
                    ),
                    SizedBox(height: 2),
                    Text(
                      serviceNames,
                      style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _statusChip(booking['status'].toString()),
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
                    Text('Date & Time', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
                    SizedBox(height: 4),
                    Text(
                      '$formattedDate · ${booking['start_time']}',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
                    ),
                  ],
                ),
              ),
              if (isUpcoming)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preferred Stylist', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
                      SizedBox(height: 4),
                      Text(
                        booking['provider_name'] ?? 'Staff',
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Payment', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
                      SizedBox(height: 4),
                      Text(
                        '₹${total.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          if (isUpcoming && booking['salon']['address'] != null) ...[
            SizedBox(height: 12),
            Text('Address', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
            SizedBox(height: 4),
            Text(booking['salon']['address'], style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextHeading)),
          ],

          if (isUpcoming && (services.isNotEmpty || addedServices.isNotEmpty)) ...[
            SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                collapsedIconColor: AppTheme.lightTextBody,
                iconColor: AppTheme.accentColor,
                title: Text('View Details', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentColor)),
                children: [
                  if (addedServices.isNotEmpty) ...[
                    Text('Booked', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: AppTheme.lightTextBody)),
                    SizedBox(height: 8),
                  ],
                  if (services.isNotEmpty)
                    ...services.map((service) => Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  service['combo_name'] != null ? '${service['name']}  ·  ${service['combo_name']}' : service['name'],
                                  style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextHeading),
                                ),
                              ),
                              Text('₹${_toDouble(service['price']).toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.lightTextHeading)),
                            ],
                          ),
                        )),
                  if (addedServices.isNotEmpty) ...[
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.add_circle_outline, size: 13, color: AppTheme.accentColor),
                        SizedBox(width: 5),
                        Text('ADDED AT THE SALON', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: AppTheme.accentColor)),
                      ],
                    ),
                    SizedBox(height: 8),
                    ...addedServices.map((service) => Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(service['name'] ?? 'Service', style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextHeading)),
                                    if (service['provider_name'] != null) Text('by ${service['provider_name']}', style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.lightTextBody)),
                                  ],
                                ),
                              ),
                              Text('₹${_toDouble(service['price']).toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.accentColor)),
                            ],
                          ),
                        )),
                    SizedBox(height: 8),
                    _moneyRow('Booked services', _toDouble(booking['booked_total']), AppTheme.lightTextHeading),
                    SizedBox(height: 4),
                    _moneyRow('Added at the salon', _toDouble(booking['added_total']), AppTheme.accentColor),
                  ],
                  SizedBox(height: 8),
                  _moneyRow('Total', total, AppTheme.lightTextHeading),
                ],
              ),
            ),
          ],

          if (isUpcoming) ...[
            Container(
              margin: EdgeInsets.only(top: services.isEmpty && addedServices.isEmpty ? 16 : 0, bottom: 12),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F9FC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Advance Paid: ', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
                      Text('₹${advance.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
                    ],
                  ),
                  Row(
                    children: [
                      Text('Pay at Salon: ', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
                      Text('₹${balance.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (booking['payment_option'] == 'full_upfront') ...[
            SizedBox(height: 4),
            Text('Paid in full upfront.', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
            SizedBox(height: 8),
          ],
          
          if (booking['cancellation_reason'] != null) ...[
            Text('Reason: ${booking['cancellation_reason']}', style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody)),
            SizedBox(height: 10),
          ],

          if (isUpcoming && (freeReschedule || needsReschedule)) ...[
            Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lightWarningBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.event_busy, size: 18, color: AppTheme.lightWarning),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          needsReschedule ? 'This booking has been released — pick a new time' : 'The salon is closed on this date',
                          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.lightWarning),
                        ),
                        SizedBox(height: 4),
                        Text(
                          booking['closure_reason'] != null
                              ? '${booking['closure_reason']}. Reschedule free of cost — your ₹${advance.toStringAsFixed(0)} advance carries over, and you get all of it back if you cancel instead.'
                              : 'Reschedule free of cost — your ₹${advance.toStringAsFixed(0)} advance carries over, and you get all of it back if you cancel instead.',
                          style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightWarning),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (isUpcoming && !canCancel && cancelBlockedReason != null) ...[
            Text('Cannot cancel: $cancelBlockedReason', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
            SizedBox(height: 6),
          ],

          if (isUpcoming && !canReschedule && rescheduleBlockedReason != null) ...[
            Text('Cannot reschedule: $rescheduleBlockedReason', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
            SizedBox(height: 12),
          ],

          if (isUpcoming && needsReschedule) ...[
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: canReschedule ? () => _openReschedule(booking) : null,
                style: TextButton.styleFrom(
                  backgroundColor: canReschedule ? AppTheme.accentColor : Colors.grey.shade200,
                  foregroundColor: canReschedule ? Colors.white : Colors.grey,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Pick a new time — free', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ),
            ),
            SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: canCancel ? () => _confirmCancel(booking) : null,
                style: TextButton.styleFrom(
                  backgroundColor: canCancel ? const Color(0xFFFEE8EA) : Colors.grey.shade100,
                  foregroundColor: canCancel ? const Color(0xFFE55D68) : Colors.grey,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Cancel and refund ₹${_toDouble(booking['refundable_advance']).toStringAsFixed(0)}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              ),
            ),
          ] else if (isUpcoming) ...[
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: canCancel ? () => _confirmCancel(booking) : null,
                    style: TextButton.styleFrom(
                      backgroundColor: canCancel ? const Color(0xFFFEE8EA) : Colors.grey.shade100,
                      foregroundColor: canCancel ? const Color(0xFFE55D68) : Colors.grey,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Cancel', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    onPressed: canReschedule ? () => _openReschedule(booking) : null,
                    style: TextButton.styleFrom(
                      backgroundColor: canReschedule ? AppTheme.accentColor : Colors.grey.shade200,
                      foregroundColor: canReschedule ? Colors.white : Colors.grey,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(freeReschedule ? 'Reschedule Free' : 'Reschedule', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            if (canGenerateQr) ...[
              SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QrCodeScreen(appointmentId: booking['id'].toString()),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.accentColor,
                    side: const BorderSide(color: AppTheme.accentColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Show QR at salon', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],

          if (!isUpcoming) ..._buildReviewSection(booking),
        ],
      ),
    ),
  ],
),
    );
  }

  List<Widget> _buildReviewSection(Map<String, dynamic> booking) {
    final review = booking['review'] as Map<String, dynamic>?;
    final canReview = booking['can_review'] == true;
    final blockedReason = booking['review_blocked_reason']?.toString();

    if (review != null) {
      return [
        SizedBox(height: 14),
        Divider(color: AppTheme.lightBorder, height: 1),
        SizedBox(height: 12),
        _buildGivenRating(review),
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
          ),
        ),
      ];
    }

    if (blockedReason != null && booking['status'] == 'completed') {
      return [
        SizedBox(height: 12),
        Text(blockedReason,
            style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextLight)),
      ];
    }

    return const [];
  }

  Widget _buildGivenRating(Map<String, dynamic> review) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('You rated this visit',
                style: GoogleFonts.outfit(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.lightTextBody)),
            SizedBox(width: 8),
            StarRow(rating: rating.toDouble(), size: 15),
            Spacer(),
            Text(review['age_label']?.toString() ?? '',
                style: GoogleFonts.outfit(fontSize: 11.5, color: AppTheme.lightTextLight)),
          ],
        ),
        if (comment.isNotEmpty) ...[
          SizedBox(height: 6),
          Text('“$comment”',
              style: GoogleFonts.outfit(
                  fontSize: 13, height: 1.4, color: AppTheme.lightTextBody)),
        ],
      ],
    );
  }

  Future<void> _rateVisit(Map<String, dynamic> booking) async {
    final visitedOn = DateTime.tryParse(booking['appointment_date']?.toString() ?? '');

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
          Text(label, style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody)),
          Text('₹${amount.toStringAsFixed(2)}',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      );

  Widget _statusChip(String status) {
    final color = _getStatusColor(status);
    final text = status.replaceAll('_', ' ').toUpperCase();
    final displayText = text.isNotEmpty ? text[0] + text.substring(1).toLowerCase() : '';
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        displayText,
        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'scheduled':
      case 'confirmed':
        return AppTheme.lightInfo;
      case 'pending_payment':
      case 'in_progress':
      case 'rescheduled':
      case 'awaiting_reschedule':
        return AppTheme.lightWarning;
      case 'completed':
        return AppTheme.lightSuccess;
      case 'cancelled':
      case 'no_show':
        return AppTheme.lightDanger;
      default:
        return AppTheme.lightTextBody;
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
            return const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFBDBDBD)),
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
