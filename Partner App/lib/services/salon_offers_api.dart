import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class SalonOffersApi {
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

  /// Fetch offer configuration options (available salon services, policy limits, scopes)
  static Future<Map<String, dynamic>> fetchOptions(String salonId) async {
    final uri = Uri.parse('$baseUrl/salons/$salonId/offers/options');
    final response = await http.get(uri, headers: await _getHeaders());

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return Map<String, dynamic>.from(jsonResponse['data'] ?? {});
    } else {
      final msg = _parseErrorMessage(response.body);
      throw Exception(msg ?? 'Failed to load offer configuration options');
    }
  }

  /// List all offers created by this salon
  static Future<List<Map<String, dynamic>>> listOffers(String salonId, {String? status}) async {
    var url = '$baseUrl/salons/$salonId/offers';
    if (status != null && status.isNotEmpty && status != 'All') {
      url += '?status=${Uri.encodeComponent(status.toLowerCase())}';
    }
    final uri = Uri.parse(url);
    final response = await http.get(uri, headers: await _getHeaders());

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final list = jsonResponse['data'] as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e)).toList();
    } else {
      final msg = _parseErrorMessage(response.body);
      throw Exception(msg ?? 'Failed to load offers');
    }
  }

  /// Get single offer details
  static Future<Map<String, dynamic>> getOffer(String salonId, String offerId) async {
    final uri = Uri.parse('$baseUrl/salons/$salonId/offers/$offerId');
    final response = await http.get(uri, headers: await _getHeaders());

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return Map<String, dynamic>.from(jsonResponse['data'] ?? {});
    } else {
      final msg = _parseErrorMessage(response.body);
      throw Exception(msg ?? 'Failed to load offer details');
    }
  }

  /// Create a new offer for this salon
  static Future<Map<String, dynamic>> createOffer(String salonId, Map<String, dynamic> payload) async {
    final uri = Uri.parse('$baseUrl/salons/$salonId/offers');
    final response = await http.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode(payload),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return Map<String, dynamic>.from(jsonResponse['data'] ?? {});
    } else {
      final msg = _parseErrorMessage(response.body);
      throw Exception(msg ?? 'Failed to create offer');
    }
  }

  /// Update an existing salon offer
  static Future<Map<String, dynamic>> updateOffer(String salonId, String offerId, Map<String, dynamic> payload) async {
    final uri = Uri.parse('$baseUrl/salons/$salonId/offers/$offerId');
    final response = await http.put(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return Map<String, dynamic>.from(jsonResponse['data'] ?? {});
    } else {
      final msg = _parseErrorMessage(response.body);
      throw Exception(msg ?? 'Failed to update offer');
    }
  }

  /// Toggle active state (activate / deactivate)
  static Future<Map<String, dynamic>> toggleActive(String salonId, String offerId, {bool? isActive}) async {
    final uri = Uri.parse('$baseUrl/salons/$salonId/offers/$offerId/toggle-active');
    final response = await http.post(
      uri,
      headers: await _getHeaders(),
      body: isActive != null ? jsonEncode({'is_active': isActive}) : null,
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return Map<String, dynamic>.from(jsonResponse['data'] ?? {});
    } else {
      final msg = _parseErrorMessage(response.body);
      throw Exception(msg ?? 'Failed to update offer status');
    }
  }

  /// Delete an offer
  static Future<void> deleteOffer(String salonId, String offerId) async {
    final uri = Uri.parse('$baseUrl/salons/$salonId/offers/$offerId');
    final response = await http.delete(uri, headers: await _getHeaders());

    if (response.statusCode != 200) {
      final msg = _parseErrorMessage(response.body);
      throw Exception(msg ?? 'Failed to delete offer');
    }
  }

  static String? _parseErrorMessage(String responseBody) {
    try {
      final json = jsonDecode(responseBody);
      if (json is Map) {
        if (json['errors'] is Map) {
          final errors = json['errors'] as Map;
          final firstKey = errors.keys.firstOrNull;
          if (firstKey != null && errors[firstKey] is List && (errors[firstKey] as List).isNotEmpty) {
            return errors[firstKey][0].toString();
          }
        }
        return json['message']?.toString();
      }
    } catch (_) {}
    return null;
  }
}
