import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:customer_app/services/http_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// A city the platform trades in.
class ServiceCity {
  final String id;
  final String name;
  final String state;
  final int salonCount;
  final double? latitude;
  final double? longitude;

  const ServiceCity({
    required this.id,
    required this.name,
    required this.state,
    required this.salonCount,
    this.latitude,
    this.longitude,
  });

  /// "Pune, Maharashtra" — the state matters because two Indian cities can
  /// share a name and a customer needs to tell them apart.
  String get label => state.isEmpty ? name : '$name, $state';

  factory ServiceCity.fromJson(Map<String, dynamic> json) => ServiceCity(
        id: json['id'].toString(),
        name: json['name'] ?? '',
        state: json['state'] ?? '',
        salonCount: json['salon_count'] ?? 0,
        latitude: json['latitude'] != null
            ? double.tryParse(json['latitude'].toString())
            : null,
        longitude: json['longitude'] != null
            ? double.tryParse(json['longitude'].toString())
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'state': state,
        'salon_count': salonCount,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };
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

  /// Where the device really was at its last fix. Kept apart from the city
  /// so choosing a city never overwrites it: the old single pair was replaced
  /// by the city centre on every pick, including right after "Use my
  /// location", so distances were measured from the middle of town.
  static const _deviceLatKey = 'device_latitude';
  static const _deviceLngKey = 'device_longitude';

  /// The pre-split keys. They may hold a city centre, so they are not trusted.
  static const _legacyLatKey = 'last_latitude';
  static const _legacyLngKey = 'last_longitude';

  /// Beyond this from the chosen city's centre, the device is somewhere else
  /// and the customer is browsing that city from afar.
  static const double nearCityKm = 60;

  ServiceCity? _city;

  /// True while [_city] is only the server's guess (its busiest market), not
  /// something the customer chose or their position decided.
  bool _cityIsGuess = false;
  bool _loaded = false;
  double? _deviceLat;
  double? _deviceLng;

  ServiceCity? get city => _city;
  bool get hasCity => _city != null;

  /// The point distances are measured from: the device's own fix while it is
  /// in (or near) the chosen city, else the chosen city's centre — someone in
  /// Pune browsing Mumbai wants Mumbai salons ordered from Mumbai, not "150
  /// km" on every card. Null when neither is known; everything still works,
  /// ordered by rating instead.
  double? get latitude => _origin()?.$1;
  double? get longitude => _origin()?.$2;
  bool get hasPosition => _origin() != null;

  /// Whether [latitude]/[longitude] are a real fix rather than a city centre.
  bool get usingDevicePosition {
    final o = _origin();
    return o != null && o.$1 == _deviceLat && o.$2 == _deviceLng;
  }

  (double, double)? _origin() {
    final cityLat = _city?.latitude;
    final cityLng = _city?.longitude;
    final hasDevice = _deviceLat != null && _deviceLng != null;

    if (hasDevice && (cityLat == null || cityLng == null)) {
      return (_deviceLat!, _deviceLng!);
    }
    if (hasDevice && distanceKm(_deviceLat!, _deviceLng!, cityLat!, cityLng!) <= nearCityKm) {
      return (_deviceLat!, _deviceLng!);
    }
    if (cityLat != null && cityLng != null) return (cityLat, cityLng);
    return null;
  }

  /// Great-circle distance in kilometres.
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

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
      _deviceLat = prefs.getDouble(_deviceLatKey);
      _deviceLng = prefs.getDouble(_deviceLngKey);
      await prefs.remove(_legacyLatKey);
      await prefs.remove(_legacyLngKey);

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
    // The city's centre is read from the city itself when it is needed; the
    // device's own fix is left alone.
    _city = city;
    _cityIsGuess = false;
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

    final cities = (jsonDecode(response.body) as List)
        .map((e) => ServiceCity.fromJson(e as Map<String, dynamic>))
        .toList();

    if (cities.isNotEmpty) {
      return cities;
    }

    // Fallback: If no serviceable cities exist, query all active cities from DB
    try {
      final fallbackUri = Uri.parse('$_baseUrl/cities').replace(queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final fallbackResp = await http.get(fallbackUri, headers: {'Accept': 'application/json'});
      if (fallbackResp.statusCode == 200) {
        return (jsonDecode(fallbackResp.body) as List)
            .map((e) => ServiceCity.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    return cities;
  }

  /// Adopt whatever city the directory decided to show.
  ///
  /// A first launch has no stored choice, so the server picks the busiest
  /// market. Recording it here means the header names the city the customer is
  /// actually looking at instead of "Select location".
  void adoptResolvedCity(Map<String, dynamic>? resolved) {
    if (resolved == null || _city != null) return;

    _city = ServiceCity.fromJson({'salon_count': 0, ...resolved});
    // Without a position the server could only pick its busiest market; with
    // one it picked the customer's own. Only the first is worth revisiting.
    _cityIsGuess = !hasPosition;
    notifyListeners();
  }

  // ------------------------------------------------------------- where they are

  /// Ask the device where the customer is.
  ///
  /// Returns null whenever a position cannot be had — services off, permission
  /// refused, or the fix timed out. Every caller treats that as "carry on
  /// without it": location makes the list better, it never gates it, and a
  /// customer who says no must still be able to book.
  Future<Position?> currentPosition({bool ask = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied && ask) {
        permission = await Geolocator.requestPermission();
      }

      // deniedForever means the OS will not ask again; only Settings can undo
      // it, so there is nothing to retry here.
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // Fast-path: Check for cached last known position from the OS (instant <10ms response)
      Position? lastKnown;
      try {
        lastKnown = await Geolocator.getLastKnownPosition();
      } catch (e) {
        debugPrint('Could not get last known position: $e');
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.medium,
            // If cached fix is already known, allow only 3s for a fresher fix; otherwise 5s max
            timeLimit: Duration(seconds: lastKnown != null ? 3 : 5),
          ),
        );
      } catch (e) {
        // If fresh fix timed out indoors/low signal, fall back immediately to cached position
        if (lastKnown != null) {
          position = lastKnown;
        } else {
          debugPrint('Could not get fresh position and no cached position: $e');
          return null;
        }
      }

      await _rememberPosition(position.latitude, position.longitude);

      return position;
    } catch (e) {
      debugPrint('Could not get a position: $e');
      return null;
    }
  }

  Future<void> _rememberPosition(double lat, double lng) async {
    final before = (latitude, longitude);
    final moved = _deviceLat == null ||
        _deviceLng == null ||
        distanceKm(_deviceLat!, _deviceLng!, lat, lng) > 0.3;

    _deviceLat = lat;
    _deviceLng = lng;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_deviceLatKey, lat);
      await prefs.setDouble(_deviceLngKey, lng);
    } catch (e) {
      debugPrint('Could not save the position: $e');
    }

    // A city the server only guessed gives way to the one this position is
    // in: the next directory fetch sends the fix without a city, and the
    // server answers with (and the app adopts) the customer's own market.
    if (_cityIsGuess) {
      _city = null;
      _cityIsGuess = false;
      notifyListeners();
      return;
    }

    // Lists sorted by distance re-sort only for a real move, not GPS jitter.
    if (moved && (latitude, longitude) != before) notifyListeners();
  }

  /// Refresh the device's position without ever prompting.
  ///
  /// The saved fix used to be read once and never renewed, so someone who
  /// moved across town kept seeing distances from where they were last week.
  /// Called at launch and when the app comes back to the foreground; does
  /// nothing unless location access was already granted.
  Future<void> refreshPosition() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (!await hasPermission()) return;
      await currentPosition(ask: false);
    } finally {
      _refreshing = false;
    }
  }

  bool _refreshing = false;

  @visibleForTesting
  void debugSet({ServiceCity? city, double? deviceLat, double? deviceLng, bool cityIsGuess = false}) {
    _city = city;
    _cityIsGuess = cityIsGuess;
    _deviceLat = deviceLat;
    _deviceLng = deviceLng;
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

  // --------------------------------------------------- permissions & lifecycle

  static const _hasPromptedInitialLocationKey = 'has_prompted_initial_location';

  bool _remindedPostLogin = false;
  bool get canShowPostLoginReminder => !_remindedPostLogin;
  void markPostLoginReminded() => _remindedPostLogin = true;

  Future<bool> hasPromptedInitialLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_hasPromptedInitialLocationKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markInitialLocationPrompted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasPromptedInitialLocationKey, true);
    } catch (_) {}
  }

  Future<LocationPermission> checkPermission() async {
    try {
      return await Geolocator.checkPermission();
    } catch (_) {
      return LocationPermission.denied;
    }
  }

  Future<LocationPermission> requestPermission() async {
    try {
      return await Geolocator.requestPermission();
    } catch (_) {
      return LocationPermission.denied;
    }
  }

  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermission() async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.whileInUse ||
          p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}

