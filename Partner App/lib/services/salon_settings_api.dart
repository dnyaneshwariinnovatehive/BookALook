import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/salon_working_hour.dart';
import 'api_config.dart';

class SalonSettingsApi {
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

  static Future<Map<String, dynamic>> fetchWorkingHours(String salonId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/salons/$salonId/working-hours'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final List<dynamic> data = jsonResponse['working_hours'];
      return {
        'hours': data.map((json) => SalonWorkingHour.fromJson(json)).toList(),
        'is_default': jsonResponse['is_default'] ?? false,
      };
    } else {
      throw Exception('Failed to fetch working hours: ${response.body}');
    }
  }

  static Future<void> updateWorkingHours(String salonId, List<SalonWorkingHour> hours) async {
    final body = {
      'working_hours': hours.map((h) => h.toJson()).toList(),
    };

    final response = await http.put(
      Uri.parse('$baseUrl/salons/$salonId/working-hours'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update working hours: ${response.body}');
    }
  }

  static Future<void> updateSalonProfile({
    required String salonId,
    required String name,
    required String phone,
    required String description,
    String? imagePath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/salons/$salonId'),
    )..headers.addAll(await _getHeaders());

    request.fields['_method'] = 'PUT'; // Common convention for multipart PUT in PHP/Laravel
    request.fields['name'] = name;
    request.fields['phone'] = phone;
    request.fields['description'] = description;

    if (imagePath != null) {
      request.files.add(await http.MultipartFile.fromPath('cover_image', imagePath));
    }

    final response = await request.send();
    if (response.statusCode != 200 && response.statusCode != 201) {
      final bodyStr = await response.stream.bytesToString();
      throw Exception('Failed to update salon profile: $bodyStr');
    }
  }
}
