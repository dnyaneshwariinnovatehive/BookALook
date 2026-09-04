import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/appointment_service.dart';
import 'walk_in_screen.dart';
import 'qr_scanner_screen.dart';
// Note: Assuming a similar AppTheme exists in the partner app
// import '../theme/app_theme.dart';

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
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load appointments')));
    }
  }

  Future<void> _completeAppointment(String id) async {
    try {
      final result = await _service.completeAppointment(id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Completed! You earned ${result['coins_earned_this_time']} coins.')
      ));
      _loadAppointments();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F7FC), // AppTheme.lightBg
      appBar: AppBar(
        title: Text('My Schedule', style: GoogleFonts.outfit(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.qr_code_scanner, color: Color(0xFF9C54F2)), // AppTheme.accentColor
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => QrScannerScreen(salonId: widget.salonId)
              )).then((_) => _loadAppointments());
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Color(0xFF9C54F2),
        icon: Icon(Icons.add),
        label: Text('Walk-In'),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => WalkInScreen(salonId: widget.salonId)
          )).then((_) => _loadAppointments());
        },
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('EEEE, MMM d').format(_selectedDate), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600)),
                IconButton(
                  icon: Icon(Icons.calendar_today, color: Color(0xFF9C54F2)),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now().subtract(Duration(days: 30)),
                      lastDate: DateTime.now().add(Duration(days: 30)),
                    );
                    if (date != null) {
                      setState(() => _selectedDate = date);
                      _loadAppointments();
                    }
                  },
                )
              ],
            ),
          ),
          Expanded(
            child: _isLoading 
                ? Center(child: CircularProgressIndicator(color: Color(0xFF9C54F2)))
                : _appointments.isEmpty
                    ? Center(child: Text('No appointments today!', style: GoogleFonts.outfit(color: Colors.grey)))
                    : ListView.separated(
                        padding: EdgeInsets.all(20),
                        itemCount: _appointments.length,
                        separatorBuilder: (context, index) => SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final apt = _appointments[index];
                          return _buildAppointmentCard(apt);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(dynamic apt) {
    bool isWalkIn = apt['booking_source'] == 'walk_in';
    String customerName = isWalkIn ? apt['walk_in_customer_name'] : apt['customer']['name'];
    
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${apt['start_time']} - ${apt['end_time']}', style: GoogleFonts.outfit(fontSize: 14, color: Color(0xFF9C54F2), fontWeight: FontWeight.bold)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                child: Text(apt['status'].toString().toUpperCase(), style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          SizedBox(height: 12),
          Text(customerName, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600)),
          if (isWalkIn)
            Text('Walk-In Customer', style: GoogleFonts.outfit(fontSize: 12, color: Colors.orange)),
          SizedBox(height: 16),
          if (apt['status'] == 'in_progress')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // Navigate to Add Service Screen (Not fully implemented in this stub)
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: Color(0xFF9C54F2)),
                    child: Text('Add Service'),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _completeAppointment(apt['id'].toString()),
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF16A34A)), // Success Green
                    child: Text('Complete'),
                  ),
                ),
              ],
            )
        ],
      ),
    );
  }
}
