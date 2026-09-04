import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// NOTE: Requires mobile_scanner package in pubspec.yaml
// import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/appointment_service.dart';

class QrScannerScreen extends StatefulWidget {
  final String salonId;
  const QrScannerScreen({Key? key, required this.salonId}) : super(key: key);

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final PartnerAppointmentService _service = PartnerAppointmentService();
  bool _isProcessing = false;

  Future<void> _processQr(String token) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await _service.verifyQrAndStartSession(widget.salonId, token);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('QR Verified! Session Started.')));
      Navigator.pop(context); // Go back to dashboard
    } catch (e) {
      setState(() => _isProcessing = false);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Invalid QR'),
          content: Text(e.toString()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('OK'))
          ],
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Scan Customer QR', style: GoogleFonts.outfit(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Placeholder for the actual MobileScanner widget
          Container(
            color: Colors.black87,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, size: 100, color: Colors.white54),
                  SizedBox(height: 16),
                  Text('Camera Preview Here', style: GoogleFonts.outfit(color: Colors.white54, fontSize: 18)),
                  SizedBox(height: 40),
                  // Dummy button to simulate a successful scan
                  ElevatedButton(
                    onPressed: () => _processQr('DUMMY_TOKEN_HASH_FOR_TESTING'),
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF9C54F2)),
                    child: Text('Simulate Scan'),
                  )
                ],
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF9C54F2)),
              ),
            )
        ],
      ),
    );
  }
}
