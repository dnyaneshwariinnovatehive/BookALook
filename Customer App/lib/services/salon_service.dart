import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_service.dart';

class SalonService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  /// The customer-facing directory.
  ///
  /// This used to read the SuperAdmin salon list, which knows nothing about
  /// subscriptions — a salon whose plan had lapsed still looked open. Each row
  /// now carries `is_serviceable`, decided by the same rule the detail page
  /// uses.
  Future<Map<String, dynamic>> fetchSalons({String? search, String? gender, String? categoryId}) async {
    final Map<String, dynamic> queryParams = {};
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (gender != null && gender.isNotEmpty && gender != 'All') queryParams['gender'] = gender;
    if (categoryId != null && categoryId.isNotEmpty) queryParams['category_id'] = categoryId;
    
    final uri = Uri.parse('$baseUrl/customer/salons').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    final token = await AuthService.getToken();
    final headers = {'Accept': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load salons');
    }
  }

  /// Full customer-facing salon profile: photos, hours, categories, services,
  /// combo packages, team and ratings, plus whether it can be booked at all.
  Future<Map<String, dynamic>> fetchSalonDetails(String salonId) async {
    final uri = Uri.parse('$baseUrl/customer/salons/$salonId');
    
    final token = await AuthService.getToken();
    final headers = {'Accept': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['salon'];
    } else if (response.statusCode == 404) {
      throw Exception('Salon not found');
    } else {
      throw Exception('Failed to load salon details');
    }
  }

  Future<List<dynamic>> fetchFavourites() async {
    final uri = Uri.parse('$baseUrl/customer/favorites');
    
    final token = await AuthService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['favourites'] ?? [];
    } else {
      throw Exception('Failed to load favourites');
    }
  }

  Future<bool> toggleFavourite(String salonId) async {
    final uri = Uri.parse('$baseUrl/customer/salons/$salonId/favorite');
    
    final token = await AuthService.getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final response = await http.post(uri, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['is_favourited'] == true;
    } else {
      throw Exception('Failed to toggle favourite');
    }
  }
}
