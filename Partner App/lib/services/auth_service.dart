import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class AuthService {
  static String get baseUrl => ApiConfig.baseUrl;

  Future<String> sendOtp(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/partner/auth/send-otp'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return 'success';
      }
      return decoded['message'] ?? 'Failed to send OTP';
    } catch (e) {
      return 'Network error: $e';
    }
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/partner/auth/verify-otp'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'phone': phone, 'otp': otp}),
      );

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return decoded; // returns success, status (new_user, existing_user), role, salons, token
      }
      return {'success': false, 'message': decoded['message'] ?? 'Invalid OTP'};
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
