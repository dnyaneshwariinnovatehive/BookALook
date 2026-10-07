import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import 'city_picker_sheet.dart';
import 'salon_illustration.dart';

/// Shows the BookALook location permission modal with entrance animation.
///
/// Returns [true] if location permission was granted, or [false] / [null] if
/// dismissed / manually selected.
Future<bool?> showLocationPermissionModal(BuildContext context) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Location Permission',
    barrierColor: Colors.black.withValues(alpha: 0.65),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return const _LocationPermissionDialog();
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedValue = Curves.easeOutCubic.transform(animation.value);
      return Transform.scale(
        scale: 0.94 + (0.06 * curvedValue),
        child: Opacity(
          opacity: animation.value,
          child: child,
        ),
      );
    },
  );
}

class _LocationPermissionDialog extends StatefulWidget {
  const _LocationPermissionDialog();

  @override
  State<_LocationPermissionDialog> createState() =>
      _LocationPermissionDialogState();
}

class _LocationPermissionDialogState extends State<_LocationPermissionDialog> {
  bool _loading = false;
  String? _statusMessage;
  bool _isPermanentlyDenied = false;
  bool _isServiceDisabled = false;

  Future<void> _handleEnableLocation() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
      _isPermanentlyDenied = false;
      _isServiceDisabled = false;
    });

    try {
      // 1. Check if device location service is enabled
      final serviceEnabled =
          await LocationService.instance.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _loading = false;
          _isServiceDisabled = true;
          _statusMessage =
              'Device location is turned off. Please enable GPS in device settings.';
        });
        AppHaptics.error();
        await LocationService.instance.openLocationSettings();
        return;
      }

      // 2. Check current OS permission
      var permission = await LocationService.instance.checkPermission();

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _isPermanentlyDenied = true;
          _statusMessage =
              'Location permission is permanently disabled. Please allow location access in App Settings.';
        });
        AppHaptics.error();
        await LocationService.instance.openAppSettings();
        return;
      }

      // 3. Request OS permission if not yet granted
      if (permission == LocationPermission.denied) {
        permission = await LocationService.instance.requestPermission();
      }

      // 4. Handle result
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        AppHaptics.success();
        // Resolve location in background to update nearest city & coordinates
        await LocationService.instance.useCurrentLocation();
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _isPermanentlyDenied = true;
          _statusMessage =
              'Location permission was denied. You can enable it in Settings anytime.';
        });
        AppHaptics.error();
        await LocationService.instance.openAppSettings();
      } else {
        // User tapped deny in OS dialog
        AppHaptics.lightImpact();
        if (mounted) {
          Navigator.of(context).pop(false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusMessage = 'Could not request location permission: $e';
        });
      }
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  void _handleSelectManually() {
    AppHaptics.selectionClick();
    Navigator.of(context).pop(false);
    // Reuse existing manual location flow
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showCityPicker(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: isDark ? context.colors.surface : Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDark
                      ? context.colors.border
                      : AppTheme.accentColor.withValues(alpha: 0.12),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentColor.withValues(
                      alpha: isDark ? 0.25 : 0.14,
                    ),
                    blurRadius: 36,
                    spreadRadius: 0,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark ? 0.5 : 0.10,
                    ),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Illustration Header with Close Button
                    Stack(
                      children: [
                        const SalonIllustration(),
                        // Soft bottom gradient blend
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 36,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  (isDark
                                          ? context.colors.surface
                                          : Colors.white)
                                      .withValues(alpha: 0.0),
                                  isDark
                                      ? context.colors.surface
                                      : Colors.white,
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Close Button (X)
                        Positioned(
                          top: 14,
                          right: 14,
                          child: Semantics(
                            label: 'Close location modal',
                            button: true,
                            child: GestureDetector(
                              onTap: () {
                                AppHaptics.lightImpact();
                                Navigator.of(context).pop(false);
                              },
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.90),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.12),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 19,
                                  color: Color(0xFF4B5563),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Main Content Section
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Heading
                          Text(
                            'Turn on your location',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Supporting Text
                          Text(
                            'Discover salons near you and get a more\npersonalized BookALook experience.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Benefit 1: Discover salons near you
                          _buildBenefitRow(
                            icon: Icons.location_on_rounded,
                            iconColor: const Color(0xFF7C3AED),
                            iconBg: const Color(0xFFEDE9FE),
                            title: 'Discover salons near you',
                            description:
                                'Find salons and services available around your location.',
                            context: context,
                          ),

                          // Benefit 2: Better recommendations
                          _buildBenefitRow(
                            icon: Icons.star_rounded,
                            iconColor: const Color(0xFFEC4899),
                            iconBg: const Color(0xFFFCE7F3),
                            title: 'Better recommendations',
                            description:
                                'See relevant salons, services and availability nearby.',
                            context: context,
                          ),

                          // Benefit 3: Plan your visit easily
                          _buildBenefitRow(
                            icon: Icons.calendar_today_rounded,
                            iconColor: const Color(0xFF3B82F6),
                            iconBg: const Color(0xFFDBEAFE),
                            title: 'Plan your visit easily',
                            description:
                                'Get more accurate location-based salon information.',
                            context: context,
                          ),

                          // Inline status / guidance notice if any
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: (_isPermanentlyDenied || _isServiceDisabled)
                                    ? context.colors.warningBg
                                    : context.colors.accentSoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    (_isPermanentlyDenied || _isServiceDisabled)
                                        ? Icons.info_outline_rounded
                                        : Icons.check_circle_outline_rounded,
                                    size: 16,
                                    color: (_isPermanentlyDenied ||
                                            _isServiceDisabled)
                                        ? context.colors.warning
                                        : AppTheme.accentColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _statusMessage!,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: (_isPermanentlyDenied ||
                                                _isServiceDisabled)
                                            ? context.colors.warning
                                            : AppTheme.accentColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 18),

                          // Primary CTA: Enable location
                          Semantics(
                            button: true,
                            label: 'Enable location',
                            child: SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed:
                                    _loading ? null : _handleEnableLocation,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7C3AED),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF8B5CF6),
                                        Color(0xFF6D28D9),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF7C3AED)
                                            .withValues(alpha: 0.35),
                                        blurRadius: 14,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: _loading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: const [
                                              Icon(
                                                Icons.my_location_rounded,
                                                size: 20,
                                                color: Colors.white,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Enable location',
                                                style: TextStyle(
                                                  fontSize: 15.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                              SizedBox(width: 4),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 20,
                                                color: Colors.white,
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Secondary CTA: Select location manually
                          Semantics(
                            button: true,
                            label: 'Select location manually',
                            child: SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: TextButton(
                                onPressed:
                                    _loading ? null : _handleSelectManually,
                                style: TextButton.styleFrom(
                                  backgroundColor: isDark
                                      ? context.colors.surfaceMuted
                                      : const Color(0xFFF3F0FF),
                                  foregroundColor: const Color(0xFF7C3AED),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Select location manually',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Informational Footer
                          Text(
                            'You can change this anytime in Settings.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: context.colors.textTertiary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String description,
    required BuildContext context,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? context.colors.surfaceMuted : const Color(0xFFF7F6FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? context.colors.border
              : AppTheme.accentColor.withValues(alpha: 0.07),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.colors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
