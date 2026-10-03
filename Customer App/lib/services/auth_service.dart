import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'push_notification_service.dart';
import 'http_client.dart' as http;

class AuthService {
  static String get baseUrl => '${dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api'}/customer/auth';

  /// Whether a session-expiry redirect is already under way.
  ///
  /// An expired token makes every in-flight request fail with 401 at the same
  /// moment, and each of them would otherwise push the login screen again.
  static bool _redirectInFlight = false;

  /// Claims the right to send the customer to the login screen.
  ///
  /// Returns `true` for the first caller of an expiry burst and `false` for
  /// every other, so only one navigation happens.
  static bool beginSessionExpiryRedirect() {
    if (_redirectInFlight) return false;
    _redirectInFlight = true;
    return true;
  }

  /// Releases the claim when no navigation could be performed, leaving the app
  /// free to redirect on a later 401.
  static void cancelSessionExpiryRedirect() {
    _redirectInFlight = false;
  }

  /// Clears the claim once a new token is stored, so a genuine expiry later in
  /// the session still redirects the customer.
  static void markSessionAuthenticated() {
    _redirectInFlight = false;
  }

  /// Sends an OTP to the provided phone number.
  Future<String> sendOtp(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/send-otp'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'phone': phone}),
        redirectOn401: false,
      );
      
      if (response.statusCode == 200) {
        return 'success';
      } else {
        return 'HTTP Error ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      debugPrint('Send OTP error: $e');
      return 'Network Exception: $e';
    }
  }

  /// Verifies the OTP. If successful, saves the Sanctum token.
  Future<dynamic> verifyOtp(String phone, String otp) async {
    try {
      final body = {
        'phone': phone,
        'otp': otp,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/verify-otp'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(body),
        redirectOn401: false,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('access_token')) {
          await _saveToken(data['access_token']);
          PushNotificationService().registerDevice();
          return true; // Authenticated
        } else if (data['requires_registration'] == true) {
          return 'requires_registration';
        }
      }
      debugPrint('Verify OTP failed: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Verify OTP error: $e');
      rethrow;
    }
  }

  /// Complete profile for new user
  Future<bool> completeProfile(
    String phone,
    String name,
    String gender,
    String? dob,
    String? address, {
    String? cityId,
    String? subAreaId,
  }) async {
    try {
      final body = {
        'phone': phone,
        'name': name,
        'gender': gender,
      };
      if (dob != null && dob.isNotEmpty) body['date_of_birth'] = dob;
      if (address != null && address.isNotEmpty) body['address'] = address;

      // What they picked on the form wins. Falling back to the city they were
      // already browsing means signing up does not throw away a choice they
      // made as a guest.
      final city = cityId ?? LocationService.instance.city?.id;
      if (city != null && city.isNotEmpty) body['city_id'] = city;
      if (subAreaId != null && subAreaId.isNotEmpty) body['sub_area_id'] = subAreaId;

      final response = await http.post(
        Uri.parse('$baseUrl/complete-profile'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(body),
        redirectOn401: false,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('access_token')) {
          await _saveToken(data['access_token']);
          PushNotificationService().registerDevice();
          return true;
        }
      }
      debugPrint('Complete Profile failed: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Complete Profile error: $e');
      return false;
    }
  }

  /// Update customer profile
  Future<bool> updateProfile(Map<String, dynamic> data) async {
    final token = await getToken();
    if (token == null) return false;
    try {
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';
      final response = await http.put(
        Uri.parse('$apiBaseUrl/customer/profile/update'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        return true;
      }
      debugPrint('Update Profile failed: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Update Profile error: $e');
      return false;
    }
  }

  /// Logs out by clearing the stored token.
  Future<void> logout() async {
    final token = await getToken();
    if (token != null) {
      try {
        await PushNotificationService().unregisterDevice();
        await http.post(
          Uri.parse('$baseUrl/logout'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          redirectOn401: false,
        );
      } catch (e) {
        debugPrint('Logout error: $e');
      }
    }
    await _removeToken();
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    markSessionAuthenticated();
  }

  Future<void> _removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  /// Deletes the customer account securely.
  Future<bool> deleteAccount() async {
    final token = await getToken();
    if (token == null) return false;
    
    try {
      final apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';
      final response = await http.delete(
        Uri.parse('$apiBaseUrl/customer/account'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      if (response.statusCode == 200) {
        await PushNotificationService().unregisterDevice();
        await _removeToken();
        return true;
      }
      debugPrint('Delete Account failed: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Delete Account error: $e');
      return false;
    }
  }
}
