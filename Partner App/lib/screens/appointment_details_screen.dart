import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'qr_scanner_screen.dart';

class AppointmentDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final String salonId;

  const AppointmentDetailsScreen({
    Key? key,
    required this.appointment,
    required this.salonId,
  }) : super(key: key);

  void _showScanQrBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String selectedStaff = 'Rahul Sharma'; // Placeholder for Staff selection
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start Session', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text('Assign Staff Member:', style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedStaff,
                        isExpanded: true,
                        items: ['Rahul Sharma', 'Vikram Singh', 'Neha Gupta']
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) => setState(() => selectedStaff = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9C54F2), // Accent Color
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                      label: Text('Scan QR & Confirm', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      onPressed: () {
                        Navigator.pop(context);
                        // Open Scanner
                        Navigator.push(context, MaterialPageRoute(
                          builder: (context) => QrScannerScreen(salonId: salonId),
                        ));
                      },
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
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
                      icon: const Icon(Icons.qr_code, color: Colors.white, size: 18),
                      label: Text('Scan QR', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                      onPressed: () => _showScanQrBottomSheet(context),
                    ),
                ],
              ),
            ),
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
