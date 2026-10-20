import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class ApiService {
  static String get baseUrl => ApiConfig.baseUrl;

  static Future<List<dynamic>> fetchCities() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/cities'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print('Error fetching cities: $e');
      return [];
    }
  }

  static Future<http.Response> post(String path, dynamic body) async {
    final headers = await ApiConfig.headers();

    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    );

    await ApiConfig.handleResponse(response);
    return response;
  }

  static Future<List<dynamic>> getSubscriptionPlans() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/public/subscription-plans'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) return decoded;
        if (decoded is Map) {
          if (decoded['plans'] is List) return decoded['plans'];
          if (decoded['data'] is List) return decoded['data'];
        }
      }
      return [];
    } catch (e) {
      print('Error fetching subscription plans: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> registerSalon(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final photoPaths = (data['photo_paths'] as List?)?.cast<String>() ?? [];

      if (photoPaths.isNotEmpty) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/partner/register'),
        );
        request.headers['Accept'] = 'application/json';
        if (token != null) {
          request.headers['Authorization'] = 'Bearer $token';
        }

        data.forEach((key, value) {
          if (key != 'photo_paths' && value != null) {
            request.fields[key] = value.toString();
          }
        });

        for (final path in photoPaths) {
          final file = File(path);
          if (await file.exists()) {
            final multipartFile = await http.MultipartFile.fromPath('photos[]', path);
            request.files.add(multipartFile);
          }
        }

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);
        final decoded = jsonDecode(response.body);

        if (response.statusCode == 201 || response.statusCode == 200) {
          return {'success': true, 'message': decoded['message'], 'data': decoded};
        } else {
          return {'success': false, 'message': decoded['message'] ?? 'Registration failed', 'errors': decoded['errors']};
        }
      } else {
        final headers = {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        };
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }

        final Map<String, dynamic> cleanData = Map.from(data)..remove('photo_paths');
        final response = await http.post(
          Uri.parse('$baseUrl/partner/register'),
          headers: headers,
          body: jsonEncode(cleanData),
        );

        final decoded = jsonDecode(response.body);

        if (response.statusCode == 201 || response.statusCode == 200) {
          return {'success': true, 'message': decoded['message'], 'data': decoded};
        } else {
          return {'success': false, 'message': decoded['message'] ?? 'Registration failed', 'errors': decoded['errors']};
        }
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
