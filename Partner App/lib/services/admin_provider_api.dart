import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/admin_provider_models.dart';
import '../models/staff_models.dart';
import 'api_config.dart';

class AdminProviderApi {
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

  static Future<AdminProviderStatus> getStatus(String salonId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/salons/$salonId/admin-provider'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return AdminProviderStatus.fromJson(jsonResponse);
    } else {
      throw Exception('Failed to get admin provider status: ${response.body}');
    }
  }

  static Future<AdminProviderStatus> toggle({
    required String salonId,
    required bool enabled,
    String? specialization,
    List<String>? serviceIds,
    bool? useSalonHours,
    List<StaffWorkingHour>? workingHours,
  }) async {
    final Map<String, dynamic> body = {
      'enabled': enabled,
    };
    if (specialization != null) body['specialization'] = specialization;
    if (serviceIds != null) body['service_ids'] = serviceIds;
    if (useSalonHours != null) body['use_salon_hours'] = useSalonHours;
    if (workingHours != null) {
      body['working_hours'] = workingHours.map((h) => h.toJson()).toList();
    }

    final response = await http.post(
      Uri.parse('$baseUrl/salons/$salonId/admin-provider/toggle'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return AdminProviderStatus.fromJson(jsonResponse);
    }
    if (response.statusCode == 409) {
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['provider_elsewhere'] is Map) {
          throw ProviderElsewhereException(
            ProviderElsewhere.fromJson(Map<String, dynamic>.from(body['provider_elsewhere'])),
          );
        }
      } on FormatException {
        // Fall through to the generic error.
      }
    }
    throw Exception('Failed to update admin provider mode: ${response.body}');
  }
}
