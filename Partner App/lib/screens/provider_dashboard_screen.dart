import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/appointment_service.dart';
import 'walk_in_screen.dart';
import 'qr_scanner_screen.dart';
import 'provider_appointment_details_screen.dart';

class ProviderDashboardScreen extends StatefulWidget {
  final String salonId;
  const ProviderDashboardScreen({Key? key, required this.salonId}) : super(key: key);

  @override
  State<ProviderDashboardScreen> createState() => _ProviderDashboardScreenState();
}

class _ProviderDashboardScreenState extends State<ProviderDashboardScreen> {
  final PartnerAppointmentService _service = PartnerAppointmentService();
  DateTime _selectedDate = DateTime.now();
  List<dynamic> _appointments = [];
  bool _isLoading = true;
  String _dateFilter = 'Today'; // 'Today', 'Tomorrow', 'Custom'
  String _statusFilter = 'All'; // 'All', 'Scheduled', 'Completed'

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _isLoading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final data = await _service.getAppointments(widget.salonId, date: dateStr);
      setState(() {
        _appointments = data;
        _isLoading = false;
      });
    } catch (e, stack) {
      print('Error fetching appointments: $e');
      print(stack);
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load appointments')));
    }
  }

  void _changeDateFilter(String filter) {
    setState(() {
      _dateFilter = filter;
      if (filter == 'Today') {
        _selectedDate = DateTime.now();
      } else if (filter == 'Tomorrow') {
        _selectedDate = DateTime.now().add(const Duration(days: 1));
      }
    });
    _loadAppointments();
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
      _updateDateFilterBasedOnSelectedDate();
    });
    _loadAppointments();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF9C54F2)),
          ),
          child: child!,
        );
      },
    );
    if (date != null) {
      setState(() {
        _selectedDate = date;
        _updateDateFilterBasedOnSelectedDate();
      });
      _loadAppointments();
    }
  }

  void _updateDateFilterBasedOnSelectedDate() {
    final now = DateTime.now();
    if (_selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day) {
      _dateFilter = 'Today';
    } else if (_selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day + 1) {
      _dateFilter = 'Tomorrow';
    } else {
      _dateFilter = 'Custom';
    }
  }

  String _formatDateHeader() {
    final now = DateTime.now();
    if (_selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day) {
      return 'Today, ${DateFormat('d MMM yyyy').format(_selectedDate)}';
    } else if (_selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day + 1) {
      return 'Tomorrow, ${DateFormat('d MMM yyyy').format(_selectedDate)}';
    }
    return DateFormat('EEEE, d MMM yyyy').format(_selectedDate);
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '';
    try {
      final timeParts = timeStr.split(':');
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, int.parse(timeParts[0]), int.parse(timeParts[1]));
      return DateFormat('hh:mm a').format(dt);
    } catch (e) {
      return timeStr;
    }
  }

  List<dynamic> get _filteredAppointments {
    if (_statusFilter == 'All') return _appointments;
    return _appointments.where((apt) {
      if (_statusFilter == 'Scheduled') {
        return apt['status'] == 'scheduled' || apt['status'] == 'in_progress';
      }
      if (_statusFilter == 'Completed') {
        return apt['status'] == 'completed';
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAppointments;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Light background
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Schedule', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w900, color: const Color(0xFF1F2937))),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF1F2937)),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (context) => QrScannerScreen(salonId: widget.salonId)
                      )).then((_) => _loadAppointments());
                    },
                  )
                ],
              ),
            ),

            // Date Filters Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  _buildDatePill('Today'),
                  const SizedBox(width: 8),
                  _buildDatePill('Tomorrow'),
                  const Spacer(),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _changeDate(-1),
                        child: const Icon(Icons.chevron_left, color: Color(0xFF6B7280)),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Text(_formatDateHeader(), style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1F2937))),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _changeDate(1),
                        child: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
                      ),
                    ],
                  )
                ],
              ),
            ),

            // Status Filters Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFF3F4F6)),
                ),
                child: Row(
                  children: [
                    Expanded(child: _buildStatusFilter('All')),
                    Expanded(child: _buildStatusFilter('Scheduled')),
                    Expanded(child: _buildStatusFilter('Completed')),
                  ],
                ),
              ),
            ),

            // Queue List
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9C54F2)))
                : filtered.isEmpty
                    ? Center(child: Text('No appointments found', style: GoogleFonts.outfit(color: Colors.grey, fontSize: 16)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          return _buildQueueCard(filtered[index]);
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePill(String label) {
    bool isSelected = _dateFilter == label;
    return GestureDetector(
      onTap: () => _changeDateFilter(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF9333EA) : const Color(0xFFF3E8FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: GoogleFonts.outfit(
          color: isSelected ? Colors.white : const Color(0xFF9333EA),
          fontWeight: FontWeight.bold,
          fontSize: 13,
        )),
      ),
    );
  }

  Widget _buildStatusFilter(String label) {
    bool isSelected = _statusFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF9333EA) : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Center(
          child: Text(label, style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : const Color(0xFF6B7280),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          )),
        ),
      ),
    );
  }

  Widget _buildQueueCard(Map<String, dynamic> apt) {
    bool isWalkIn = apt['booking_source'] == 'walk_in';
    String customerName = isWalkIn ? (apt['walk_in_customer_name'] ?? 'Walk-In') : (apt['customer']?['name'] ?? 'Unknown');
    
    List services = apt['services'] ?? [];
    String serviceNames = services.map((s) => s['service']?['name'] ?? 'Service').join(' + ');
    if (serviceNames.isEmpty) serviceNames = 'General Service';
    
    int duration = services.fold(0, (sum, s) => sum + (s['duration_minutes_at_booking'] as int? ?? 0));
    
    String time = _formatTime(apt['start_time']);
    String timeNumber = time.isNotEmpty ? time.split(' ')[0] : '';
    String timeMeridiem = time.length > 2 ? time.substring(time.length - 2) : '';

    String status = (apt['status'] ?? 'scheduled').toString();
    Color statusColor = const Color(0xFF3B82F6); // Default Blue for Scheduled
    Color statusBg = const Color(0xFFEFF6FF);
    String statusLabel = 'Scheduled';

    if (status == 'in_progress') {
      statusColor = const Color(0xFFD97706); // Orange
      statusBg = const Color(0xFFFEF3C7);
      statusLabel = 'In Progress';
    } else if (status == 'completed') {
      statusColor = const Color(0xFF16A34A); // Green
      statusBg = const Color(0xFFDCFCE7);
      statusLabel = 'Completed';
    } else if (status == 'cancelled' || status == 'no_show') {
      statusColor = const Color(0xFFDC2626); // Red
      statusBg = const Color(0xFFFEE2E2);
      statusLabel = status == 'no_show' ? 'No Show' : 'Cancelled';
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => ProviderAppointmentDetailsScreen(appointment: apt)
        )).then((val) {
          if (val == true) _loadAppointments();
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: statusColor, width: 4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time Section
              SizedBox(
                width: 50,
                child: Column(
                  children: [
                    Text(timeNumber, style: GoogleFonts.outfit(color: statusColor, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(timeMeridiem, style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              
              // Details Section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(customerName, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1F2937)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB), size: 20),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(serviceNames, style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF6B7280)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 12),
                    
                    // Tags Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(12)),
                          child: Text(statusLabel, style: GoogleFonts.outfit(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text('${duration}m', style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Text(isWalkIn ? 'Offline' : 'Online', style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 11, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (apt['balance_amount'] != null && apt['balance_amount'] > 0)
                          Text('Due ₹${apt['balance_amount']}', style: GoogleFonts.outfit(color: const Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
