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
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
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
                    SizedBox(
                      height: 110,
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, 0.15),
                        child: const SizedBox(
                          width: 380,
                          height: 220,
                          child: SalonIllustration(),
                        ),
                      ),
                    ),
                    // Soft bottom gradient blend
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white,
                            ],
                          ),
                        ),
                      ),
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
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppTheme.lightTextLight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Share your salon location',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.lightTextHeading,
                          letterSpacing: -0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Help nearby customers discover your salon and get walk-ins.',
                        style: GoogleFonts.outfit(
                          fontSize: 12.5,
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
                        color: const Color(0xFFE3F2FD),
                        iconColor: const Color(0xFF1565C0),
                      ),
                      const SizedBox(height: 6),
                      _buildBenefitRow(
                        icon: Icons.directions_walk,
                        title: 'Get more walk-ins',
                        description: 'Help customers easily find and reach your salon.',
                        color: const Color(0xFFEEE3FD),
                        iconColor: AppTheme.accentColor,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: FilledButton.icon(
                          onPressed: () => _enableLocation(context),
                          icon: const Icon(Icons.my_location, size: 18),
                          label: Text(
                            'Enable location',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accentColor,
                            padding: const EdgeInsets.symmetric(vertical: 0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 36,
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
                            foregroundColor: AppTheme.lightTextBody,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'View location details',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: iconColor),
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
                    fontWeight: FontWeight.w600,
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
