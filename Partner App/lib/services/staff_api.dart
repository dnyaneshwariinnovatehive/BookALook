import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/staff_models.dart';
import '../models/leave_models.dart';
import '../models/service_models.dart';
import 'api_config.dart';

class StaffResult {
  final List<StaffMember> staff;
  final List<UnassignedServiceItem> unassignedServices;

  StaffResult({
    required this.staff,
    required this.unassignedServices,
  });
}

class StaffApi {
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

  // Fetch staff list only (kept for backward compatibility with existing callers)
  static Future<List<StaffMember>> fetchStaff(String salonId) async {
    final result = await fetchStaffDetailed(salonId);
    return result.staff;
  }

  // Fetch staff along with unassigned services list
  static Future<StaffResult> fetchStaffDetailed(String salonId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/salons/$salonId/staff'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final List<dynamic> data = jsonResponse['staff'] ?? [];
      final staffList = data.map((json) => StaffMember.fromJson(json)).toList();
      final unassigned = (jsonResponse['unassigned_services'] as List? ?? [])
          .map((item) => UnassignedServiceItem.fromJson(item))
          .toList();
      return StaffResult(staff: staffList, unassignedServices: unassigned);
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
    bool autoApproveLeave = false,
    bool useSalonWorkingHours = true,
  }) async {
    final body = {
      'name': name,
      'phone': phone,
      'email': email,
      'specialization': specialization,
      'base_salary': baseSalary,
      'commission_percentage': commissionPercentage,
      'service_ids': serviceIds,
      'auto_approve_leave': autoApproveLeave,
      'use_salon_hours': useSalonWorkingHours,
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

  static Future<void> updateStaff({
    required String salonId,
    required String staffId,
    String? name,
    String? phone,
    String? email,
    String? specialization,
    double? baseSalary,
    double? commissionPercentage,
    List<String>? serviceIds,
    List<StaffWorkingHour>? workingHours,
    bool? autoApproveLeave,
    bool? useSalonWorkingHours,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (phone != null) body['phone'] = phone;
    if (email != null) body['email'] = email;
    if (specialization != null) body['specialization'] = specialization;
    if (baseSalary != null) body['base_salary'] = baseSalary;
    if (commissionPercentage != null) body['commission_percentage'] = commissionPercentage;
    if (serviceIds != null) body['service_ids'] = serviceIds;
    if (autoApproveLeave != null) body['auto_approve_leave'] = autoApproveLeave;
    if (useSalonWorkingHours != null) body['use_salon_hours'] = useSalonWorkingHours;
    if (workingHours != null) body['working_hours'] = workingHours.map((h) => h.toJson()).toList();

    final response = await http.put(
      Uri.parse('$baseUrl/salons/$salonId/staff/$staffId'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update staff: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> fetchMyProfile(String salonId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/salons/$salonId/provider-profile'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch provider profile: ${response.body}');
    }
  }

  static Future<void> deleteStaff(String salonId, String staffId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/salons/$salonId/staff/$staffId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete staff: ${response.body}');
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

  static Future<Map<String, dynamic>> requestLeave(String salonId, Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/salons/$salonId/leaves'),
      headers: await _getHeaders(),
      body: jsonEncode(data),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to request leave: ${response.body}');
    }
  }

  static Future<List<ProviderLeave>> fetchMyLeaves(String salonId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/salons/$salonId/my-leaves'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final List<dynamic> data = jsonResponse['leaves'];
      return data.map((json) => ProviderLeave.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch my leaves: ${response.body}');
    }
  }
}
