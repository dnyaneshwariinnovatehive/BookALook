import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SalonService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  /// The customer-facing directory.
  ///
  /// This used to read the SuperAdmin salon list, which knows nothing about
  /// subscriptions — a salon whose plan had lapsed still looked open. Each row
  /// now carries `is_serviceable`, decided by the same rule the detail page
  /// uses.
  Future<List<dynamic>> fetchSalons({String? search}) async {
    final uri = Uri.parse('$baseUrl/customer/salons').replace(
      queryParameters: (search != null && search.isNotEmpty) ? {'search': search} : null,
    );

    final response = await http.get(uri, headers: {'Accept': 'application/json'});

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['salons'] ?? [];
    } else {
      throw Exception('Failed to load salons');
    }
  }

  /// Full customer-facing salon profile: photos, hours, categories, services,
  /// combo packages, team and ratings, plus whether it can be booked at all.
  Future<Map<String, dynamic>> fetchSalonDetails(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/customer/salons/$id'),
      headers: {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['salon'];
    } else if (response.statusCode == 404) {
      throw Exception('Salon not found');
    } else {
      throw Exception('Failed to load salon details');
    }
  }
}
