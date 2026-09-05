import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../services/appointment_service.dart'; // Ensure correct path
import '../../appointment_details_screen.dart'; // Fixed relative path

class AppointmentsTab extends StatefulWidget {
  final String salonId;
  const AppointmentsTab({Key? key, required this.salonId}) : super(key: key);

  @override
  State<AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<AppointmentsTab> {
  final PartnerAppointmentService _service = PartnerAppointmentService();
  List<dynamic> _appointments = [];
  bool _isLoading = true;

  String _selectedDate = 'Today';
  String _selectedProvider = 'All Providers';
  String _selectedService = 'All Services';
  String _selectedStatus = 'All Status';
  String _selectedSource = 'All Sources';

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _isLoading = true);
    try {
      // Fetch real data from database
      final data = await _service.getAppointments(widget.salonId);
      setState(() {
        _appointments = data;
        _isLoading = false;
      });
    } catch (e, stack) {
      print('AppointmentsTab error: $e');
      print(stack);
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load appointments')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Light background
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilters(),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9C54F2)))
                : _appointments.isEmpty
                  ? Center(child: Text('No appointments found', style: GoogleFonts.outfit(color: Colors.grey)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _appointments.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final apt = _appointments[index];
                        return _buildDynamicAppointmentCard(apt);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Appointments',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1F2937),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Cancel This Day',
              style: GoogleFonts.outfit(
                color: const Color(0xFFDC2626),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  ['All Dates', 'Today', 'Yesterday', 'Tomorrow', 'Custom Date'],
                  _selectedDate,
                  (v) => setState(() => _selectedDate = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  ['All Providers', 'Rahul Sharma', 'Vikram Singh'],
                  _selectedProvider,
                  (v) => setState(() => _selectedProvider = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  ['All Services', 'Haircut', 'Massage'],
                  _selectedService,
                  (v) => setState(() => _selectedService = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  ['All Status', 'Scheduled', 'In Progress', 'Completed', 'Cancelled', 'No Show'],
                  _selectedStatus,
                  (v) => setState(() => _selectedStatus = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            ['All Sources', 'App', 'Walk-in', 'Phone'],
            _selectedSource,
            (v) => setState(() => _selectedSource = v!),
            isFullWidth: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(List<String> items, String value, ValueChanged<String?> onChanged, {bool isFullWidth = false}) {
    if (!items.contains(value)) value = items.first;

    return Container(
      width: isFullWidth ? double.infinity : null,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black87),
          style: GoogleFonts.outfit(color: const Color(0xFF1F2937), fontSize: 12, fontWeight: FontWeight.w500),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDynamicAppointmentCard(Map<String, dynamic> apt) {
    bool isWalkIn = apt['booking_source'] == 'walk_in';
    String customerName = isWalkIn 
        ? (apt['walk_in_customer_name'] ?? 'Walk-In Customer') 
        : (apt['customer'] != null ? apt['customer']['name'] : 'Unknown Customer');
    
    String customerPhone = isWalkIn 
        ? (apt['walk_in_customer_phone'] ?? '') 
        : (apt['customer'] != null ? apt['customer']['phone'] : '');

    String initials = customerName.isNotEmpty ? customerName[0].toUpperCase() : '?';
    String status = (apt['status'] ?? '').toString().toUpperCase();
    
    // Determine colors based on status
    Color statusColor = const Color(0xFFE0F2FE);
    Color statusTextColor = const Color(0xFF0369A1);
    if (status == 'COMPLETED') {
      statusColor = const Color(0xFFDCFCE7);
      statusTextColor = const Color(0xFF15803D);
    } else if (status == 'CANCELLED' || status == 'NO_SHOW') {
      statusColor = const Color(0xFFFEE2E2);
      statusTextColor = const Color(0xFFDC2626);
    }

    // Determine icon based on source
    IconData sourceIcon = Icons.wifi;
    String sourceName = 'App';
    if (isWalkIn) {
      sourceIcon = Icons.storefront_outlined;
      sourceName = 'Walk-in';
    } else if (apt['booking_source'] == 'phone') {
      sourceIcon = Icons.phone_outlined;
      sourceName = 'Phone';
    }

    String provider = apt['appointed_provider'] != null ? apt['appointed_provider']['name'] : 'Any Staff';
    
    // Parse services
    List services = apt['services'] ?? [];
    String serviceNames = services.map((s) => s['service']?['name'] ?? 'Service').join(', ');
    if (serviceNames.isEmpty) serviceNames = 'General Service';

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => AppointmentDetailsScreen(
            appointment: apt,
            salonId: widget.salonId,
          )
        )).then((_) => _loadAppointments()); // Reload on return
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFF3E8FF),
                  radius: 20,
                  child: Text(
                    initials,
                    style: GoogleFonts.outfit(color: const Color(0xFF9333EA), fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customerName, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1F2937))),
                      if (customerPhone.isNotEmpty)
                        Text(customerPhone, style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(16)),
                  child: Text(status, style: GoogleFonts.outfit(color: statusTextColor, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Provider: ', style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 13)),
                Text(provider, style: GoogleFonts.outfit(color: const Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Text('Time: ', style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 13)),
                Text('${apt['start_time']} - ${apt['end_time']}', style: GoogleFonts.outfit(color: const Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Service: ', style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 13)),
                Expanded(
                  child: Text(
                    serviceNames, 
                    style: GoogleFonts.outfit(color: const Color(0xFF111827), fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFFF3F4F6), height: 1, thickness: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(sourceIcon, size: 16, color: const Color(0xFF9CA3AF)),
                const SizedBox(width: 4),
                Text(sourceName, style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('₹${apt['total_amount']}', style: GoogleFonts.outfit(color: const Color(0xFF9333EA), fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
