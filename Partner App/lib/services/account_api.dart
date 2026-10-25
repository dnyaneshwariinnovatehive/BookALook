import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'auth_session.dart';

/// The signed-in partner's own account — salon owner, staff member or
/// collaborator alike.
class AccountApi {
  static String get _baseUrl => '${ApiConfig.baseUrl}/partner/me';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Sends an OTP to [phone], the number to move the account to. Returns
  /// what to show; throws with the server's reason otherwise.
  static Future<String> sendPhoneChangeOtp(String phone) async {
    final body = await _post('$_baseUrl/phone/send-otp', {'phone': phone});
    return body['message']?.toString() ?? 'OTP sent.';
  }

  /// Confirms the OTP, moves the account to [phone] and updates the saved
  /// sign-in so every screen shows the new number. Returns it as saved.
  static Future<String> confirmPhoneChange(String phone, String otp) async {
    final body = await _post('$_baseUrl/phone/verify', {'phone': phone, 'otp': otp});
    final saved = body['user']?['phone']?.toString() ?? phone;
    await _rememberPhone(saved);
    return saved;
  }

  /// The number in the saved sign-in, for screens that show it.
  static Future<String?> savedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AuthSession.stateKey);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)['user']?['phone']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _rememberPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AuthSession.stateKey);
    if (raw == null) return;
    try {
      final state = jsonDecode(raw) as Map<String, dynamic>;
      final user = state['user'];
      if (user is Map<String, dynamic>) {
        user['phone'] = phone;
        await prefs.setString(AuthSession.stateKey, jsonEncode(state));
      }
    } catch (_) {
      // A sign-in we cannot read is refreshed at the next login anyway.
    }
  }

  static Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> data) async {
    final response = await http.post(Uri.parse(url), headers: await _headers(), body: jsonEncode(data));

    final decoded = response.body.isNotEmpty ? jsonDecode(response.body) : <String, dynamic>{};
    final body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode == 200) return body;

    if (response.statusCode == 429) {
      throw Exception('Too many tries. Wait a minute and try again.');
    }
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      throw Exception(first is List && first.isNotEmpty ? first.first.toString() : first.toString());
    }
    throw Exception(body['message']?.toString() ?? 'Something went wrong. Try again.');
  }
}
