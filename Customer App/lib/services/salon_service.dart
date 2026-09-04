import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SalonService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  Future<List<dynamic>> fetchSalons() async {
    // Calling the unprotected superadmin salon directory endpoint
    final response = await http.get(
      Uri.parse('$baseUrl/superadmin/salons'),
      headers: {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data'] ?? [];
    } else {
      throw Exception('Failed to load salons');
    }
  }

  Future<Map<String, dynamic>> fetchSalonDetails(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/superadmin/salons/$id'),
      headers: {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data'];
    } else {
      throw Exception('Failed to load salon details');
    }
  }
}
