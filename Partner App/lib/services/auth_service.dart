import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/phone_screen.dart';
import 'auth_session.dart';
import 'push_notification_service.dart';
import 'api_config.dart';

class AuthService {
  /// [client] is for tests. Null uses the package-level http functions, which
  /// is what every call did before it existed.
  AuthService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static String get baseUrl => ApiConfig.baseUrl;

  /// Long enough for a slow mobile connection, short enough that a dead one
  /// ends in a message the screen can show instead of a spinner forever.
  static const Duration requestTimeout = Duration(seconds: 20);

  Future<http.Response> _post(String path, Map<String, String> body) {
    final url = Uri.parse('$baseUrl$path');
    const headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};
    final encoded = jsonEncode(body);
    final client = _client;
    final request = client != null
        ? client.post(url, headers: headers, body: encoded)
        : http.post(url, headers: headers, body: encoded);
    return request.timeout(requestTimeout);
  }

  /// 'success', or a message explaining why the code was not sent.
  Future<String> sendOtp(String phone) async {
    try {
      final response = await _post('/partner/auth/send-otp', {'phone': phone});

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
      final response = await _post('/partner/auth/verify-otp', {'phone': phone, 'otp': otp});

      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return decoded; // returns success, status (new_user, existing_user), role, salons, token
      }
      return {'success': false, 'message': decoded['message'] ?? 'Invalid OTP'};
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final stateStr = prefs.getString(AuthSession.stateKey);
    if (stateStr == null) return null;
    return jsonDecode(stateStr);
  }

  Future<void> logout(BuildContext context) async {
    await PushNotificationService().unregisterDevice();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const PhoneScreen()),
      (route) => false,
    );
  }
}
