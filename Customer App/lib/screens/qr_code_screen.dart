import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';

/// The code the salon scans to start the appointment.
///
/// The token expires, so the screen counts down and refreshes itself rather
/// than letting the customer hold up a dead code at the counter.
class QrCodeScreen extends StatefulWidget {
  final String appointmentId;
  const QrCodeScreen({Key? key, required this.appointmentId}) : super(key: key);

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

class _QrCodeScreenState extends State<QrCodeScreen> {
  final AppointmentService _appointmentService = AppointmentService();

  String? _qrToken;
  DateTime? _expiresAt;
  bool _isLoading = true;
  String _error = '';
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _generateQr();
    // Drives the countdown; one second is enough to keep it honest.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _generateQr() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final response = await _appointmentService.generateQr(widget.appointmentId);
      if (!mounted) return;
      setState(() {
        _qrToken = response['qr_token'];
        _expiresAt = DateTime.tryParse('${response['expires_at']}')?.toLocal();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Duration? get _remaining {
    if (_expiresAt == null) return null;
    final left = _expiresAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get _isExpired => _remaining != null && _remaining! == Duration.zero;

  String _formatRemaining(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.accentColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Get a fresh code',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoading ? null : _generateQr,
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : _error.isNotEmpty
                ? _buildError()
                : _buildCard(),
      ),
    );
  }

  Widget _buildError() => Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2, size: 56, color: AppTheme.lightTextLight),
            const SizedBox(height: 12),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: AppTheme.lightDanger, fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _generateQr, child: const Text('Try again')),
          ],
        ),
      );

  Widget _buildCard() {
    final remaining = _remaining;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Scan at the salon',
              style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.lightTextHeading)),
          const SizedBox(height: 8),
          Text(
            'Show this to the staff member to start your appointment.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: AppTheme.lightTextBody),
          ),
          const SizedBox(height: 28),

          Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: _isExpired ? 0.15 : 1,
                child: QrImageView(
                  data: _qrToken ?? '',
                  version: QrVersions.auto,
                  size: 220.0,
                  foregroundColor: AppTheme.lightTextHeading,
                ),
              ),
              if (_isExpired)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_off_outlined, size: 40, color: AppTheme.lightDanger),
                    const SizedBox(height: 8),
                    Text('This code has expired',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold, color: AppTheme.lightDanger)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _generateQr,
                      child: const Text('Show a new code'),
                    ),
                  ],
                ),
            ],
          ),

          if (remaining != null && !_isExpired) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule, size: 16, color: AppTheme.lightTextLight),
                const SizedBox(width: 6),
                Text(
                  'Valid for ${_formatRemaining(remaining)}',
                  style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: remaining.inMinutes < 5
                          ? AppTheme.lightWarning
                          : AppTheme.lightTextLight),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
