import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/check_in_api.dart';
import 'check_in_confirm_sheet.dart';
import 'collect_payment_sheet.dart';
import 'qr_scanner_screen.dart';

class ProviderAppointmentDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> appointment;
  final String salonId;

  const ProviderAppointmentDetailsScreen({
    Key? key,
    required this.appointment,
    required this.salonId,
  }) : super(key: key);

  @override
  State<ProviderAppointmentDetailsScreen> createState() => _ProviderAppointmentDetailsScreenState();
}

class _ProviderAppointmentDetailsScreenState extends State<ProviderAppointmentDetailsScreen> {
  late Map<String, dynamic> _apt = Map<String, dynamic>.from(widget.appointment);
  bool _isProcessing = false;

  String get _appointmentId => _apt['id'].toString();

  Future<void> _refresh() async {
    try {
      final target = await CheckInApi.bill(widget.salonId, _appointmentId);
      if (!mounted) return;
      setState(() {
        _apt['status'] = target.appointment.status;
        _apt['total_amount'] = target.appointment.totalAmount;
        _apt['balance_amount'] = target.appointment.balanceAmount;
        _apt['payment_mode'] = target.appointment.paymentMode;
      });
    } catch (_) {
      // Leave the screen usable if the refresh fails.
    }
  }

  /// Scan the customer's code to begin. Falls back to a manual start when they
  /// cannot show one.
  Future<void> _startSession({required bool scan}) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      if (scan) {
        final started = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => QrScannerScreen(
              salonId: widget.salonId,
              expectedAppointmentId: _appointmentId,
            ),
          ),
        );
        if (started == true) await _refresh();
      } else {
        final target = await CheckInApi.resolve(widget.salonId, appointmentId: _appointmentId);
        if (!mounted) return;
        final started = await CheckInConfirmSheet.show(
          context,
          salonId: widget.salonId,
          target: target,
        );
        if (started) await _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Bill summary and payment. Completing the job and taking the money are the
  /// same action — there is no tab.
  Future<void> _openBill() async {
    final collected = await CollectPaymentSheet.show(
      context,
      salonId: widget.salonId,
      appointmentId: _appointmentId,
    );

    if (collected) {
      await _refresh();
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apt = _apt;
    final bool isWalkIn = apt['booking_source'] == 'walk_in';
    
    final customer = apt['customer'] ?? {};
    final String customerName = isWalkIn ? (apt['walk_in_customer_name'] ?? 'Walk-In Customer') : (customer['name'] ?? 'Unknown');
    final String customerPhone = isWalkIn ? (apt['walk_in_customer_phone'] ?? '') : (customer['phone'] ?? '');
    final String customerEmail = customer['email'] ?? ''; // Might be empty for walk-ins

    final String status = (apt['status'] ?? '').toString().toUpperCase();
    final bool isScheduled = apt['status'] == 'scheduled';
    final bool isInProgress = apt['status'] == 'in_progress';
    final bool canComplete = isScheduled || isInProgress;

    final num totalAmount = apt['total_amount'] ?? 0;
    final num advancePaid = apt['advance_amount'] ?? 0;
    final num balanceDue = apt['balance_amount'] ?? totalAmount;

    final List services = apt['services'] ?? [];
    int totalDuration = services.fold(0, (sum, s) => sum + (s['duration_minutes_at_booking'] as int? ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text('Appointment Details', style: GoogleFonts.outfit(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100), // Padding for bottom button
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Status Pills
                Row(
                  children: [
                    _buildPill(status, const Color(0xFFFEF3C7), const Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    _buildPill(isWalkIn ? 'Walk-In' : 'Online Booking', const Color(0xFFF3E8FF), const Color(0xFF9333EA)),
                  ],
                ),
                const SizedBox(height: 16),

                // Customer Details Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFFE0F2FE),
                            child: const Icon(Icons.person_outline, color: Color(0xFF0369A1)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(customerName, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (customerPhone.isNotEmpty) ...[
                                      const Icon(Icons.phone, size: 14, color: Color(0xFF9CA3AF)),
                                      const SizedBox(width: 4),
                                      Text(customerPhone, style: GoogleFonts.outfit(color: const Color(0xFF6B7280), fontSize: 13)),
                                    ],
                                    if (customerEmail.isNotEmpty) ...[
                                      const SizedBox(width: 12),
                                      const Icon(Icons.email_outlined, size: 14, color: Color(0xFF9CA3AF)),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(customerEmail, style: GoogleFonts.outfit(color: const Color(0xFF6B7280), fontSize: 13), overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Services Section
                Text('SERVICES', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF6B7280), letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: services.map((s) {
                      final srv = s['service'] ?? {};
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(srv['name'] ?? 'Service', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937))),
                                  const SizedBox(height: 4),
                                  Text('${s['duration_minutes_at_booking']} mins', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF9CA3AF))),
                                ],
                              ),
                            ),
                            Text('₹${s['price_at_booking']}', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1F2937))),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // Financial Details Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _buildInfoRow('Time Slot', '${apt['start_time']} ($totalDuration mins)'),
                      _buildInfoRow('Payment Method', apt['payment_option'] == 'full_at_venue' ? 'Pay at Venue' : 'Prepaid'),
                      _buildInfoRow('Total Amount', '₹$totalAmount'),
                      _buildInfoRow('Advance Paid', '₹$advancePaid', valueColor: const Color(0xFF16A34A)),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Color(0xFFF3F4F6))),
                      _buildInfoRow('Balance Due', '₹$balanceDue', isBold: true, valueColor: const Color(0xFFDC2626)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Notes / Warnings
                if (apt['customer_notes'] != null && apt['customer_notes'].toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFFEF9C3), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFFCA8A04), size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(apt['customer_notes'], style: GoogleFonts.outfit(color: const Color(0xFF854D0E), fontSize: 13))),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),
                
                // Final Billed Amount
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FINAL BILLED AMOUNT', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF9CA3AF), letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      Text('₹$totalAmount', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFF1F2937))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bottom Action Button
          if (canComplete)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The customer cannot always show a code — a dead phone
                    // should not stop the salon working.
                    if (isScheduled)
                      TextButton.icon(
                        onPressed: _isProcessing ? null : () => _startSession(scan: false),
                        icon: const Icon(Icons.play_circle_outline, size: 18),
                        label: Text('Start without scanning',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                      ),
                    SizedBox(
                      height: 54,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : isScheduled
                                ? () => _startSession(scan: true)
                                : _openBill,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Icon(isScheduled ? Icons.qr_code_scanner : Icons.receipt_long,
                                color: Colors.white),
                        label: Text(
                          _isProcessing
                              ? 'Processing...'
                              : isScheduled
                                  ? 'Scan QR to start'
                                  : 'Bill & collect payment',
                          style: GoogleFonts.outfit(
                              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isScheduled
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF9C54F2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPill(String label, Color bgColor, Color fgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: GoogleFonts.outfit(color: fgColor, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false, Color valueColor = const Color(0xFF1F2937)}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(color: isBold ? const Color(0xFF1F2937) : const Color(0xFF6B7280), fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: GoogleFonts.outfit(color: valueColor, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}
