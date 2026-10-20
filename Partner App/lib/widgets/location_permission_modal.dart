import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/salon_location_api.dart';
import '../screens/dashboard/more/salon_location_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'salon_illustration.dart';

class LocationPermissionModal extends StatelessWidget {
  final String salonId;

  const LocationPermissionModal({super.key, required this.salonId});

  static Future<void> checkAndShow(BuildContext context, String salonId) async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        builder: (context) => LocationPermissionModal(salonId: salonId),
      );
    }
  }

  Future<void> _enableLocation(BuildContext context) async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        content: const Text(
          'Location permission is permanently denied. Please enable it in Settings.',
        ),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () => SalonLocationApi.openAppSettings(),
        ),
      ));
      if (context.mounted) Navigator.pop(context);
      return;
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      if (!context.mounted) return;

      // Check if location services are disabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          content: const Text(
            'Permission granted, but Device Location (GPS) is off. Please turn it on.',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => SalonLocationApi.openLocationSettings(),
          ),
        ));
        return;
      }

      // Read position and save to salon
      try {
        final position = await SalonLocationApi.requireDevicePosition();
        final message = await SalonLocationApi.save(
          salonId,
          position.latitude,
          position.longitude,
        );

        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.green.shade700,
          content: Text(message),
        ));
      } catch (e) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          content: Text('Permission granted. ${e.toString().replaceFirst('Exception: ', '')}'),
        ));
      }
    } else {
      if (!context.mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentColor.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top compact illustration header with close button
                Stack(
                  children: [
                    const SizedBox(
                      height: 115,
                      width: double.infinity,
                      child: SalonIllustration(),
                    ),
                    // Close button (X)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Semantics(
                        label: 'Close location reminder',
                        button: true,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.06),
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
                                color: AppTheme.lightTextBody,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Share your salon location',
                        style: GoogleFonts.outfit(
                          fontSize: 18.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.lightTextHeading,
                          letterSpacing: -0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Help nearby customers discover your salon and get walk-ins.',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.lightTextBody,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      _buildBenefitRow(
                        icon: Icons.radar,
                        title: 'Appear in nearby search',
                        description: 'Nearby clients discover your salon faster.',
                        color: const Color(0xFFE0F2FE),
                        iconColor: const Color(0xFF0284C7),
                      ),
                      _buildBenefitRow(
                        icon: Icons.directions_walk_rounded,
                        title: 'Get more walk-ins',
                        description: 'Help customers easily find and reach your salon.',
                        color: const Color(0xFFEDE9FE),
                        iconColor: AppTheme.accentColor,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: Container(
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
                                color: AppTheme.accentColor.withValues(alpha: 0.30),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _enableLocation(context),
                              borderRadius: BorderRadius.circular(14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.my_location, size: 18, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Enable location',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                      color: Colors.white,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 38,
                        child: TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SalonLocationScreen(salonId: salonId),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFFF4EFFF),
                            foregroundColor: AppTheme.accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: AppTheme.accentColor.withValues(alpha: 0.18),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Text(
                            'View location details',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppTheme.accentColor,
                            ),
                          ),
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
    );
  }

  Widget _buildBenefitRow({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required Color iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8FD),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.08),
          width: 0.9,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
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
                    color: AppTheme.lightTextHeading,
                  ),
                ),
                Text(
                  description,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppTheme.lightTextBody,
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
