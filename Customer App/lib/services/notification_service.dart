import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// The in-app notification inbox. WhatsApp mirrors these messages, but this is
/// the channel the app can always rely on.
class NotificationService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  /// Returns `{notifications: [...], unread_count: n}`. Guests have no inbox,
  /// so an unauthenticated read is an empty one rather than an error.
  Future<Map<String, dynamic>> fetch() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('auth_token') == null) {
      return {'notifications': [], 'unread_count': 0};
    }

    final response = await http.get(
      Uri.parse('$baseUrl/customer/notifications'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load notifications');
  }

  Future<void> markRead(String id) async {
    await http.post(
      Uri.parse('$baseUrl/customer/notifications/$id/read'),
      headers: await _headers(),
    );
  }

  Future<void> markAllRead() async {
    await http.post(
      Uri.parse('$baseUrl/customer/notifications/read-all'),
      headers: await _headers(),
    );
  }
}
