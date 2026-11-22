import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Opens turn-by-turn directions to a salon in Google Maps (or whatever maps
/// app the phone hands the link to).
///
/// Uses the salon's pin when it has one; otherwise its address, so a salon
/// that was never pinned can still be found. Shown next to the Call button
/// wherever a collaborator sees a salon assigned to them.
Future<void> openSalonDirections(
  BuildContext context, {
  double? latitude,
  double? longitude,
  String? address,
  String? city,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final place = [address, city].where((p) => p != null && p.trim().isNotEmpty).join(', ');

  final String? destination = (latitude != null && longitude != null)
      ? '$latitude,$longitude'
      : (place.isEmpty ? null : place);

  if (destination == null) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('This salon has no location or address yet.')),
    );
    return;
  }

  final uri = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': destination});
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened) {
    messenger?.showSnackBar(const SnackBar(content: Text('Could not open maps on this phone.')));
  }
}

/// A compact "Directions" button, styled to sit beside the Call button.
class SalonDirectionsButton extends StatelessWidget {
  const SalonDirectionsButton({
    super.key,
    this.latitude,
    this.longitude,
    this.address,
    this.city,
    this.compact = false,
  });

  final double? latitude;
  final double? longitude;
  final String? address;
  final String? city;

  /// Icon only, for tight rows.
  final bool compact;

  /// Reads latitude/longitude/address/city straight off a salon map from the
  /// collaborator API.
  factory SalonDirectionsButton.fromSalon(Map<String, dynamic> salon, {bool compact = false}) {
    double? num_(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return SalonDirectionsButton(
      latitude: num_(salon['latitude']),
      longitude: num_(salon['longitude']),
      address: salon['address']?.toString(),
      city: salon['city'] is Map ? (salon['city']['name']?.toString()) : salon['city']?.toString(),
      compact: compact,
    );
  }

  void _open(BuildContext context) => openSalonDirections(
        context,
        latitude: latitude,
        longitude: longitude,
        address: address,
        city: city,
      );

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'Directions',
        onPressed: () => _open(context),
        icon: const Icon(Icons.directions_outlined, color: AppTheme.accentColor),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _open(context),
      icon: const Icon(Icons.directions_outlined, size: 15),
      label: const Text('Directions'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.accentColor,
        side: BorderSide(color: AppTheme.accentColor.withValues(alpha: 0.5)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
