import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/deep_link_service.dart';
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

class _LocationPermissionDialogState extends State<_LocationPermissionDialog>
    with WidgetsBindingObserver {
  bool _loading = false;
  String? _statusMessage;
  bool _isPermanentlyDenied = false;
  bool _isServiceDisabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_loading) {
      _checkStatusOnResume();
    }
  }

  Future<void> _checkStatusOnResume() async {
    final serviceEnabled =
        await LocationService.instance.isLocationServiceEnabled();
    final permission = await LocationService.instance.checkPermission();

    if (!mounted) return;

    // Case 1: GPS was disabled, user turned it on in settings
    if (_isServiceDisabled && serviceEnabled) {
      setState(() {
        _isServiceDisabled = false;
        _statusMessage = null;
      });
      _handleEnableLocation();
      return;
    }

    // Case 2: Permission was permanently denied, user enabled it in app settings
    if (_isPermanentlyDenied &&
        (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always)) {
      setState(() {
        _isPermanentlyDenied = false;
        _statusMessage = null;
      });
      _handleEnableLocation();
      return;
    }

    // Case 3: Refresh state if user updated settings without enabling
    if (!serviceEnabled) {
      setState(() {
        _isServiceDisabled = true;
        _statusMessage =
            'Device location is turned off. Please turn on GPS or select your city manually.';
      });
    } else if (permission == LocationPermission.deniedForever) {
      setState(() {
        _isPermanentlyDenied = true;
        _statusMessage =
            'Location permission is disabled in phone settings. You can pick your city manually or allow access in Settings.';
      });
    } else if (_isPermanentlyDenied &&
        permission != LocationPermission.deniedForever) {
      setState(() {
        _isPermanentlyDenied = false;
        _statusMessage = null;
      });
    }
  }

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
              'Device location is turned off. Please turn on GPS or select your city manually.';
        });
        AppHaptics.error();
        return;
      }

      // 2. Check current OS permission
      var permission = await LocationService.instance.checkPermission();

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _isPermanentlyDenied = true;
          _statusMessage =
              'Location permission is disabled in phone settings. You can pick your city manually or allow access in Settings.';
        });
        AppHaptics.lightImpact();
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
        final problem = await LocationService.instance.useCurrentLocation();
        if (!mounted) return;

        if (problem != null) {
          if (LocationService.instance.hasCity) {
            // Nearest market resolved even if out of exact range
            if (mounted) {
              Navigator.of(context).pop(true);
            }
            final ctx = DeepLinkService.navigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text(problem),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 4),
                  backgroundColor: const Color(0xFF1E293B),
                ),
              );
            }
          } else {
            // Failed to resolve coordinates or network error
            if (mounted) {
              Navigator.of(context).pop(false);
            }
            final ctx = DeepLinkService.navigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted) {
                  showCityPicker(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(problem),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              });
            }
          }
        } else {
          // Success!
          Navigator.of(context).pop(true);
        }
      } else if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _isPermanentlyDenied = true;
          _statusMessage =
              'Location permission was denied. You can pick your city manually or enable it in Settings.';
        });
        AppHaptics.lightImpact();
      } else {
        // User tapped deny in OS dialog — smoothly fall back to manual city selection
        AppHaptics.lightImpact();
        if (mounted) {
          Navigator.of(context).pop(false);
          final ctx = DeepLinkService.navigatorKey.currentContext;
          if (ctx != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showCityPicker(ctx);
            });
          }
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

  Future<void> _handleOpenSettings() async {
    AppHaptics.lightImpact();
    await LocationService.instance.openAppSettings();
  }

  Future<void> _handleOpenLocationSettings() async {
    AppHaptics.lightImpact();
    await LocationService.instance.openLocationSettings();
  }

  void _handleSelectManually() {
    AppHaptics.selectionClick();
    Navigator.of(context).pop(false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = DeepLinkService.navigatorKey.currentContext;
      if (ctx != null) {
        showCityPicker(ctx);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? context.colors.border
                      : AppTheme.accentColor.withValues(alpha: 0.10),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentColor.withValues(
                      alpha: isDark ? 0.22 : 0.12,
                    ),
                    blurRadius: 32,
                    spreadRadius: 0,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark ? 0.45 : 0.08,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Illustration Header with Close Button
                    Stack(
                      children: [
                        const SizedBox(
                          height: 115,
                          width: double.infinity,
                          child: SalonIllustration(),
                        ),
                        // Close Button (X)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Semantics(
                            label: 'Close location modal',
                            button: true,
                            child: GestureDetector(
                              onTap: () {
                                AppHaptics.lightImpact();
                                Navigator.of(context).pop(false);
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: context.colors.surface.withValues(alpha: 0.90),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? context.colors.border
                                        : Colors.black.withValues(alpha: 0.06),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Main Content Section
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Heading
                          Text(
                            'Turn on your location',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w700,
                              color: context.colors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),

                          // Supporting Text
                          Text(
                            'Discover salons near you and get personalized recommendations.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Benefit 1: Discover salons near you
                          _buildBenefitRow(
                            icon: Icons.location_on_rounded,
                            iconColor: AppTheme.accentColor,
                            iconBg: const Color(0xFFEDE9FE),
                            title: 'Discover salons near you',
                            description:
                                'Explore salons and available services around your area.',
                            context: context,
                          ),

                          // Benefit 2: Plan your visit easily
                          _buildBenefitRow(
                            icon: Icons.calendar_today_rounded,
                            iconColor: const Color(0xFF0284C7),
                            iconBg: const Color(0xFFE0F2FE),
                            title: 'Plan your visit easily',
                            description:
                                'Get accurate distance, availability and instant booking.',
                            context: context,
                          ),

                          // Inline status / guidance notice if any
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: (_isPermanentlyDenied || _isServiceDisabled)
                                    ? context.colors.warningBg
                                    : context.colors.accentSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    (_isPermanentlyDenied || _isServiceDisabled)
                                        ? Icons.info_outline_rounded
                                        : Icons.check_circle_outline_rounded,
                                    size: 15,
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
                                        fontSize: 11,
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

                          const SizedBox(height: 12),

                          // Primary & Secondary CTAs
                          if (_isPermanentlyDenied) ...[
                            // Primary CTA: Select location manually
                            Semantics(
                              button: true,
                              label: 'Select location manually',
                              child: SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton(
                                  onPressed:
                                      _loading ? null : _handleSelectManually,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accentColor,
                                    foregroundColor: context.colors.onAccent,
                                    elevation: 0,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppTheme.accentGradientStart,
                                          AppTheme.accentGradientEnd,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.accentColor
                                              .withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.location_city_rounded,
                                            size: 18,
                                            color: context.colors.onAccent,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Select location manually',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: context.colors.onAccent,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color: context.colors.onAccent,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Secondary CTA: Open Settings
                            Semantics(
                              button: true,
                              label: 'Open Phone Settings',
                              child: SizedBox(
                                width: double.infinity,
                                height: 38,
                                child: TextButton(
                                  onPressed:
                                      _loading ? null : _handleOpenSettings,
                                  style: TextButton.styleFrom(
                                    backgroundColor: isDark
                                        ? context.colors.surfaceMuted
                                        : context.colors.accentSoft,
                                    foregroundColor: AppTheme.accentColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.settings_outlined, size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'Open Phone Settings',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.accentColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ] else if (_isServiceDisabled) ...[
                            // Primary CTA: Turn on GPS
                            Semantics(
                              button: true,
                              label: 'Turn on GPS',
                              child: SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton(
                                  onPressed: _loading
                                      ? null
                                      : _handleOpenLocationSettings,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accentColor,
                                    foregroundColor: context.colors.onAccent,
                                    elevation: 0,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppTheme.accentGradientStart,
                                          AppTheme.accentGradientEnd,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.accentColor
                                              .withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.gps_fixed_rounded,
                                            size: 18,
                                            color: context.colors.onAccent,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Turn on GPS in Settings',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: context.colors.onAccent,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color: context.colors.onAccent,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Secondary CTA: Select location manually
                            Semantics(
                              button: true,
                              label: 'Select location manually',
                              child: SizedBox(
                                width: double.infinity,
                                height: 38,
                                child: TextButton(
                                  onPressed:
                                      _loading ? null : _handleSelectManually,
                                  style: TextButton.styleFrom(
                                    backgroundColor: isDark
                                        ? context.colors.surfaceMuted
                                        : context.colors.accentSoft,
                                    foregroundColor: AppTheme.accentColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Select location manually',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.accentColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            // Primary CTA: Enable location
                            Semantics(
                              button: true,
                              label: 'Enable location',
                              child: SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton(
                                  onPressed:
                                      _loading ? null : _handleEnableLocation,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accentColor,
                                    foregroundColor: context.colors.onAccent,
                                    elevation: 0,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppTheme.accentGradientStart,
                                          AppTheme.accentGradientEnd,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.accentColor
                                              .withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: _loading
                                          ? SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: context.colors.onAccent,
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.my_location_rounded,
                                                  size: 18,
                                                  color:
                                                      context.colors.onAccent,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Enable location',
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        context.colors.onAccent,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 18,
                                                  color:
                                                      context.colors.onAccent,
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Secondary CTA: Select location manually
                            Semantics(
                              button: true,
                              label: 'Select location manually',
                              child: SizedBox(
                                width: double.infinity,
                                height: 38,
                                child: TextButton(
                                  onPressed:
                                      _loading ? null : _handleSelectManually,
                                  style: TextButton.styleFrom(
                                    backgroundColor: isDark
                                        ? context.colors.surfaceMuted
                                        : const Color(0xFFF4EFFF),
                                    foregroundColor: AppTheme.accentColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: isDark
                                            ? context.colors.border
                                            : AppTheme.accentColor
                                                .withValues(alpha: 0.18),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'Select location manually',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.accentColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),

                          // Informational Footer
                          Text(
                            'You can change this anytime in Settings.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10.5,
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
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? context.colors.surfaceMuted : const Color(0xFFF9F8FD),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isDark
              ? context.colors.border
              : AppTheme.accentColor.withValues(alpha: 0.08),
          width: 0.9,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.textSecondary,
                    height: 1.25,
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
