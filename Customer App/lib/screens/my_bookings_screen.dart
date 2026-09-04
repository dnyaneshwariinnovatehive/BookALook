import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';
import 'qr_code_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    try {
      final data = await _appointmentService.getMyBookings();
      setState(() {
        _upcoming = data['upcoming'];
        _past = data['past'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelAppointment(String id) async {
    try {
      await _appointmentService.cancelAppointment(id);
      _loadBookings();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

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
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_upcoming, isUpcoming: true),
                _buildList(_past, isUpcoming: false),
              ],
            ),
    );
  }

  Widget _buildList(List<dynamic> list, {required bool isUpcoming}) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          isUpcoming ? 'No upcoming appointments.' : 'No past appointments.',
          style: GoogleFonts.outfit(color: AppTheme.lightTextLight, fontSize: 16),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(20),
      itemCount: list.length,
      separatorBuilder: (context, index) => SizedBox(height: 16),
      itemBuilder: (context, index) {
        final item = list[index];
        final aptDate = DateTime.parse(item['appointment_date']);
        
        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.lightBorder),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: Offset(0, 4))
            ]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMM d, yyyy').format(aptDate),
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(item['status']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item['status'].toString().toUpperCase(),
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: _getStatusColor(item['status'])),
                    ),
                  )
                ],
              ),
              SizedBox(height: 12),
              Text(item['salon']['name'], style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.lightTextHeading)),
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: AppTheme.lightTextBody),
                  SizedBox(width: 4),
                  Text('${item['start_time']} - ${item['end_time']}', style: GoogleFonts.outfit(color: AppTheme.lightTextBody)),
                ],
              ),
              SizedBox(height: 16),
              if (isUpcoming && item['status'] == 'scheduled')
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _cancelAppointment(item['id'].toString()),
                        child: Text('Cancel'),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (context) => QrCodeScreen(appointmentId: item['id'].toString())
                          ));
                        },
                        child: Text('View QR'),
                      ),
                    ),
                  ],
                )
            ],
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'scheduled': return AppTheme.lightInfo;
      case 'in_progress': return AppTheme.lightWarning;
      case 'completed': return AppTheme.lightSuccess;
      case 'cancelled': return AppTheme.lightDanger;
      default: return AppTheme.lightTextBody;
    }
  }
}
