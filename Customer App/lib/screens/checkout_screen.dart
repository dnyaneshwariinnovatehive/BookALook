import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';

class CheckoutScreen extends StatefulWidget {
  final String salonId;
  const CheckoutScreen({Key? key, required this.salonId}) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final AppointmentService _appointmentService = AppointmentService();
  DateTime _selectedDate = DateTime.now();
  String? _selectedTime;
  List<dynamic> _availableSlots = [];
  bool _isLoadingSlots = false;
  bool _isBooking = false;

  @override
  void initState() {
    super.initState();
    _fetchSlots();
  }

  Future<void> _fetchSlots() async {
    setState(() {
      _isLoadingSlots = true;
      _selectedTime = null;
    });
    
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final slots = await _appointmentService.getAvailableSlots(widget.salonId, dateStr);
      setState(() {
        _availableSlots = slots;
        _isLoadingSlots = false;
      });
    } catch (e) {
      setState(() {
        _availableSlots = [];
        _isLoadingSlots = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load time slots')));
    }
  }

  Future<void> _bookAppointment() async {
    if (_selectedTime == null) return;
    
    setState(() => _isBooking = true);
    
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      await _appointmentService.bookAppointment(widget.salonId, dateStr, _selectedTime!);
      
      setState(() => _isBooking = false);
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: AppTheme.lightSuccess, size: 80),
              SizedBox(height: 16),
              Text('Booking Confirmed!', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Your appointment has been successfully booked.', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: AppTheme.lightTextBody)),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back to previous screen
                },
                style: AppTheme.lightTheme.elevatedButtonTheme.style,
                child: Center(child: Text('View My Bookings')),
              )
            ],
          ),
        ),
      );
    } catch (e) {
      setState(() => _isBooking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Select Date & Time')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Date', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
            SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(Duration(days: 30)),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.light(primary: AppTheme.accentColor),
                      ),
                      child: child!,
                    );
                  },
                );
                if (date != null) {
                  setState(() => _selectedDate = date);
                  _fetchSlots();
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: AppTheme.lightSurface,
                  border: Border.all(color: AppTheme.lightBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate), style: GoogleFonts.outfit(fontSize: 16)),
                    Icon(Icons.calendar_today, color: AppTheme.accentColor),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 32),
            
            Text('Available Slots', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
            SizedBox(height: 16),
            
            _isLoadingSlots 
              ? Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
              : _availableSlots.isEmpty 
                  ? Center(child: Text('No slots available for this date.', style: GoogleFonts.outfit(color: AppTheme.lightTextBody)))
                  : Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _availableSlots.map((slot) {
                        final isSelected = _selectedTime == slot['time'];
                        return InkWell(
                          onTap: () {
                            setState(() => _selectedTime = slot['time']);
                          },
                          child: Container(
                            width: (MediaQuery.of(context).size.width - 60) / 3,
                            padding: EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.accentColor : AppTheme.lightSurface,
                              border: Border.all(color: isSelected ? AppTheme.accentColor : AppTheme.lightBorder),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                slot['time'],
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : AppTheme.lightTextHeading,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    )
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: ElevatedButton(
            onPressed: _selectedTime != null && !_isBooking ? _bookAppointment : null,
            style: AppTheme.lightTheme.elevatedButtonTheme.style?.copyWith(
              padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 16)),
            ),
            child: _isBooking 
                ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Confirm & Pay Advance', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}
