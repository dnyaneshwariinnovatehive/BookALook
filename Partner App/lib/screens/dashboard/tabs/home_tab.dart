import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../qr_scanner_screen.dart';

class HomeTab extends StatelessWidget {
  final String salonId;
  const HomeTab({super.key, required this.salonId});

  Future<void> _openScanner(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(salonId: salonId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Home'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const Center(
        child: Text('Home Tab'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openScanner(context),
        backgroundColor: AppTheme.accentColor,
        foregroundColor: Colors.white,
        tooltip: 'Scan customer QR',
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
    );
  }
}
