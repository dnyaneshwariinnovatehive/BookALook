import 'dart:convert';
import 'package:customer_app/services/http_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ProfileService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  Future<Map<String, dynamic>> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.get(
      Uri.parse('$baseUrl/customer/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load profile');
    }
  }

  Future<Map<String, dynamic>> getNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token == null) return {};

    final response = await http.get(
      Uri.parse('$baseUrl/customer/notifications/preferences'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['preferences'] ?? {};
    }
    return {};
  }

  /// Sends an OTP to [phone], the number the customer wants to move to.
  /// Returns what to show them; throws with the server's reason otherwise.
  Future<String> sendPhoneChangeOtp(String phone) async {
    final body = await _postPhone('$baseUrl/customer/profile/phone/send-otp', {'phone': phone});
    return body['message']?.toString() ?? 'OTP sent.';
  }

  /// Confirms the OTP and moves the account to [phone]. Returns the number
  /// as saved.
  Future<String> confirmPhoneChange(String phone, String otp) async {
    final body = await _postPhone('$baseUrl/customer/profile/phone/verify', {'phone': phone, 'otp': otp});
    return body['user']?['phone']?.toString() ?? phone;
  }

  Future<Map<String, dynamic>> _postPhone(String url, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(data),
    );

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

  Future<void> updateNotificationPreferences(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token == null) return;

    await http.put(
      Uri.parse('$baseUrl/customer/notifications/preferences'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(data),
    );
  }
}
