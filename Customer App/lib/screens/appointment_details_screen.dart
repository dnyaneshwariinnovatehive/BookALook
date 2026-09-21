import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';
import 'qr_code_screen.dart';
import 'reschedule_screen.dart';
import '../widgets/rating_bars.dart';
import '../widgets/review_prompt_sheet.dart';

class AppointmentDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  final bool isUpcoming;

  const AppointmentDetailsScreen({
    Key? key,
    required this.booking,
    required this.isUpcoming,
  }) : super(key: key);

  @override
  State<AppointmentDetailsScreen> createState() => _AppointmentDetailsScreenState();
}

class _AppointmentDetailsScreenState extends State<AppointmentDetailsScreen> {
  final AppointmentService _appointmentService = AppointmentService();
  bool _hasChanges = false;
  late Map<String, dynamic> _booking;

  @override
  void initState() {
    super.initState();
    _booking = Map.from(widget.booking);
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmCancel() async {
    final refundable = _toDouble(_booking['refundable_advance']);
    final forfeited = _toDouble(_booking['forfeited_advance']);
    final advance = _toDouble(_booking['advance_paid']);

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
              '${_booking['salon']['name']} · ${DateFormat('EEE, MMM d').format(DateTime.parse(_booking['appointment_date']))} at ${_booking['start_time']}',
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
                _booking['released_by_salon'] == true
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
      final result = await _appointmentService.cancelAppointment(_booking['id'].toString());
      final refund = result['refund'] ?? {};
      final refunded = _toDouble(refund['refundable']);

      _showMessage(refunded > 0
          ? 'Booking cancelled. ₹${refunded.toStringAsFixed(2)} will be refunded.'
          : 'Booking cancelled.');

      final requirement = result['payment_requirement'];
      if (requirement != null && requirement['full_upfront'] == true) {
        _showMessage(
          'You have changed ${requirement['changes_used']} bookings for that day. '
          'Further bookings that day need full payment upfront.',
        );
      }
      
      _hasChanges = true;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openReschedule() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RescheduleScreen(
          appointmentId: _booking['id'].toString(),
          freeReschedule: _booking['free_reschedule'] == true,
        ),
      ),
    );

    if (changed == true) {
      _hasChanges = true;
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _rateVisit() async {
    final visitedOn = DateTime.tryParse(_booking['appointment_date']?.toString() ?? '');

    final submitted = await ReviewPromptSheet.show(context, {
      'appointment_id': _booking['id'],
      'salon_name': _booking['salon']?['name'],
      'provider_name': _booking['provider_name'],
      'appointment_date': _booking['appointment_date'],
      'visited_label': visitedOn == null
          ? ''
          : 'On ${DateFormat('d MMM yyyy').format(visitedOn)}',
    });

    if (submitted && mounted) {
      _hasChanges = true;
      Navigator.pop(context, true);
    }
  }

  Widget _dialogRow(String label, String value, Color valueColor) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
          Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      );

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

  Widget _buildStatusChip(String status, bool isDark) {
    final color = _getStatusColor(status);
    final text = status.replaceAll('_', ' ').toUpperCase();
    final displayText = text.isNotEmpty ? text[0] + text.substring(1).toLowerCase() : '';
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        displayText,
        style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child, required bool isDark, required Color headingColor}) {
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightPurpleBorder;
    
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withOpacity(0.02),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: headingColor)),
            SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }

  Widget _moneyRow(String label, double amount, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody)),
          Text('₹${amount.toStringAsFixed(2)}',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headingColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final bgColor = isDark ? AppTheme.darkBg : const Color(0xFFF9F9FC);

    final date = DateTime.parse(_booking['appointment_date']);
    final services = (_booking['services'] as List?) ?? [];
    final addedServices = (_booking['added_services'] as List?) ?? [];
    final total = _toDouble(_booking['total_amount']);
    final advance = _toDouble(_booking['advance_paid']);
    final balance = _toDouble(_booking['balance_amount']);
    
    final freeReschedule = _booking['free_reschedule'] == true;
    final needsReschedule = _booking['needs_reschedule'] == true;
    final canCancel = _booking['can_cancel'] == true;
    final canReschedule = _booking['can_reschedule'] == true;
    final canGenerateQr = _booking['can_generate_qr'] == true;
    
    final cancelBlockedReason = _booking['cancel_blocked_reason'];
    final rescheduleBlockedReason = _booking['reschedule_blocked_reason'];

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
    final formattedDate = '$datePrefix${DateFormat('d MMM yyyy').format(date)}';

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _hasChanges);
        return false;
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: headingColor),
            onPressed: () => Navigator.pop(context, _hasChanges),
          ),
          title: Text('Appointment Details', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: headingColor)),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Salon & Service Summary
              _buildSection(
                title: '',
                isDark: isDark,
                headingColor: headingColor,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        _booking['salon']?['cover_image'] ?? _booking['salon']?['cover_photo_url'] ?? _booking['salon']?['logo_image'] ?? '',
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 60,
                          height: 60,
                          color: const Color(0xFFF3F0FF),
                          child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 28),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _booking['salon']?['name'] ?? 'Salon',
                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: headingColor),
                          ),
                          SizedBox(height: 4),
                          Text(
                            serviceNames,
                            style: GoogleFonts.outfit(fontSize: 14, color: bodyColor),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    _buildStatusChip(_booking['status'].toString(), isDark),
                  ],
                ),
              ),

              // 2. Appointment Details (Date/Time/Stylist)
              _buildSection(
                title: 'Appointment',
                isDark: isDark,
                headingColor: headingColor,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Date & Time', style: GoogleFonts.outfit(fontSize: 13, color: bodyColor)),
                          SizedBox(height: 4),
                          Text(
                            '$formattedDate · ${_booking['start_time']}',
                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: headingColor),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Preferred Stylist', style: GoogleFonts.outfit(fontSize: 13, color: bodyColor)),
                          SizedBox(height: 4),
                          Text(
                            _booking['provider_name'] ?? 'Staff',
                            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: headingColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Location
              if (_booking['salon']['address'] != null)
                _buildSection(
                  title: 'Location',
                  isDark: isDark,
                  headingColor: headingColor,
                  child: Text(_booking['salon']['address'], style: GoogleFonts.outfit(fontSize: 14, color: headingColor)),
                ),

              // 4. Payment & Services Breakdown
              if (services.isNotEmpty || addedServices.isNotEmpty)
                _buildSection(
                  title: 'Payment Details',
                  isDark: isDark,
                  headingColor: headingColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (addedServices.isNotEmpty) ...[
                        Text('Booked', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: bodyColor)),
                        SizedBox(height: 10),
                      ],
                      if (services.isNotEmpty)
                        ...services.map((service) => Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      service['combo_name'] != null ? '${service['name']}  ·  ${service['combo_name']}' : service['name'],
                                      style: GoogleFonts.outfit(fontSize: 14, color: headingColor),
                                    ),
                                  ),
                                  Text('₹${_toDouble(service['price']).toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: headingColor)),
                                ],
                              ),
                            )),
                      if (addedServices.isNotEmpty) ...[
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.add_circle_outline, size: 14, color: AppTheme.accentColor),
                            SizedBox(width: 5),
                            Text('ADDED AT THE SALON', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: AppTheme.accentColor)),
                          ],
                        ),
                        SizedBox(height: 10),
                        ...addedServices.map((service) => Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(service['name'] ?? 'Service', style: GoogleFonts.outfit(fontSize: 14, color: headingColor)),
                                        if (service['provider_name'] != null) Text('by ${service['provider_name']}', style: GoogleFonts.outfit(fontSize: 12, color: bodyColor)),
                                      ],
                                    ),
                                  ),
                                  Text('₹${_toDouble(service['price']).toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.accentColor)),
                                ],
                              ),
                            )),
                        SizedBox(height: 12),
                        _moneyRow('Booked services', _toDouble(_booking['booked_total']), headingColor),
                        SizedBox(height: 6),
                        _moneyRow('Added at the salon', _toDouble(_booking['added_total']), AppTheme.accentColor),
                      ],
                      
                      SizedBox(height: 12),
                      Divider(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      SizedBox(height: 12),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: headingColor)),
                          Text('₹${total.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: headingColor)),
                        ],
                      ),
                      
                      if (widget.isUpcoming) ...[
                        SizedBox(height: 16),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkBg : const Color(0xFFF9F9FC),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Advance Paid', style: GoogleFonts.outfit(fontSize: 12, color: bodyColor)),
                                  SizedBox(height: 2),
                                  Text('₹${advance.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: headingColor)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Pay at Salon', style: GoogleFonts.outfit(fontSize: 12, color: bodyColor)),
                                  SizedBox(height: 2),
                                  Text('₹${balance.toStringAsFixed(0)}', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: headingColor)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_booking['payment_option'] == 'full_upfront') ...[
                        SizedBox(height: 12),
                        Text('Paid in full upfront.', style: GoogleFonts.outfit(fontSize: 13, color: bodyColor)),
                      ],
                    ],
                  ),
                ),

              // 5. Status / Rules / Messages
              if (widget.isUpcoming && (freeReschedule || needsReschedule || !canCancel || !canReschedule || _booking['cancellation_reason'] != null))
                _buildSection(
                  title: 'Booking Info',
                  isDark: isDark,
                  headingColor: headingColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_booking['cancellation_reason'] != null) ...[
                        Text('Reason: ${_booking['cancellation_reason']}', style: GoogleFonts.outfit(fontSize: 14, color: bodyColor)),
                        SizedBox(height: 12),
                      ],

                      if (freeReschedule || needsReschedule) ...[
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkWarningBg : AppTheme.lightWarningBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.event_busy, size: 20, color: isDark ? AppTheme.darkWarning : AppTheme.lightWarning),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      needsReschedule ? 'This booking has been released — pick a new time' : 'The salon is closed on this date',
                                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? AppTheme.darkWarning : AppTheme.lightWarning),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      _booking['closure_reason'] != null
                                          ? '${_booking['closure_reason']}. Reschedule free of cost — your ₹${advance.toStringAsFixed(0)} advance carries over, and you get all of it back if you cancel instead.'
                                          : 'Reschedule free of cost — your ₹${advance.toStringAsFixed(0)} advance carries over, and you get all of it back if you cancel instead.',
                                      style: GoogleFonts.outfit(fontSize: 13, color: isDark ? AppTheme.darkWarning : AppTheme.lightWarning),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                      ],

                      if (!canCancel && cancelBlockedReason != null) ...[
                        Text('Cannot cancel: $cancelBlockedReason', style: GoogleFonts.outfit(fontSize: 13, color: bodyColor)),
                        SizedBox(height: 8),
                      ],

                      if (!canReschedule && rescheduleBlockedReason != null) ...[
                        Text('Cannot reschedule: $rescheduleBlockedReason', style: GoogleFonts.outfit(fontSize: 13, color: bodyColor)),
                      ],
                    ],
                  ),
                ),

              // 6. Actions (Cancel, Reschedule, QR Code)
              if (widget.isUpcoming && (needsReschedule || canCancel || canReschedule || canGenerateQr))
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    children: [
                      if (needsReschedule) ...[
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: canReschedule ? _openReschedule : null,
                            style: TextButton.styleFrom(
                              backgroundColor: canReschedule ? (isDark ? AppTheme.darkButtonBg : AppTheme.accentColor) : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                              foregroundColor: canReschedule ? Colors.white : (isDark ? Colors.grey.shade500 : Colors.grey),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text('Pick a new time — free', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                        SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: canCancel ? _confirmCancel : null,
                            style: TextButton.styleFrom(
                              backgroundColor: canCancel ? (isDark ? AppTheme.darkDangerBg : const Color(0xFFFEE8EA)) : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
                              foregroundColor: canCancel ? AppTheme.lightDanger : (isDark ? Colors.grey.shade500 : Colors.grey),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text('Cancel and refund ₹${_toDouble(_booking['refundable_advance']).toStringAsFixed(0)}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: canCancel ? _confirmCancel : null,
                                style: TextButton.styleFrom(
                                  backgroundColor: canCancel ? (isDark ? AppTheme.darkDangerBg : const Color(0xFFFEE8EA)) : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
                                  foregroundColor: canCancel ? AppTheme.lightDanger : (isDark ? Colors.grey.shade500 : Colors.grey),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: Text('Cancel', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: TextButton(
                                onPressed: canReschedule ? _openReschedule : null,
                                style: TextButton.styleFrom(
                                  backgroundColor: canReschedule ? (isDark ? AppTheme.darkButtonBg : AppTheme.accentColor) : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                  foregroundColor: canReschedule ? Colors.white : (isDark ? Colors.grey.shade500 : Colors.grey),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: Text(freeReschedule ? 'Reschedule Free' : 'Reschedule', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (canGenerateQr) ...[
                        SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => QrCodeScreen(appointmentId: _booking['id'].toString()),
                              ),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
                              foregroundColor: AppTheme.accentColor,
                              side: const BorderSide(color: AppTheme.accentColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              padding: EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text('Show QR at salon', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // 7. Reviews (if past)
              if (!widget.isUpcoming) ..._buildReviewSection(isDark, headingColor, bodyColor),
              
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildReviewSection(bool isDark, Color headingColor, Color bodyColor) {
    final review = _booking['review'] as Map<String, dynamic>?;
    final canReview = _booking['can_review'] == true;
    final blockedReason = _booking['review_blocked_reason']?.toString();

    if (review != null) {
      final rating = (review['rating'] as num?)?.toInt() ?? 0;
      final comment = review['comment']?.toString() ?? '';
      final lightColor = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;

      return [
        _buildSection(
          title: 'Your Review',
          isDark: isDark,
          headingColor: headingColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StarRow(rating: rating.toDouble(), size: 16),
                  Spacer(),
                  Text(review['age_label']?.toString() ?? '', style: GoogleFonts.outfit(fontSize: 12, color: lightColor)),
                ],
              ),
              if (comment.isNotEmpty) ...[
                SizedBox(height: 12),
                Text('“$comment”', style: GoogleFonts.outfit(fontSize: 14, height: 1.4, color: bodyColor)),
              ],
            ],
          ),
        ),
      ];
    }

    if (canReview) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _rateVisit,
              icon: Icon(Icons.star_rounded, size: 22),
              label: Text('Rate your visit', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? AppTheme.darkButtonBg : AppTheme.accentColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
        ),
      ];
    }

    if (blockedReason != null && _booking['status'] == 'completed') {
      return [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Text(blockedReason, style: GoogleFonts.outfit(fontSize: 13, color: isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight)),
        ),
      ];
    }

    return const [];
  }
}
