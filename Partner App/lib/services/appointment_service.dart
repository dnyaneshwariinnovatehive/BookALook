import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class PartnerAppointmentService {
  // Must match the rest of the app — see ApiConfig.
  String get baseUrl => ApiConfig.baseUrl;

  Future<List<dynamic>> getAppointments(String salonId, {String? date}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    String url = '$baseUrl/partner/salons/$salonId/appointments';
    if (date != null) {
      url += '?date=$date';
    }

    final response = await http.get(
      Uri.parse(url),
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
      print('Failed to load appointments: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to load appointments');
    }
  }

  Future<Map<String, dynamic>> verifyQrAndStartSession(String salonId, String qrToken) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final response = await http.post(
      Uri.parse('$baseUrl/partner/salons/$salonId/appointments/verify-qr'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'qr_token': qrToken,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to verify QR Code');
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
