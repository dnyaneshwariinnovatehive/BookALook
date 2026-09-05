import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../services/appointment_service.dart';
import '../../../../services/service_management_api.dart';

class ProviderWalkInTab extends StatefulWidget {
  final Map<String, dynamic> salon;
  final Map<String, dynamic> provider;
  
  const ProviderWalkInTab({
    Key? key,
    required this.salon,
    required this.provider,
  }) : super(key: key);

  @override
  State<ProviderWalkInTab> createState() => _ProviderWalkInTabState();
}

class _ProviderWalkInTabState extends State<ProviderWalkInTab> {
  final PartnerAppointmentService _appointmentService = PartnerAppointmentService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  String _selectedGender = 'Male';
  List<Map<String, dynamic>> _salonServices = [];
  String? _selectedServiceId;
  String? _selectedTime;
  
  bool _isLoadingServices = true;
  bool _isBooking = false;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      final services = await ServiceManagementApi.getSalonServices(widget.salon['id'].toString());
      setState(() {
        _salonServices = services;
        _isLoadingServices = false;
        if (services.isNotEmpty) {
          _selectedServiceId = services.first['id'].toString();
        }
      });
    } catch (e) {
      setState(() => _isLoadingServices = false);
    }
  }

  // Generates simple time slots for UI demonstration
  List<String> _generateTimeSlots() {
    List<String> slots = [];
    DateTime start = DateTime(2023, 1, 1, 9, 0); // 9:00 AM
    DateTime end = DateTime(2023, 1, 1, 18, 0); // 6:00 PM
    while (start.isBefore(end)) {
      slots.add(DateFormat('h:mm a').format(start));
      start = start.add(const Duration(minutes: 30));
    }
    return slots;
  }

  Future<void> _startWalkIn() async {
    if (_nameController.text.isEmpty || _selectedServiceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter name and select a service')));
      return;
    }

    setState(() => _isBooking = true);
    try {
      // Format selected time to Y-m-d H:i:s if a future time is selected
      String? startTimeParam;
      if (_selectedTime != null && _selectedTime != 'Now') {
        try {
          final now = DateTime.now();
          final timeParts = DateFormat('h:mm a').parse(_selectedTime!);
          final dt = DateTime(now.year, now.month, now.day, timeParts.hour, timeParts.minute);
          startTimeParam = DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
        } catch (e) {
          // ignore parsing error, fallback to null (now)
        }
      }

      await _appointmentService.walkIn(
        widget.salon['id'].toString(), 
        _nameController.text, 
        _phoneController.text, 
        [_selectedServiceId!],
        gender: _selectedGender,
        startTime: startTimeParam,
      );
      
      setState(() {
        _isBooking = false;
        _nameController.clear();
        _phoneController.clear();
        _selectedTime = null;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Walk-In successfully created!'), backgroundColor: Colors.green));
    } catch (e) {
      setState(() => _isBooking = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeSlots = ['Now', ..._generateTimeSlots()];
    
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FE),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Add Walk-in Customer', style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF1F2937))),
              ),
              
              // Time Slots (Horizontal Scroll)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: timeSlots.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final time = timeSlots[index];
                    final isSelected = _selectedTime == time || (_selectedTime == null && time == 'Now');
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTime = time),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF9C54F2) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? const Color(0xFF9C54F2) : const Color(0xFFE5E7EB)),
                        ),
                        child: Text(time, style: GoogleFonts.outfit(
                          color: isSelected ? Colors.white : const Color(0xFF6B7280),
                          fontWeight: FontWeight.bold,
                        )),
                      ),
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 24),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customer Details', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1F2937))),
                    const SizedBox(height: 16),
                    
                    // Name Field
                    Text('Customer Name', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF6B7280))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'Enter name',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Phone Field
                    Text('Phone (optional)', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF6B7280))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Enter phone',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Gender Toggle
                    Text('Gender', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF6B7280))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _buildGenderButton('Male')),
                        const SizedBox(width: 12),
                        Expanded(child: _buildGenderButton('Female')),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Service Dropdown
                    Text('Service', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF6B7280))),
                    const SizedBox(height: 6),
                    _isLoadingServices 
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF9C54F2)))
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedServiceId,
                              isExpanded: true,
                              hint: Text('Select service...', style: GoogleFonts.outfit()),
                              items: _salonServices.map((service) {
                                return DropdownMenuItem<String>(
                                  value: service['id'].toString(),
                                  child: Text(service['name'], style: GoogleFonts.outfit(color: const Color(0xFF1F2937))),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() => _selectedServiceId = val);
                              },
                            ),
                          ),
                        ),
                        
                    const SizedBox(height: 40),
                    
                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isBooking ? null : _startWalkIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1F1F29), // Dark button like screenshot
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isBooking
                            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Add Walk-in', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderButton(String label) {
    bool isSelected = _selectedGender == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedGender = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF9C54F2) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: GoogleFonts.outfit(
          color: isSelected ? Colors.white : const Color(0xFF6B7280),
          fontWeight: FontWeight.bold,
          fontSize: 15,
        )),
      ),
    );
  }
}
