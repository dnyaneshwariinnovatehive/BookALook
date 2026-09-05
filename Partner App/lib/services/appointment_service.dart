import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PartnerAppointmentService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

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
    } else {
      print('Failed to load appointments: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to load appointments');
    }
  }

  Future<Map<String, dynamic>> walkIn(String salonId, String name, String phone, List<String> serviceIds, {String? gender, String? startTime}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final Map<String, dynamic> body = {
      'customer_name': name,
      'customer_phone': phone,
      'services': serviceIds,
    };
    if (gender != null) body['gender'] = gender;
    if (startTime != null) body['start_time'] = startTime;

    final response = await http.post(
      Uri.parse('$baseUrl/partner/salons/$salonId/appointments/walk-in'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create walk-in appointment');
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
