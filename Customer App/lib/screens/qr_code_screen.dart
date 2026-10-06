import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';
import '../theme/app_colors.dart';

enum CheckInStatus { activeQR, animating, success, nonActive }

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

class _QrCodeScreenState extends State<QrCodeScreen> with WidgetsBindingObserver {
  final AppointmentService _appointmentService = AppointmentService();

  String? _qrToken;
  DateTime? _expiresAt;
  bool _isLoading = true;
  String _error = '';
  
  Timer? _ticker;
  Timer? _pollTicker;
  
  Map<String, dynamic>? _appointmentData;
  CheckInStatus _checkInStatus = CheckInStatus.activeQR;
  
  // Animation flags
  bool _qrShrinking = false;
  bool _circleForming = false;
  bool _showCheck = false;
  bool _showText = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Drives the countdown; one second is enough to keep it honest.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    
    _initializeState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _pollTicker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_checkInStatus == CheckInStatus.activeQR) {
        _startPolling();
      }
    } else if (state == AppLifecycleState.paused) {
      _pollTicker?.cancel();
    }
  }

  Future<void> _initializeState() async {
    setState(() => _isLoading = true);
    try {
      final response = await _appointmentService.getAppointment(widget.appointmentId);
      final appointment = response['appointment'];
      _appointmentData = appointment;
      final status = appointment['status'];
      
      if (status == 'in_progress') {
        _triggerSuccessState(skipAnimation: true);
        return;
      } else if (status == 'completed' || status == 'cancelled') {
        setState(() {
          _checkInStatus = CheckInStatus.nonActive;
          _isLoading = false;
        });
        return;
      }
      
      // If scheduled, generate QR and start polling
      await _generateQr(isInit: true);
      _startPolling();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _startPolling() {
    _pollTicker?.cancel();
    _pollTicker = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollAppointmentStatus();
    });
  }

  Future<void> _pollAppointmentStatus() async {
    if (!mounted || _checkInStatus != CheckInStatus.activeQR) return;
    try {
      final response = await _appointmentService.getAppointment(widget.appointmentId);
      if (!mounted) return;
      final appointment = response['appointment'];
      _appointmentData = appointment;
      final status = appointment['status'];
      
      if (status == 'in_progress') {
        _triggerSuccessState();
      } else if (status == 'completed' || status == 'cancelled') {
        _ticker?.cancel();
        _pollTicker?.cancel();
        setState(() {
          _checkInStatus = CheckInStatus.nonActive;
        });
      }
    } catch (e) {
      // Silently retry on next tick
    }
  }

  void _triggerSuccessState({bool skipAnimation = false}) {
    _ticker?.cancel();
    _pollTicker?.cancel();
    
    if (skipAnimation) {
       setState(() {
         _checkInStatus = CheckInStatus.success;
         _circleForming = true;
         _showCheck = true;
         _showText = true;
         _isLoading = false;
       });
       _exitWithDelay();
       return;
    }
    
    setState(() {
      _checkInStatus = CheckInStatus.animating;
      _qrShrinking = true;
    });
    
    HapticFeedback.mediumImpact();
    
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _circleForming = true);
    });
    
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _showCheck = true);
      HapticFeedback.heavyImpact();
    });
    
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
         _showText = true;
         _checkInStatus = CheckInStatus.success;
      });
    });
    
    _exitWithDelay();
  }
  
  void _exitWithDelay() {
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) Navigator.pop(context, true); 
    });
  }

  Future<void> _generateQr({bool isInit = false}) async {
    if (!isInit) {
      setState(() {
        _isLoading = true;
        _error = '';
      });
    }

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
          if (_checkInStatus == CheckInStatus.activeQR)
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
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       _buildMainContent(),
                       if (_showText || _checkInStatus == CheckInStatus.success) ...[
                         const SizedBox(height: 32),
                         AnimatedOpacity(
                           opacity: _showText ? 1.0 : 0.0,
                           duration: const Duration(milliseconds: 350),
                           child: Column(
                             children: [
                               Text("You're checked in!", style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                               const SizedBox(height: 8),
                               Text("Your appointment has started.", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16)),
                               const SizedBox(height: 4),
                               if (_appointmentData?['serving_provider_name'] != null || _appointmentData?['booked_provider_name'] != null)
                                 Text('${_appointmentData?['serving_provider_name'] ?? _appointmentData?['booked_provider_name']} is ready for you ✨', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16)),
                             ]
                           )
                         )
                       ]
                    ]
                )
      ),
    );
  }

  Widget _buildMainContent() {
    if (_checkInStatus == CheckInStatus.nonActive) {
      return _buildNonActiveState();
    }
    
    if (_checkInStatus == CheckInStatus.animating || _checkInStatus == CheckInStatus.success) {
      return _buildSuccessAnimation();
    }
    
    return _buildCard();
  }

  Widget _buildNonActiveState() {
    final status = _appointmentData?['status'] ?? 'completed';
    final isCancelled = status == 'cancelled';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isCancelled ? Icons.cancel_outlined : Icons.check_circle_outline, 
               size: 64, 
               color: isCancelled ? AppColors.light.danger : AppColors.light.success),
          const SizedBox(height: 16),
          Text(isCancelled ? 'Appointment Cancelled' : 'Appointment Completed',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.light.textPrimary)),
          const SizedBox(height: 12),
          Text(
            isCancelled ? 'This appointment was cancelled and no longer has an active QR code.' : 'This appointment is already completed.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: AppColors.light.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Go back'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessAnimation() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      margin: EdgeInsets.symmetric(horizontal: _circleForming ? 80 : 32),
      padding: EdgeInsets.symmetric(
          horizontal: _circleForming ? 0 : 32,
          vertical: _circleForming ? 0 : 36),
      height: _circleForming ? 180 : 430, // Approximate height of the original card
      width: _circleForming ? 180 : MediaQuery.of(context).size.width - 64,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: _circleForming ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: _circleForming ? null : BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Center(
        child: _circleForming
            ? AnimatedScale(
                scale: _showCheck ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.elasticOut,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 80, color: AppColors.light.success),
                  ],
                ),
              )
            : AnimatedOpacity(
                opacity: _qrShrinking ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 350),
                child: AnimatedScale(
                  scale: _qrShrinking ? 0.5 : 1.0,
                  duration: const Duration(milliseconds: 350),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Scan at the salon',
                          style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.light.textPrimary)),
                      const SizedBox(height: 8),
                      Text(
                        'Show this to the staff member to start your appointment.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(color: AppColors.light.textSecondary),
                      ),
                      const SizedBox(height: 28),
                      QrImageView(
                        data: _qrToken ?? '',
                        version: QrVersions.auto,
                        size: 220.0,
                        foregroundColor: AppColors.light.textPrimary,
                      ),
                    ],
                  ),
                ),
              ),
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
            Icon(Icons.qr_code_2, size: 56, color: AppColors.light.textTertiary),
            const SizedBox(height: 12),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: AppColors.light.danger, fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _initializeState, child: const Text('Try again')),
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Scan at the salon',
              style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.light.textPrimary)),
          const SizedBox(height: 8),
          Text(
            'Show this to the staff member to start your appointment.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: AppColors.light.textSecondary),
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
                  foregroundColor: AppColors.light.textPrimary,
                ),
              ),
              if (_isExpired)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_off_outlined, size: 40, color: AppColors.light.danger),
                    const SizedBox(height: 8),
                    Text('QR expired',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold, color: AppColors.light.danger)),
                    const SizedBox(height: 4),
                    Text('Generate a new QR to check in.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            color: AppColors.light.textSecondary, fontSize: 13)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _generateQr(isInit: false),
                      child: const Text('Generate New QR'),
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
                Icon(Icons.schedule, size: 16, color: AppColors.light.textTertiary),
                const SizedBox(width: 6),
                Text(
                  'Valid for ${_formatRemaining(remaining)}',
                  style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: remaining.inMinutes < 5
                          ? AppColors.light.warning
                          : AppColors.light.textTertiary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
