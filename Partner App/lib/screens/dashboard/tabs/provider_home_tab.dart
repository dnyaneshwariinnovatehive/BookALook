import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../services/appointment_service.dart';
import '../../provider_appointment_details_screen.dart';

class ProviderHomeTab extends StatefulWidget {
  final Map<String, dynamic> salon;
  final Map<String, dynamic> provider;
  final Map<String, dynamic> user;

  const ProviderHomeTab({
    Key? key,
    required this.salon,
    required this.provider,
    required this.user,
  }) : super(key: key);

  @override
  State<ProviderHomeTab> createState() => _ProviderHomeTabState();
}

class _ProviderHomeTabState extends State<ProviderHomeTab> {
  final PartnerAppointmentService _service = PartnerAppointmentService();
  List<dynamic> _appointments = [];
  bool _isLoading = true;
  String _availability = 'Available';

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _isLoading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // PartnerAppointmentService automatically fetches for the logged-in provider
      final data = await _service.getAppointments(widget.salon['id'].toString(), date: dateStr);
      setState(() {
        _appointments = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load appointments')));
    }
  }

  String _getShiftTiming() {
    final List workingHours = widget.provider['working_hours'] ?? [];
    // PHP date('w') maps 0=Sunday, 6=Saturday. Dart weekday is 1=Monday, 7=Sunday.
    int currentDartDay = DateTime.now().weekday;
    int phpDay = currentDartDay == 7 ? 0 : currentDartDay;
    
    for (var wh in workingHours) {
      if (wh['day_of_week'] == phpDay) {
        if (wh['is_weekly_off'] == true || wh['is_weekly_off'] == 1) {
          return 'Weekly Off';
        }
        String shiftStart = _formatTime(wh['shift_start']);
        String shiftEnd = _formatTime(wh['shift_end']);
        String breakStr = '';
        if (wh['break_start'] != null && wh['break_end'] != null) {
          breakStr = ' • Break: ${_formatTime(wh['break_start'])} - ${_formatTime(wh['break_end'])}';
        }
        return 'Shift: $shiftStart - $shiftEnd$breakStr';
      }
    }
    return 'Shift: Not Scheduled';
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

  @override
  Widget build(BuildContext context) {
    String name = widget.user['name'] ?? 'Provider';
    String salonName = widget.salon['name'] ?? 'Salon';
    String location = widget.salon['city'] ?? 'Location';
    String initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    // Calculate Stats
    int total = _appointments.length;
    int done = _appointments.where((apt) => apt['status'] == 'completed').length;
    int left = _appointments.where((apt) => apt['status'] == 'scheduled' || apt['status'] == 'in_progress').length;

    // Find Next Appointment
    final nextApt = _appointments.firstWhere(
      (apt) => apt['status'] == 'scheduled' || apt['status'] == 'in_progress', 
      orElse: () => null
    );

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadAppointments,
        color: const Color(0xFF9C54F2),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.blueGrey,
                    child: Text(initials, style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Hi $name', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF1F2937))),
                            const SizedBox(width: 4),
                            const Text('👋', style: TextStyle(fontSize: 20)),
                          ],
                        ),
                        Text('$salonName • $location', style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF6B7280))),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_none, color: Colors.black87),
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Availability Toggle
              Row(
                children: [
                  Expanded(child: _buildAvailabilityButton('Available', Icons.check_circle_outline, _availability == 'Available', const Color(0xFFF3E8FF), const Color(0xFF9333EA))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildAvailabilityButton('On Break', Icons.coffee_outlined, _availability == 'On Break', const Color(0xFFF3E8FF), const Color(0xFF9333EA))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildAvailabilityButton('Busy', Icons.remove_circle_outline, _availability == 'Busy', const Color(0xFFDC2626), Colors.white)),
                ],
              ),
              const SizedBox(height: 24),

              // Next Appointment Card
              if (nextApt != null) _buildNextAppointmentCard(nextApt),
              if (nextApt != null) const SizedBox(height: 24),

              // Statistics
              Row(
                children: [
                  Expanded(child: _buildStatCard('Total', total.toString(), Icons.calendar_today, const Color(0xFFF3E8FF), const Color(0xFF9333EA))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatCard('Done', done.toString(), Icons.check_circle_outline, const Color(0xFFDCFCE7), const Color(0xFF15803D))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatCard('Left', left.toString(), Icons.access_time, const Color(0xFFFEF3C7), const Color(0xFFD97706))),
                ],
              ),
              const SizedBox(height: 16),

              // Shift Info
              Row(
                children: [
                  const Icon(Icons.business_center_outlined, size: 16, color: Color(0xFF9333EA)),
                  const SizedBox(width: 8),
                  Text(_getShiftTiming(), style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF6B7280), fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 24),

              // Today's Queue
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Today's Appointments", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1F2937))),
                  Text('$total appointments', style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF9CA3AF))),
                ],
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(child: CircularProgressIndicator(color: Color(0xFF9C54F2)))
              else if (_appointments.isEmpty)
                Center(child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text('No appointments today!', style: GoogleFonts.outfit(color: Colors.grey, fontSize: 16)),
                ))
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _appointments.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final apt = _appointments[index];
                    return _buildQueueCard(apt);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailabilityButton(String label, IconData icon, bool isSelected, Color bgColor, Color fgColor) {
    return GestureDetector(
      onTap: () => setState(() => _availability = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? fgColor : bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? fgColor : (fgColor == Colors.white ? const Color(0xFFDC2626) : Colors.transparent)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected && fgColor != Colors.white ? Colors.white : fgColor),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.outfit(
              color: isSelected && fgColor != Colors.white ? Colors.white : fgColor,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildNextAppointmentCard(Map<String, dynamic> apt) {
    bool isWalkIn = apt['booking_source'] == 'walk_in';
    String customerName = isWalkIn ? (apt['walk_in_customer_name'] ?? 'Walk-In') : (apt['customer']?['name'] ?? 'Unknown');
    List services = apt['services'] ?? [];
    String serviceNames = services.map((s) => s['service']?['name'] ?? 'Service').join(' + ');
    if (serviceNames.isEmpty) serviceNames = 'General Service';
    
    int duration = services.fold(0, (sum, s) => sum + (s['duration_minutes_at_booking'] as int? ?? 0));
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6), // Purple
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text('NEXT', style: GoogleFonts.outfit(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(customerName, style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(serviceNames, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_formatTime(apt['start_time']), style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('${duration}m • ₹${apt['total_amount']}', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(isWalkIn ? Icons.storefront : Icons.wifi, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(isWalkIn ? 'Walk-in' : 'Online', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color bgColor, Color fgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Icon(icon, color: fgColor, size: 24),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.outfit(color: fgColor, fontSize: 24, fontWeight: FontWeight.w900)),
          Text(label, style: GoogleFonts.outfit(color: fgColor, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildQueueCard(Map<String, dynamic> apt) {
    bool isWalkIn = apt['booking_source'] == 'walk_in';
    String customerName = isWalkIn ? (apt['walk_in_customer_name'] ?? 'Walk-In') : (apt['customer']?['name'] ?? 'Unknown');
    List services = apt['services'] ?? [];
    String serviceNames = services.map((s) => s['service']?['name'] ?? 'Service').join(' + ');
    
    String time = _formatTime(apt['start_time']);
    String timeNumber = time.isNotEmpty ? time.split(' ')[0] : '';
    String timeMeridiem = time.length > 2 ? time.substring(time.length - 2) : '';

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => ProviderAppointmentDetailsScreen(appointment: apt)
        )).then((_) => _loadAppointments());
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: const Border(left: BorderSide(color: Color(0xFF9C54F2), width: 4)), // Accent left border
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(timeNumber, style: GoogleFonts.outfit(color: const Color(0xFF1F2937), fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(timeMeridiem, style: GoogleFonts.outfit(color: const Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold)), // Red meridiem
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customerName, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1F2937))),
                    const SizedBox(height: 4),
                    Text(serviceNames, style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF9CA3AF)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('₹${apt['total_amount']}', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF1F2937))),
            ],
          ),
        ),
      ),
    );
  }
}
