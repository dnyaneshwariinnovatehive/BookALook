import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_colors.dart';
import '../widgets/initials_avatar.dart';

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

class _QrCodeScreenState extends State<QrCodeScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  final AppointmentService _appointmentService = AppointmentService();

  String? _qrToken;
  DateTime? _expiresAt;
  bool _isLoading = true;
  String _error = '';
  
  Timer? _ticker;
  Timer? _pollTicker;
  
  Map<String, dynamic>? _appointmentData;
  CheckInStatus _checkInStatus = CheckInStatus.activeQR;
  
  // Animation controllers
  late AnimationController _cutController;
  late Animation<Offset> _scissorPosition;
  late Animation<double> _scissorAngle;
  late Animation<double> _qrSplit;
  late Animation<double> _qrFallY;
  late Animation<double> _qrRotationTop;
  late Animation<double> _qrRotationBottom;
  late Animation<double> _qrOpacity;
  late Animation<double> _particlesProgress;
  late Animation<double> _particlesOpacity;
  
  late Animation<double> _successCircleScale;
  late Animation<double> _successCheckmarkProgress;
  late Animation<double> _successTitleOpacity;
  late Animation<double> _successTitleSlide;
  late Animation<double> _successSubtitleOpacity;
  late Animation<double> _providerInfoOpacity;
  late Animation<double> _providerInfoSlide;
  
  final List<Particle> _topRightParticles = [];
  final List<Particle> _bottomLeftParticles = [];

  @override
  void initState() {
    super.initState();
    PushNotificationService.suppressedAppointmentStartedId = widget.appointmentId;
    WidgetsBinding.instance.addObserver(this);
    
    _cutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    
    _scissorPosition = Tween<Offset>(
      begin: const Offset(-180, -180),
      end: const Offset(180, 180),
    ).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.05, 0.25, curve: Curves.easeInOutCubic),
    ));
    
    _scissorAngle = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.6).chain(CurveTween(curve: Curves.easeOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.6, end: 0.0).chain(CurveTween(curve: Curves.easeInCubic)), weight: 15),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 35),
    ]).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.05, 0.25),
    ));
    
    _qrSplit = Tween<double>(begin: 0.0, end: 12.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.15, 0.25, curve: Curves.easeOutCubic),
    ));
    
    _qrFallY = Tween<double>(begin: 0.0, end: 350.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.18, 0.60, curve: Curves.easeIn),
    ));
    
    _qrRotationTop = Tween<double>(begin: 0.0, end: 0.15).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.18, 0.60, curve: Curves.easeInQuad),
    ));
    
    _qrRotationBottom = Tween<double>(begin: 0.0, end: -0.1).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.18, 0.60, curve: Curves.easeInQuad),
    ));
    
    _qrOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.35, 0.45, curve: Curves.linear),
    ));
    
    _particlesProgress = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.15, 0.60, curve: Curves.easeOutCubic),
    ));
    
    _particlesOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.40, 0.55, curve: Curves.linear),
    ));
    
    _successCircleScale = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.65, 0.75, curve: Curves.easeOutBack),
    ));
    
    _successCheckmarkProgress = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.70, 0.85, curve: Curves.easeInOutCubic),
    ));
    
    _successTitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.75, 0.85, curve: Curves.easeOut),
    ));
    
    _successTitleSlide = Tween<double>(begin: 10.0, end: 0.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.75, 0.85, curve: Curves.easeOutCubic),
    ));
    
    _successSubtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.78, 0.88, curve: Curves.easeOut),
    ));
    
    _providerInfoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.85, 0.95, curve: Curves.easeOut),
    ));
    
    _providerInfoSlide = Tween<double>(begin: 10.0, end: 0.0).animate(CurvedAnimation(
      parent: _cutController,
      curve: const Interval(0.85, 0.95, curve: Curves.easeOutCubic),
    ));

    _generateParticles();

    // Drives the countdown; one second is enough to keep it honest.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    
    _initializeState();
  }

  @override
  void dispose() {
    if (PushNotificationService.suppressedAppointmentStartedId == widget.appointmentId) {
      PushNotificationService.suppressedAppointmentStartedId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _pollTicker?.cancel();
    _cutController.dispose();
    super.dispose();
  }

  void _generateParticles() {
    final rnd = math.Random(42);
    for (int i = 0; i < 40; i++) {
      double x = rnd.nextDouble() * 220;
      double y = rnd.nextDouble() * 220;
      bool isTopRight = x > y;
      
      Color c = rnd.nextDouble() > 0.8 ? AppTheme.accentColor : AppColors.light.textPrimary;
      double size = 4.0 + rnd.nextDouble() * 6.0;
      
      Offset center = isTopRight ? const Offset(146, 73) : const Offset(73, 146);
      Offset dir = Offset(x - center.dx, y - center.dy);
      double dist = math.sqrt(dir.dx * dir.dx + dir.dy * dir.dy);
      if (dist > 0) dir = dir / dist;
      
      Offset velocity = dir * (5.0 + rnd.nextDouble() * 20.0);
      
      Particle p = Particle(
        initialPosition: Offset(x, y),
        velocity: velocity,
        size: size,
        color: c,
        rotationSpeed: (rnd.nextDouble() - 0.5) * 4.0,
      );
      
      if (isTopRight) {
        _topRightParticles.add(p);
      } else {
        _bottomLeftParticles.add(p);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushNotificationService.suppressedAppointmentStartedId = widget.appointmentId;
      if (_checkInStatus == CheckInStatus.activeQR) {
        _startPolling();
      }
    } else if (state == AppLifecycleState.paused) {
      if (PushNotificationService.suppressedAppointmentStartedId == widget.appointmentId) {
        PushNotificationService.suppressedAppointmentStartedId = null;
      }
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
         _isLoading = false;
       });
       _cutController.value = 1.0;
       _exitWithDelay();
       return;
    }
    
    setState(() {
      _checkInStatus = CheckInStatus.animating;
    });
    
    _cutController.forward();
    
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) HapticFeedback.mediumImpact();
    });
    
    _exitWithDelay();
  }
  
  void _exitWithDelay() {
    Future.delayed(const Duration(milliseconds: 5000), () {
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
              onPressed: _isLoading ? null : _initializeState,
            ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : _error.isNotEmpty
                ? _buildError()
                : _buildMainContent(),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_checkInStatus == CheckInStatus.nonActive) {
      return _buildNonActiveState();
    }
    
    if (_checkInStatus == CheckInStatus.animating || _checkInStatus == CheckInStatus.success) {
      return _buildCuttingAnimation();
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

  Widget _buildCuttingAnimation() {
    String providerName = _appointmentData?['provider_name'] ?? _appointmentData?['service_provider']?['name'] ?? 'Your provider';
    String salonName = _appointmentData?['salon']?['name'] ?? '';
    String salonAddress = _appointmentData?['salon']?['address'] ?? '';
    String? providerPhoto = _appointmentData?['provider_photo_url'] ?? _appointmentData?['service_provider']?['profile_image'];

    return AnimatedBuilder(
      animation: _cutController,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10)),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The QR Cut Animation layer (fades out or disappears)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: (1.0 - (_cutController.value * 10)).clamp(0.0, 1.0),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // Bottom-Left QR Half
                        Transform.translate(
                          offset: Offset(-_qrSplit.value, _qrSplit.value + _qrFallY.value),
                          child: Transform.rotate(
                            angle: _qrRotationBottom.value,
                            child: Stack(
                              children: [
                                Opacity(
                                  opacity: _qrOpacity.value,
                                  child: ClipPath(
                                    clipper: DiagonalClipper(isTopRight: false),
                                    child: QrImageView(
                                      data: _qrToken ?? '',
                                      version: QrVersions.auto,
                                      size: 220.0,
                                      foregroundColor: AppColors.light.textPrimary,
                                    ),
                                  ),
                                ),
                                if (_particlesProgress.value > 0)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: QrParticlePainter(
                                        particles: _bottomLeftParticles,
                                        progress: _particlesProgress.value,
                                        opacity: _particlesOpacity.value,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Top-Right QR Half
                        Transform.translate(
                          offset: Offset(_qrSplit.value, -_qrSplit.value + _qrFallY.value),
                          child: Transform.rotate(
                            angle: _qrRotationTop.value,
                            child: Stack(
                              children: [
                                Opacity(
                                  opacity: _qrOpacity.value,
                                  child: ClipPath(
                                    clipper: DiagonalClipper(isTopRight: true),
                                    child: QrImageView(
                                      data: _qrToken ?? '',
                                      version: QrVersions.auto,
                                      size: 220.0,
                                      foregroundColor: AppColors.light.textPrimary,
                                    ),
                                  ),
                                ),
                                if (_particlesProgress.value > 0)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: QrParticlePainter(
                                        particles: _topRightParticles,
                                        progress: _particlesProgress.value,
                                        opacity: _particlesOpacity.value,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        
                        // Scissor overlay
                        if (_cutController.value > 0.0 && _cutController.value < 0.25)
                          Positioned(
                            left: 110 + _scissorPosition.value.dx - 50,
                            top: 110 + _scissorPosition.value.dy - 50,
                            width: 100,
                            height: 100,
                            child: CustomPaint(
                              painter: ScissorPainter(
                                openAngle: _scissorAngle.value,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_remaining != null && !_isExpired) ...[
                    const SizedBox(height: 24),
                    Opacity(
                      opacity: (1.0 - (_cutController.value * 10)).clamp(0.0, 1.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.schedule, size: 16, color: AppColors.light.textTertiary),
                          const SizedBox(width: 6),
                          Text(
                            'Valid for ${_formatRemaining(_remaining!)}',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.light.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              
              // The Success UI layer
              if (_cutController.value > 0.6)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Circle + Checkmark
                    Transform.scale(
                      scale: _successCircleScale.value,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accentColor.withValues(alpha: 0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: CustomPaint(
                          painter: PremiumCheckmarkPainter(
                            progress: _successCheckmarkProgress.value,
                            color: AppTheme.accentColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Opacity(
                      opacity: _successTitleOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, _successTitleSlide.value),
                        child: Text(
                          "You're checked in!",
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.light.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Opacity(
                      opacity: _successSubtitleOpacity.value,
                      child: Text(
                        "Your appointment has started.",
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          color: AppColors.light.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Opacity(
                      opacity: _providerInfoOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, _providerInfoSlide.value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.light.surfaceMuted,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InitialsAvatar(
                                name: providerName,
                                radius: 20,
                                // We don't have imageUrl on InitialsAvatar based on the earlier check
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "$providerName is ready for you ✨",
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.light.textPrimary,
                                      ),
                                    ),
                                    if (salonName.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        salonAddress.isNotEmpty ? "$salonName • $salonAddress" : salonName,
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          color: AppColors.light.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
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
                      onPressed: _initializeState,
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

class DiagonalClipper extends CustomClipper<Path> {
  final bool isTopRight;
  DiagonalClipper({required this.isTopRight});

  @override
  Path getClip(Size size) {
    final path = Path();
    if (isTopRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.close();
    } else {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.close();
    }
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class ScissorPainter extends CustomPainter {
  final double openAngle; 
  final Color color;

  ScissorPainter({required this.openAngle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(math.pi / 4);

    canvas.save();
    canvas.rotate(openAngle); 
    _drawHalfScissor(canvas, paint, isTop: false);
    canvas.restore();

    canvas.save();
    canvas.rotate(-openAngle); 
    _drawHalfScissor(canvas, paint, isTop: true);
    canvas.restore();

    paint.color = Colors.white;
    canvas.drawCircle(Offset.zero, 3, paint);

    canvas.restore();
  }

  void _drawHalfScissor(Canvas canvas, Paint paint, {required bool isTop}) {
    final path = Path();
    final sign = isTop ? -1.0 : 1.0;
    
    path.moveTo(-8, 0);
    path.lineTo(45, 0);
    path.quadraticBezierTo(20, 6 * sign, -8, 4 * sign);
    path.close();
    
    path.moveTo(-8, 0);
    path.lineTo(-18, 4 * sign);
    path.lineTo(-18, 9 * sign);
    path.lineTo(-8, 4 * sign);
    path.close();
    
    canvas.drawPath(path, paint);
    
    final center = Offset(-30, 9 * sign);
    final outerRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 28, height: 18),
      const Radius.circular(9)
    );
    final innerRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 14, height: 8),
      const Radius.circular(4)
    );
    canvas.drawDRRect(outerRRect, innerRRect, paint);
  }

  @override
  bool shouldRepaint(ScissorPainter oldDelegate) => oldDelegate.openAngle != openAngle;
}

class Particle {
  final Offset initialPosition;
  final Offset velocity;
  final double size;
  final Color color;
  final double rotationSpeed;

  Particle({
    required this.initialPosition,
    required this.velocity,
    required this.size,
    required this.color,
    required this.rotationSpeed,
  });
}

class QrParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double progress; 
  final double opacity;

  QrParticlePainter({
    required this.particles,
    required this.progress,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0 || opacity == 0) return;

    final paint = Paint()..style = PaintingStyle.fill;
    
    for (var p in particles) {
      double t = progress;
      double extraGravity = 100.0 * t * t; 
      Offset pos = p.initialPosition + p.velocity * t + Offset(0, extraGravity);
      
      paint.color = p.color.withOpacity(opacity);
      
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.rotationSpeed * t);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(QrParticlePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.opacity != opacity;
  }
}

class PremiumCheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;
  
  PremiumCheckmarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(size.width * 0.28, size.height * 0.52);
    path.lineTo(size.width * 0.44, size.height * 0.68);
    path.lineTo(size.width * 0.72, size.height * 0.35);

    final pathMetrics = path.computeMetrics().first;
    final extractPath = pathMetrics.extractPath(0.0, pathMetrics.length * progress);
    
    canvas.drawPath(extractPath, paint);
  }

  @override
  bool shouldRepaint(PremiumCheckmarkPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
