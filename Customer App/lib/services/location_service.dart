import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// A city the platform trades in.
class ServiceCity {
  final String id;
  final String name;
  final String state;
  final int salonCount;

  const ServiceCity({
    required this.id,
    required this.name,
    required this.state,
    required this.salonCount,
  });

  /// "Pune, Maharashtra" — the state matters because two Indian cities can
  /// share a name and a customer needs to tell them apart.
  String get label => state.isEmpty ? name : '$name, $state';

  factory ServiceCity.fromJson(Map<String, dynamic> json) => ServiceCity(
        id: json['id'].toString(),
        name: json['name'] ?? '',
        state: json['state'] ?? '',
        salonCount: json['salon_count'] ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'state': state, 'salon_count': salonCount};
}

/// Which city the customer is shopping in.
///
/// One place owns this, because four screens read it and any of them showing a
/// different city than the header would be worse than showing none. It is held
/// in a [ValueNotifier] so a change on the home screen redraws Explore without
/// either knowing about the other.
///
/// Deliberately survives sign-out: a guest picks a city, browses, then creates
/// an account, and losing their choice at that moment would be the worst
/// possible time to lose it.
class LocationService extends ChangeNotifier {
  LocationService._();

  static final LocationService instance = LocationService._();

  static const _cityKey = 'selected_city';

  static String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  static const _latKey = 'last_latitude';
  static const _lngKey = 'last_longitude';

  ServiceCity? _city;
  bool _loaded = false;
  double? _lat;
  double? _lng;

  ServiceCity? get city => _city;
  bool get hasCity => _city != null;

  /// The last known position, or null when the customer has never shared one.
  /// Used to sort the directory by distance; everything still works without it.
  double? get latitude => _lat;
  double? get longitude => _lng;
  bool get hasPosition => _lat != null && _lng != null;

  /// What the header shows before anything is chosen.
  String get label => _city?.name ?? 'Select location';

  /// Read the stored choice. Safe to call repeatedly; only the first does work.
  Future<void> restore() async {
    if (_loaded) return;
    _loaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cityKey);

      if (raw != null) {
        _city = ServiceCity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }

      // Kept so a returning customer gets distance ordering on the first
      // screen, before any fresh fix has come back.
      _lat = prefs.getDouble(_latKey);
      _lng = prefs.getDouble(_lngKey);

      notifyListeners();
    } catch (e) {
      debugPrint('Could not restore the saved city: $e');
    }
  }

  /// Remember the choice locally, and on the account when there is one.
  ///
  /// The local copy is written first and is what the app reads: a customer
  /// switching city should not wait on the network, and a failed sync must not
  /// leave the screen showing a city they did not pick.
  Future<void> setCity(ServiceCity city) async {
    _city = city;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cityKey, jsonEncode(city.toJson()));
    } catch (e) {
      debugPrint('Could not save the city locally: $e');
    }

    await _syncToProfile(city);
  }

  /// Push the choice to the account so it follows them to a new device.
  Future<void> _syncToProfile(ServiceCity city) async {
    final token = await AuthService.getToken();

    if (token == null) return; // Guest — the local copy is the only copy.

    try {
      await http.put(
        Uri.parse('$_baseUrl/customer/profile/city'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'city_id': city.id}),
      );
    } catch (e) {
      // Not worth interrupting anyone for; the local copy still works and the
      // next change will try again.
      debugPrint('Could not sync the city to the profile: $e');
    }
  }

  /// The cities a customer can actually book in.
  ///
  /// Only serviceable ones: the platform knows hundreds of Indian cities and
  /// trades in a handful, and offering the rest sends people to an empty screen.
  Future<List<ServiceCity>> fetchCities({String? search}) async {
    final uri = Uri.parse('$_baseUrl/cities').replace(queryParameters: {
      'serviceable': '1',
      if (search != null && search.isNotEmpty) 'search': search,
    });

    final response = await http.get(uri, headers: {'Accept': 'application/json'});

    if (response.statusCode != 200) {
      throw Exception('Could not load cities');
    }

    return (jsonDecode(response.body) as List)
        .map((e) => ServiceCity.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Adopt whatever city the directory decided to show.
  ///
  /// A first launch has no stored choice, so the server picks the busiest
  /// market. Recording it here means the header names the city the customer is
  /// actually looking at instead of "Select location".
  void adoptResolvedCity(Map<String, dynamic>? resolved) {
    if (resolved == null || _city != null) return;

    _city = ServiceCity(
      id: resolved['id'].toString(),
      name: resolved['name'] ?? '',
      state: resolved['state'] ?? '',
      salonCount: 0,
    );
    notifyListeners();
  }

  // ------------------------------------------------------------- where they are

  /// Ask the device where the customer is.
  ///
  /// Returns null whenever a position cannot be had — services off, permission
  /// refused, or the fix timed out. Every caller treats that as "carry on
  /// without it": location makes the list better, it never gates it, and a
  /// customer who says no must still be able to book.
  Future<Position?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // deniedForever means the OS will not ask again; only Settings can undo
      // it, so there is nothing to retry here.
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // City resolution and distance ordering do not need metre accuracy,
          // and asking for less keeps the fix quick and cheap on battery.
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );

      await _rememberPosition(position.latitude, position.longitude);

      return position;
    } catch (e) {
      // A timeout is the normal case indoors, not an exception worth surfacing.
      debugPrint('Could not get a position: $e');
      return null;
    }
  }

  Future<void> _rememberPosition(double lat, double lng) async {
    _lat = lat;
    _lng = lng;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_latKey, lat);
      await prefs.setDouble(_lngKey, lng);
    } catch (e) {
      debugPrint('Could not save the position: $e');
    }
  }

  /// Find the customer's market from a fix, and switch to it.
  ///
  /// The server decides which city a coordinate belongs to, using the nearest
  /// open salon rather than a boundary — someone in Thane whose closest salons
  /// are all in Mumbai wants Mumbai, and no administrative line says that.
  ///
  /// @return a message to show, or null when it simply worked.
  Future<String?> useCurrentLocation() async {
    final position = await currentPosition();

    if (position == null) {
      return 'We could not get your location. Pick your city below instead.';
    }

    try {
      final uri = Uri.parse('$_baseUrl/cities/nearest').replace(queryParameters: {
        'lat': position.latitude.toString(),
        'lng': position.longitude.toString(),
      });

      final response =
          await http.get(uri, headers: {'Accept': 'application/json'});

      if (response.statusCode != 200) {
        return 'We could not work out your city. Pick one below instead.';
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final city = ServiceCity.fromJson(body['city'] as Map<String, dynamic>);

      await setCity(city);

      // Honest about the edge case rather than pretending the nearest market
      // is local: it may be hundreds of kilometres away.
      if (body['in_range'] != true) {
        return 'We are not in your area yet. Showing ${city.name} for now.';
      }

      return null;
    } catch (e) {
      debugPrint('Could not resolve the nearest city: $e');
      return 'We could not work out your city. Pick one below instead.';
    }
  }
}
