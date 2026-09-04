import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';

class QrCodeScreen extends StatefulWidget {
  final String appointmentId;
  const QrCodeScreen({Key? key, required this.appointmentId}) : super(key: key);

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

class _QrCodeScreenState extends State<QrCodeScreen> {
  final AppointmentService _appointmentService = AppointmentService();
  String? _qrToken;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _generateQr();
  }

  Future<void> _generateQr() async {
    try {
      final response = await _appointmentService.generateQr(widget.appointmentId);
      setState(() {
        _qrToken = response['qr_token'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.accentColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _isLoading 
            ? CircularProgressIndicator(color: Colors.white)
            : _error.isNotEmpty 
                ? Container(
                    margin: EdgeInsets.all(20),
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Text(_error, style: GoogleFonts.outfit(color: AppTheme.lightDanger, fontSize: 16)),
                  )
                : Container(
                    margin: EdgeInsets.symmetric(horizontal: 40),
                    padding: EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: Offset(0, 10))
                      ]
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Scan at Salon', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
                        SizedBox(height: 8),
                        Text('Show this QR code to the service provider to start your session.', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: AppTheme.lightTextBody)),
                        SizedBox(height: 32),
                        QrImageView(
                          data: _qrToken ?? '',
                          version: QrVersions.auto,
                          size: 200.0,
                          foregroundColor: AppTheme.lightTextHeading,
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
