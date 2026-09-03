import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/service_models.dart';
import 'api_config.dart';

class ServiceManagementApi {
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

  // Fetch Master Catalog (Categories and Templates)
  static Future<List<ServiceCategory>> getMasterCatalog(String? salonId) async {
    final uri = Uri.parse('$baseUrl/master-catalog').replace(queryParameters: {
      if (salonId != null) 'salon_id': salonId,
    });
    
    final response = await http.get(uri, headers: await _getHeaders());
    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final categoriesJson = jsonResponse['categories'] as List;
      return categoriesJson.map((json) => ServiceCategory.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch master catalog: ${response.body}');
    }
  }

  // Fetch Salon's Services (grouped by category)
  // We'll return a List of Map containing category and services
  static Future<List<Map<String, dynamic>>> getSalonServices(String salonId) async {
    final response = await http.get(Uri.parse('$baseUrl/salons/$salonId/services'), headers: await _getHeaders());
    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(jsonResponse['grouped_services']);
    } else {
      throw Exception('Failed to fetch salon services: ${response.body}');
    }
  }

  // Add Service
  static Future<SalonService> addService({
    required String salonId,
    required bool isCustom,
    String? templateId,
    required double price,
    String? description,
    String? categoryId,
    String? customCategoryName,
    String? customTemplateName,
    int? estimatedDurationMinutes,
  }) async {
    final body = {
      'is_custom': isCustom,
      if (!isCustom) 'template_id': templateId,
      'price': price,
      if (description != null) 'description': description,
      if (isCustom) 'category_id': categoryId,
      if (isCustom && categoryId == 'new_custom') 'custom_category_name': customCategoryName,
      if (isCustom) 'custom_template_name': customTemplateName,
      if (isCustom) 'estimated_duration_minutes': estimatedDurationMinutes,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/salons/$salonId/services'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final jsonResponse = jsonDecode(response.body);
      return SalonService.fromJson(jsonResponse['service']);
    } else {
      throw Exception('Failed to add service: ${response.body}');
    }
  }

  // Update Service
  static Future<SalonService> updateService({
    required String salonId,
    required String serviceId,
    double? price,
    String? description,
  }) async {
    final body = <String, dynamic>{};
    if (price != null) body['price'] = price;
    if (description != null) body['description'] = description;

    final response = await http.put(
      Uri.parse('$baseUrl/salons/$salonId/services/$serviceId'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return SalonService.fromJson(jsonResponse['service']);
    } else {
      throw Exception('Failed to update service: ${response.body}');
    }
  }

  // Delete Service
  static Future<void> deleteService(String salonId, String serviceId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/salons/$salonId/services/$serviceId'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete service: ${response.body}');
    }
  }
  // Combos
  static Future<List<dynamic>> getCombos(String salonId) async {
    final response = await http.get(Uri.parse('$baseUrl/salons/$salonId/combos'), headers: await _getHeaders());
    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['combos'] as List<dynamic>;
    } else {
      throw Exception('Failed to fetch combos: ${response.body}');
    }
  }

  static Future<dynamic> createCombo({
    required String salonId,
    required String name,
    required List<Map<String, dynamic>> services,
  }) async {
    final body = {
      'name': name,
      'services': services,
    };
    final response = await http.post(
      Uri.parse('$baseUrl/salons/$salonId/combos'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body)['combo'];
    } else {
      throw Exception('Failed to create combo: ${response.body}');
    }
  }

  // Staff Assignment
  static Future<Map<String, dynamic>> getServiceStaff(String salonId, String serviceId) async {
    final response = await http.get(Uri.parse('$baseUrl/salons/$salonId/services/$serviceId/staff'), headers: await _getHeaders());
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch service staff: ${response.body}');
    }
  }

  static Future<void> assignServiceStaff(String salonId, String serviceId, List<String> staffIds) async {
    final body = {
      'staff_ids': staffIds,
    };
    final response = await http.post(
      Uri.parse('$baseUrl/salons/$salonId/services/$serviceId/staff'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to assign staff: ${response.body}');
    }
  }
}
