import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class PartnerAppointmentService {
  // Must match the rest of the app — see ApiConfig.
  String get baseUrl => ApiConfig.baseUrl;

  /// One booking, in the same shape as a row of [getAppointments]. Returns
  /// null when it is gone or not visible to this user (404/403), so a tapped
  /// notification about a cancelled or reassigned booking degrades gently.
  Future<Map<String, dynamic>?> getAppointment(String salonId, String appointmentId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.get(
      Uri.parse('$baseUrl/partner/salons/$salonId/appointments/$appointmentId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final appointment = jsonDecode(response.body)['appointment'];
      return appointment is Map<String, dynamic> ? appointment : null;
    }
    if (response.statusCode == 404 || response.statusCode == 403) return null;
    if (response.statusCode == 401) {
      prefs.remove('auth_token');
      throw Exception('Session expired. Please log in again.');
    }
    debugPrint('Failed to load appointment: ${response.statusCode} - ${response.body}');
    throw Exception('Failed to load booking');
  }

  Future<List<dynamic>> getAppointments(String salonId, {String? date, String? providerId}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    final queryParams = <String, String>{};
    if (date != null && date.isNotEmpty) queryParams['date'] = date;
    if (providerId != null && providerId.isNotEmpty) queryParams['provider_id'] = providerId;

    final uri = Uri.parse('$baseUrl/partner/salons/$salonId/appointments')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['appointments'];
    } else if (response.statusCode == 401) {
      prefs.remove('auth_token');
      throw Exception('Session expired. Please log in again.');
    } else {
      debugPrint('Failed to load appointments: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to load appointments');
    }
  }

  Future<Map<String, dynamic>> addServiceMidAppointment(String salonId, String appointmentId, String serviceId, String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/partner/salons/$salonId/appointments/$appointmentId/add-service'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'service_id': serviceId,
        'provider_id': providerId,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to add service mid-appointment');
    }
  }

  Future<void> markNoShow(String appointmentId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/partner/appointments/$appointmentId/no-show'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update status');
    }
  }
  
  Future<Map<String, dynamic>> completeAppointment(String appointmentId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/partner/appointments/$appointmentId/complete'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to complete appointment');
    }
  }
}
