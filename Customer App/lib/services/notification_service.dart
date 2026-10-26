import 'dart:convert';
import 'package:customer_app/services/http_client.dart' as http;
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
  Future<Map<String, dynamic>> fetch({String? period}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('auth_token') == null) {
      return {'notifications': [], 'unread_count': 0};
    }

    final response = await http.get(
      Uri.parse('$baseUrl/customer/notifications${period == null ? '' : '?period=$period'}'),
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

  /// Delete one notification. Throws if the server did not confirm it.
  Future<void> delete(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/customer/notifications/$id'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) throw Exception('Could not delete the notification.');
  }

  /// Delete every notification in [period], or all of them. Returns how many.
  Future<int> deleteMany({String? period}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/customer/notifications/delete'),
      headers: await _headers(),
      body: jsonEncode(period == null ? {'all': true} : {'period': period}),
    );
    if (response.statusCode != 200) throw Exception('Could not delete the notifications.');
    return ((jsonDecode(response.body) as Map)['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<void> markAllRead() async {
    await http.post(
      Uri.parse('$baseUrl/customer/notifications/read-all'),
      headers: await _headers(),
    );
  }
}
