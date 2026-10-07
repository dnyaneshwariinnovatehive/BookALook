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
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // If service is totally off, maybe wait for permission first, or just show it anyway.
      // But let's check permission.
    }
    
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      // Show the modal
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.4),
        builder: (context) => LocationPermissionModal(salonId: salonId),
      );
    }
  }

  Future<void> _enableLocation(BuildContext context) async {
    // Check permission
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      // Permanently denied, tell user to go to settings
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 2500),
        content: const Text('Location permission is permanently denied. Please enable it in Settings.'),
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

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      // Granted!
      if (!context.mounted) return;
      Navigator.pop(context);
      
      // Check if location services are disabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: const Text('Location permission granted, but Location Services are turned off. Please turn them on.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => SalonLocationApi.openLocationSettings(),
          ),
        ));
      } else {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 2500),
            content: Text('Location permission granted!'),
         ));
      }
    } else {
      // Still denied
      if (!context.mounted) return;
      Navigator.pop(context); // just dismiss, don't spam
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    _buildIllustration(),
                    const SizedBox(height: 24),
                    Text(
                      'Share your salon location',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.lightTextHeading,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Help customers find your salon easily\nand get more walk-ins.',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        color: AppTheme.lightTextBody,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    _buildBenefitRow(
                      icon: Icons.radar,
                      title: 'Appear in nearby search',
                      description: 'Customers near you can discover your salon.',
                      color: const Color(0xFFE3F2FD),
                      iconColor: const Color(0xFF1565C0),
                    ),
                    const SizedBox(height: 16),
                    _buildBenefitRow(
                      icon: Icons.directions_walk,
                      title: 'Get more walk-ins',
                      description: 'Your location helps nearby customers reach you.',
                      color: const Color(0xFFF3EBFE),
                      iconColor: AppTheme.accentColor,
                    ),
                    const SizedBox(height: 16),
                    _buildBenefitRow(
                      icon: Icons.visibility_outlined,
                      title: 'Better visibility',
                      description: "Improve your salon's reach and business opportunities.",
                      color: const Color(0xFFE8F5E9),
                      iconColor: const Color(0xFF2E7D32),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _enableLocation(context),
                        icon: const Icon(Icons.my_location, size: 20),
                        label: Text(
                          'Enable location',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
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
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Select location manually',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Semantics(
                  label: 'Close location reminder',
                  button: true,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.close_rounded,
                          size: 24,
                          color: AppTheme.lightTextLight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIllustration() {
    return const SalonIllustration();
  }

  Widget _buildBenefitRow({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required Color iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.lightTextHeading,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.lightTextBody,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

