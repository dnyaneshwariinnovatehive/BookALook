import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/appointment_service.dart';

class WalkInScreen extends StatefulWidget {
  final String salonId;
  const WalkInScreen({Key? key, required this.salonId}) : super(key: key);

  @override
  State<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends State<WalkInScreen> {
  final PartnerAppointmentService _service = PartnerAppointmentService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isBooking = false;
  
  // Note: In a full implementation, you'd fetch services from the API.
  // We're using a dummy list here for the UI flow.
  List<Map<String, dynamic>> _dummyServices = [
    {'id': '1', 'name': 'Haircut', 'price': 25.0},
    {'id': '2', 'name': 'Beard Trim', 'price': 15.0},
  ];
  List<String> _selectedServices = [];

  Future<void> _startWalkIn() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty || _selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please fill all fields and select a service')));
      return;
    }

    setState(() => _isBooking = true);
    try {
      await _service.walkIn(widget.salonId, _nameController.text, _phoneController.text, _selectedServices);
      setState(() => _isBooking = false);
      Navigator.pop(context); // Go back to dashboard on success
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Walk-In Started!')));
    } catch (e) {
      setState(() => _isBooking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F7FC),
      appBar: AppBar(
        title: Text('New Walk-In', style: GoogleFonts.outfit(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customer Details', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Customer Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            Text('Select Services', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            ..._dummyServices.map((service) {
              final isSelected = _selectedServices.contains(service['id']);
              return CheckboxListTile(
                title: Text(service['name'], style: GoogleFonts.outfit(fontWeight: FontWeight.w500)),
                subtitle: Text('\$${service['price']}'),
                value: isSelected,
                activeColor: Color(0xFF9C54F2),
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedServices.add(service['id']);
                    } else {
                      _selectedServices.remove(service['id']);
                    }
                  });
                },
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              );
            }).toList(),
            SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isBooking ? null : _startWalkIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF9C54F2),
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isBooking
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                    : Text('Start Session', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
