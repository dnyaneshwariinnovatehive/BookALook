import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

/// Where the salon sits on the map.
class SalonLocation {
  final double? latitude;
  final double? longitude;

  /// 'owner' when the owner pinned it themselves, 'city_centre' when the
  /// platform placed it at the middle of their city as a stand-in, null when
  /// it has never been placed at all.
  final String? source;
  final String? cityName;

  const SalonLocation({
    this.latitude,
    this.longitude,
    this.source,
    this.cityName,
  });

  bool get isPinned => latitude != null && longitude != null;
  bool get isOwnerPinned => source == 'owner';

  factory SalonLocation.fromJson(Map<String, dynamic> json) => SalonLocation(
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        source: json['location_source'] as String?,
        cityName: (json['city'] as Map<String, dynamic>?)?['name'] as String?,
      );
}

/// The link a salon's printed QR code carries.
class SalonQrCode {
  final String url;
  final String salonName;
  final String salonSlug;
  final String? city;

  const SalonQrCode({
    required this.url,
    required this.salonName,
    required this.salonSlug,
    this.city,
  });

  factory SalonQrCode.fromJson(Map<String, dynamic> json) => SalonQrCode(
        url: json['url'] ?? '',
        salonName: json['salon_name'] ?? '',
        salonSlug: json['salon_slug'] ?? 'salon',
        city: json['city'] as String?,
      );
}

/// Reading and setting the salon's position.
///
/// Customers see the nearest salons first, so this is not decoration — a salon
/// the platform cannot place sorts below every salon it can.
class SalonLocationApi {
  static String get _baseUrl => ApiConfig.baseUrl;

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<SalonLocation> fetch(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/partner/salons/$salonId/location'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception('Could not load the salon location');
    }

    return SalonLocation.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Save the pin. Returns the message to show the owner.
  static Future<String> save(String salonId, double lat, double lng) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/partner/salons/$salonId/location'),
      headers: await _headers(),
      body: jsonEncode({'latitude': lat, 'longitude': lng}),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Could not save the location');
    }

    return body['message'] ?? 'Location saved.';
  }

  /// Read the device's position.
  ///
  /// Null on any refusal or failure — the owner can try again later, and
  /// nothing else in the app depends on this succeeding.
  static Future<Position?> devicePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // The owner is standing in the salon, so it is worth waiting for a
          // good fix here — this is recorded once and used for a long time.
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      debugPrint('Could not get a position: $e');
      return null;
    }
  }

  /// The address this salon's QR poster points at.
  ///
  /// Fetched rather than built on the device, so every poster printed anywhere
  /// carries the same link and SuperAdmin can move the site without
  /// invalidating the ones already on walls.
  static Future<SalonQrCode> fetchQrCode(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/partner/salons/$salonId/qr-code'),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception('Could not load the QR code');
    }

    return SalonQrCode.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
