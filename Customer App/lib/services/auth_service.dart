import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthService {
  static String get baseUrl => '${dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api'}/customer/auth';

  /// Sends an OTP to the provided phone number.
  Future<String> sendOtp(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/send-otp'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      
      if (response.statusCode == 200) {
        return 'success';
      } else {
        return 'HTTP Error ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      print('Send OTP error: $e');
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
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('access_token')) {
          await _saveToken(data['access_token']);
          return true; // Authenticated
        } else if (data['requires_registration'] == true) {
          return 'requires_registration';
        }
      }
      print('Verify OTP failed: ${response.body}');
      return false;
    } catch (e) {
      print('Verify OTP error: $e');
      rethrow;
    }
  }

  /// Complete profile for new user
  Future<bool> completeProfile(String phone, String name, String gender, String? dob, String? address) async {
    try {
      final body = {
        'phone': phone,
        'name': name,
        'gender': gender,
      };
      if (dob != null && dob.isNotEmpty) body['date_of_birth'] = dob;
      if (address != null && address.isNotEmpty) body['address'] = address;

      final response = await http.post(
        Uri.parse('$baseUrl/complete-profile'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('access_token')) {
          await _saveToken(data['access_token']);
          return true;
        }
      }
      print('Complete Profile failed: ${response.body}');
      return false;
    } catch (e) {
      print('Complete Profile error: $e');
      return false;
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
