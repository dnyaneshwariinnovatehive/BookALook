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
  /// [period] narrows to `today`, `yesterday`, `week` or `month`.
  static Future<Map<String, dynamic>> fetch({int limit = 50, String? period}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications?limit=$limit${period == null ? '' : '&period=$period'}'),
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

  /// Delete one notification. Throws if the server did not confirm it.
  static Future<void> delete(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/notifications/$id'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) throw Exception('Could not delete the notification.');
  }

  /// Delete every notification in [period], or all of them. Returns how many.
  static Future<int> deleteMany({String? period}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/delete'),
      headers: await _getHeaders(),
      body: jsonEncode(period == null ? {'all': true} : {'period': period}),
    );
    if (response.statusCode != 200) throw Exception('Could not delete the notifications.');
    return ((jsonDecode(response.body) as Map)['deleted'] as num?)?.toInt() ?? 0;
  }

  static Future<void> markAllRead() async {
    await http.post(
      Uri.parse('$baseUrl/notifications/read-all'),
      headers: await _getHeaders(),
    );
  }

  static Future<Map<String, dynamic>> getPreferences() async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications/preferences'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load notification preferences');
  }

  static Future<bool> updatePreferences(Map<String, dynamic> preferences) async {
    final response = await http.put(
      Uri.parse('$baseUrl/notifications/preferences'),
      headers: await _getHeaders(),
      body: jsonEncode(preferences),
    );

    return response.statusCode == 200;
  }
}