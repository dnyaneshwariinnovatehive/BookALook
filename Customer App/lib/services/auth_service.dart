import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Use 10.0.2.2 for Android Emulator, 127.0.0.1 for iOS Simulator
  static const String baseUrl = 'http://10.0.2.2:8000/api/customer/auth';

  /// Sends an OTP to the provided phone number.
  Future<bool> sendOtp(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/send-otp'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print('Send OTP failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Send OTP error: $e');
      return false;
    }
  }

  /// Verifies the OTP. If successful, saves the Sanctum token.
  Future<bool> verifyOtp(String phone, String otp, {String? name, String? gender}) async {
    try {
      final body = {
        'phone': phone,
        'otp': otp,
      };
      
      // Add optional fields if registering
      if (name != null && name.isNotEmpty) body['name'] = name;
      if (gender != null && gender.isNotEmpty) body['gender'] = gender;

      final response = await http.post(
        Uri.parse('$baseUrl/verify-otp'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('access_token')) {
          await _saveToken(data['access_token']);
          return true;
        } else if (data['requires_registration'] == true) {
          // Returning false with a specific flow for UI is better, but this handles basic flow.
          throw Exception('Requires Registration');
        }
      }
      print('Verify OTP failed: ${response.body}');
      return false;
    } catch (e) {
      print('Verify OTP error: $e');
      rethrow;
    }
  }

  /// Logs out by clearing the stored token.
  Future<void> logout() async {
    final token = await getToken();
    if (token != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/logout'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
      } catch (e) {
        print('Logout error: $e');
      }
    }
    await _removeToken();
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  Future<void> _removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }
}
