import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';
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
      appBar: AppBar(
        title: Text('My Bookings', style: AppTheme.lightTheme.appBarTheme.titleTextStyle),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.accentColor,
          unselectedLabelColor: AppTheme.lightTextBody,
          indicatorColor: AppTheme.accentColor,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16),
          tabs: [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _error.isNotEmpty
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_upcoming, isUpcoming: true),
                    _buildList(_past, isUpcoming: false),
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
            Icon(Icons.event_busy, size: 72, color: AppTheme.lightTextLight),
            SizedBox(height: 16),
            Center(
              child: Text(
                isUpcoming ? 'No upcoming appointments.' : 'No past appointments.',
                style: GoogleFonts.outfit(color: AppTheme.lightTextLight, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentColor,
      onRefresh: _loadBookings,
      child: ListView.separated(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(20),
        // One extra leading row on Upcoming for the cutoff notice.
        itemCount: isUpcoming ? list.length + 1 : list.length,
        separatorBuilder: (context, index) => SizedBox(height: 16),
        itemBuilder: (context, index) {
          if (isUpcoming && index == 0) {
            return Text(
              'Bookings can be cancelled up to $_cancelCutoffMinutes minutes or rescheduled up to $_rescheduleCutoffMinutes minutes before the start time.',
              style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextLight),
            );
          }

          return _buildCard(list[isUpcoming ? index - 1 : index], isUpcoming: isUpcoming);
        },
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> booking, {required bool isUpcoming}) {
    final date = DateTime.parse(booking['appointment_date']);
    final services = (booking['services'] as List?) ?? [];
    final total = _toDouble(booking['total_amount']);
    final advance = _toDouble(booking['advance_paid']);
    final balance = _toDouble(booking['balance_amount']);
    final freeReschedule = booking['free_reschedule'] == true;
    // The salon closed the day and released this booking — only the customer
    // can resolve it, so the card is styled to demand attention.
    final needsReschedule = booking['needs_reschedule'] == true;
    final canCancel = booking['can_cancel'] == true;
    final canReschedule = booking['can_reschedule'] == true;
    final canGenerateQr = booking['can_generate_qr'] == true;
    final cancelBlockedReason = booking['cancel_blocked_reason'];
    final rescheduleBlockedReason = booking['reschedule_blocked_reason'];

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: needsReschedule ? AppTheme.lightWarning : AppTheme.lightBorder,
          width: needsReschedule ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(DateFormat('EEE, MMM d, yyyy').format(date),
                  style: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
              _statusChip(booking['status'].toString()),
            ],
          ),
          SizedBox(height: 12),

          Text(booking['salon']['name'] ?? 'Salon',
              style: GoogleFonts.outfit(
                  fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.lightTextHeading)),
          if (booking['salon']['address'] != null) ...[
            SizedBox(height: 2),
            Text(booking['salon']['address'],
                style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextLight)),
          ],

          SizedBox(height: 10),
          _iconLine(Icons.access_time, '${booking['start_time']} – ${booking['end_time']}'),
          SizedBox(height: 4),
          _iconLine(Icons.person_outline, booking['provider_name'] ?? 'Staff'),

          if (services.isNotEmpty) ...[
            SizedBox(height: 14),
            Divider(color: AppTheme.lightBorder, height: 1),
            SizedBox(height: 12),
            ...services.map((service) => Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          service['combo_name'] != null
                              ? '${service['name']}  ·  ${service['combo_name']}'
                              : service['name'],
                          style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody),
                        ),
                      ),
                      Text('₹${_toDouble(service['price']).toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                              fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.lightTextHeading)),
                    ],
                  ),
                )),
          ],

          SizedBox(height: 12),
          Divider(color: AppTheme.lightBorder, height: 1),
          SizedBox(height: 12),

          _moneyRow('Total', total, AppTheme.lightTextHeading),
          SizedBox(height: 4),
          _moneyRow('Advance paid', advance, AppTheme.lightSuccess),
          SizedBox(height: 4),
          _moneyRow('Balance at salon', balance, AppTheme.lightTextBody),

          if (booking['payment_option'] == 'full_upfront') ...[
            SizedBox(height: 8),
            Text('Paid in full upfront.',
                style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextLight)),
          ],

          if (booking['cancellation_reason'] != null) ...[
            SizedBox(height: 10),
            Text('Reason: ${booking['cancellation_reason']}',
                style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextLight)),
          ],

          if (isUpcoming && (freeReschedule || needsReschedule)) ...[
            SizedBox(height: 14),
            Container(
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
                          needsReschedule
                              ? 'This booking has been released — pick a new time'
                              : 'The salon is closed on this date',
                          style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.lightWarning),
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
            SizedBox(height: 12),
            Text('Cannot cancel: $cancelBlockedReason', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextLight)),
          ],

          if (isUpcoming && !canReschedule && rescheduleBlockedReason != null) ...[
            SizedBox(height: 6),
            Text('Cannot reschedule: $rescheduleBlockedReason', style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextLight)),
          ],

          // A released booking has one job: get a new time. Rescheduling is the
          // primary action and the QR is meaningless until it has a slot again.
          if (isUpcoming && needsReschedule) ...[
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canReschedule ? () => _openReschedule(booking) : null,
                child: Text('Pick a new time — free'),
              ),
            ),
            SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: canCancel ? () => _confirmCancel(booking) : null,
                child: Text('Cancel and refund ₹${_toDouble(booking['refundable_advance']).toStringAsFixed(0)}'),
              ),
            ),
          ] else if (isUpcoming) ...[
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canCancel ? () => _confirmCancel(booking) : null,
                    child: Text('Cancel'),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: canReschedule ? () => _openReschedule(booking) : null,
                    child: Text(freeReschedule ? 'Reschedule free' : 'Reschedule'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canGenerateQr
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => QrCodeScreen(appointmentId: booking['id'].toString()),
                          ),
                        )
                    : null,
                child: Text(canGenerateQr ? 'Show QR at salon' : 'QR available on the day'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconLine(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.lightTextBody),
          SizedBox(width: 6),
          Expanded(child: Text(text, style: GoogleFonts.outfit(color: AppTheme.lightTextBody))),
        ],
      );

  Widget _moneyRow(String label, double amount, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
          Text('₹${amount.toStringAsFixed(2)}',
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        ],
      );

  Widget _statusChip(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: color),
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
