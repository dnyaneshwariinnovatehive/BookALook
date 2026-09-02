import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:8000/api'; // Android Emulator localhost

  static Future<Map<String, dynamic>> registerSalon(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('\$baseUrl/partner/register'),
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
      return {'success': false, 'message': 'Network error: \$e'};
    }
  }
}
