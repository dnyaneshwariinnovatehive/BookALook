import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://10.90.1.35:8000/api';

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

  static Future<Map<String, dynamic>> registerSalon(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/partner/register'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(data),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'message': decoded['message'], 'data': decoded};
      } else {
        return {'success': false, 'message': decoded['message'] ?? 'Unknown error occurred'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}
