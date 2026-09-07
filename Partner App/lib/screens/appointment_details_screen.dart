import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/check_in_api.dart';
import 'check_in_confirm_sheet.dart';
import 'collect_payment_sheet.dart';
import 'qr_scanner_screen.dart';

class AppointmentDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> appointment;
  final String salonId;

  const AppointmentDetailsScreen({
    Key? key,
    required this.appointment,
    required this.salonId,
  }) : super(key: key);

  @override
  State<AppointmentDetailsScreen> createState() => _AppointmentDetailsScreenState();
}

class _AppointmentDetailsScreenState extends State<AppointmentDetailsScreen> {
  late Map<String, dynamic> appointment = Map<String, dynamic>.from(widget.appointment);
  String get salonId => widget.salonId;
  bool _isBusy = false;

  /// Reloads the row so the buttons reflect what actually happened.
  Future<void> _refresh() async {
    try {
      final target = await CheckInApi.bill(salonId, appointment['id'].toString());
      if (!mounted) return;
      setState(() {
        appointment['status'] = target.appointment.status;
        appointment['serving_provider_id'] = target.appointment.servingProviderId;
        appointment['total_amount'] = target.appointment.totalAmount;
        appointment['balance_amount'] = target.appointment.balanceAmount;
        appointment['payment_mode'] = target.appointment.paymentMode;
      });
    } catch (_) {
      // The screen stays usable on a refresh failure.
    }
  }

  /// Start the session for this specific booking. The admin can scan the
  /// customer's code, or start it by hand when they cannot show one.
  Future<void> _startSession({required bool scan}) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    try {
      if (scan) {
        final started = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => QrScannerScreen(
              salonId: salonId,
              expectedAppointmentId: appointment['id'].toString(),
            ),
          ),
        );
        if (started == true) await _refresh();
      } else {
        final target = await CheckInApi.resolve(
          salonId,
          appointmentId: appointment['id'].toString(),
        );
        if (!mounted) return;
        final started = await CheckInConfirmSheet.show(
          context,
          salonId: salonId,
          target: target,
        );
        if (started) await _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _openBill() async {
    final collected = await CollectPaymentSheet.show(
      context,
      salonId: salonId,
      appointmentId: appointment['id'].toString(),
    );
    if (collected) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bool isWalkIn = appointment['booking_source'] == 'walk_in';
    final String customerName = isWalkIn 
        ? (appointment['walk_in_customer_name'] ?? 'Walk-In') 
        : (appointment['customer']?['name'] ?? 'Unknown');
    final String customerPhone = isWalkIn 
        ? (appointment['walk_in_customer_phone'] ?? '') 
        : (appointment['customer']?['phone'] ?? '');

    final String status = (appointment['status'] ?? '').toString().toUpperCase();
    final bool isScheduled = appointment['status'] == 'scheduled';
    final bool isInProgress = appointment['status'] == 'in_progress';
    final bool isCompleted = appointment['status'] == 'completed';

    // Parse Services
    final List services = appointment['services'] ?? [];
    String serviceNames = services.map((s) => s['service']?['name'] ?? 'Service').join(', ');
    if (serviceNames.isEmpty) serviceNames = 'No specific service';

    final num totalAmount = appointment['total_amount'] ?? 0;
    final num advancePaid = appointment['advance_amount'] ?? 0;
    final num balanceDue = appointment['balance_amount'] ?? totalAmount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text('Appointment Details', style: GoogleFonts.outfit(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and QR Action
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status', style: GoogleFonts.outfit(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
                        child: Text(status, style: GoogleFonts.outfit(color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  if (isScheduled)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 18),
                      label: Text('Scan QR', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                      onPressed: _isBusy ? null : () => _startSession(scan: true),
                    )
                  else if (isInProgress)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9C54F2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.receipt_long, color: Colors.white, size: 18),
                      label: Text('Bill & collect', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                      onPressed: _openBill,
                    ),
                ],
              ),
            ),

            // The customer cannot always show a code — a dead phone should not
            // stop the salon working. Recorded as a manual check-in.
            if (isScheduled) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isBusy ? null : () => _startSession(scan: false),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text('Start without scanning',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
            if (isCompleted) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Settled${appointment['payment_mode'] != null ? ' by ${appointment['payment_mode']}' : ''}.',
                  style: GoogleFonts.outfit(color: const Color(0xFF15803D), fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Customer Info
            _buildSection(
              title: 'Customer Information',
              children: [
                _buildInfoRow('Name', customerName),
                _buildInfoRow('Phone', customerPhone),
                _buildInfoRow('Source', isWalkIn ? 'Walk-in' : 'App Booking'),
              ],
            ),
            const SizedBox(height: 16),

            // Appointment Info
            _buildSection(
              title: 'Appointment Details',
              children: [
                _buildInfoRow('Date', appointment['appointment_date'] ?? ''),
                _buildInfoRow('Time', '${appointment['start_time']} - ${appointment['end_time']}'),
                _buildInfoRow('Assigned Provider', appointment['appointed_provider']?['name'] ?? 'Any Staff'),
                const Divider(height: 24),
                Text('Booked Services', style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(serviceNames, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),

            // Financial Info
            _buildSection(
              title: 'Billing Information',
              children: [
                _buildInfoRow('Total Amount', '₹$totalAmount'),
                _buildInfoRow('Advance Paid', '₹$advancePaid'),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Balance Due', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('₹$balanceDue', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626))),
                  ],
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF9C54F2))),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(color: Colors.grey.shade600, fontSize: 14)),
          Text(value, style: GoogleFonts.outfit(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }
}
