import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/staff_models.dart';
import '../models/leave_models.dart';
import 'api_config.dart';

class StaffApi {
  static String get baseUrl => '${ApiConfig.baseUrl}/partner';

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<List<StaffMember>> fetchStaff(String salonId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/salons/$salonId/staff'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final List<dynamic> data = jsonResponse['staff'];
      return data.map((json) => StaffMember.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch staff: ${response.body}');
    }
  }

  static Future<void> addStaff({
    required String salonId,
    required String name,
    required String phone,
    String? email,
    String? specialization,
    required double baseSalary,
    required double commissionPercentage,
    required List<String> serviceIds,
    required List<StaffWorkingHour> workingHours,
  }) async {
    final body = {
      'name': name,
      'phone': phone,
      'email': email,
      'specialization': specialization,
      'base_salary': baseSalary,
      'commission_percentage': commissionPercentage,
      'service_ids': serviceIds,
      'working_hours': workingHours.map((h) => h.toJson()).toList(),
    };

    final response = await http.post(
      Uri.parse('$baseUrl/salons/$salonId/staff'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to add staff: ${response.body}');
    }
  }

  static Future<List<ProviderLeave>> fetchLeaves(String salonId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/salons/$salonId/leaves'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final List<dynamic> data = jsonResponse['leaves'];
      return data.map((json) => ProviderLeave.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch leaves: ${response.body}');
    }
  }

  static Future<void> updateLeaveStatus(String salonId, String leaveId, String status) async {
    final body = {'status': status};

    final response = await http.put(
      Uri.parse('$baseUrl/salons/$salonId/leaves/$leaveId/status'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update leave status: ${response.body}');
    }
  }
}
