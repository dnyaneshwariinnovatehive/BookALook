import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

/// The salon owner's inbox. SuperAdmin's complaint warnings and suspensions
/// land here, alongside renewal reminders.
class PartnerNotificationService {
  static String get baseUrl => '${ApiConfig.baseUrl}/partner';

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Returns `{notifications: [...], unread_count: n}`.
  static Future<Map<String, dynamic>> fetch({int limit = 50}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications?limit=$limit'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load notifications');
  }

  static Future<int> unreadCount() async {
    final data = await fetch();
    return (data['unread_count'] ?? 0) as int;
  }

  static Future<void> markRead(String id) async {
    await http.post(
      Uri.parse('$baseUrl/notifications/$id/read'),
      headers: await _getHeaders(),
    );
  }

  static Future<void> markAllRead() async {
    await http.post(
      Uri.parse('$baseUrl/notifications/read-all'),
      headers: await _getHeaders(),
    );
  }
}