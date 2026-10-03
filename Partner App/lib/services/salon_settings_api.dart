import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/salon_working_hour.dart';
import 'api_config.dart';

class SalonSettingsApi {
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

  static Future<Map<String, dynamic>> fetchWorkingHours(String salonId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/salons/$salonId/working-hours'),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final List<dynamic> data = jsonResponse['working_hours'];
      return {
        'hours': data.map((json) => SalonWorkingHour.fromJson(json)).toList(),
        'is_default': jsonResponse['is_default'] ?? false,
      };
    } else {
      throw Exception('Failed to fetch working hours: ${response.body}');
    }
  }

  static Future<void> updateWorkingHours(String salonId, List<SalonWorkingHour> hours) async {
    final body = {
      'working_hours': hours.map((h) => h.toJson()).toList(),
    };

    final response = await http.put(
      Uri.parse('$baseUrl/salons/$salonId/working-hours'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update working hours: ${response.body}');
    }
  }

  static Future<void> updateSalonProfile({
    required String salonId,
    required String name,
    required String phone,
    required String description,
    String? address,
    String? pincode,
    String? genderFocus,
    String? mapUrl,
    bool? advanceRequired,
    String? advancePercentageDefault,
    String? imagePath,
  }) async {
    final headers = await _getHeaders();
    headers.remove('Content-Type'); // Let MultipartRequest set its own boundary

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/salons/$salonId'),
    )..headers.addAll(headers);

    request.fields['_method'] = 'PUT'; // Common convention for multipart PUT in PHP/Laravel
    request.fields['name'] = name;
    request.fields['phone'] = phone;
    request.fields['description'] = description;
    
    if (address != null && address.isNotEmpty) {
      request.fields['address'] = address;
    }
    if (pincode != null && pincode.isNotEmpty) {
      request.fields['pincode'] = pincode;
    }
    if (genderFocus != null && genderFocus.isNotEmpty) {
      request.fields['gender_focus'] = genderFocus;
    }
    if (mapUrl != null) {
      request.fields['map_url'] = mapUrl;
    }
    if (advanceRequired != null) {
      request.fields['advance_required'] = advanceRequired ? '1' : '0';
    }
    if (advancePercentageDefault != null && advancePercentageDefault.isNotEmpty) {
      request.fields['advance_percentage_default'] = advancePercentageDefault;
    }

    if (imagePath != null) {
      final fileBytes = await File(imagePath).readAsBytes();
      String filename = imagePath.split(RegExp(r'[/\\]')).last;
      String extension = 'jpeg';
      if (filename.toLowerCase().endsWith('.png')) {
        extension = 'png';
      } else if (filename.toLowerCase().endsWith('.jpg') || filename.toLowerCase().endsWith('.jpeg')) {
        extension = 'jpeg';
      } else if (filename.toLowerCase().endsWith('.webp')) {
        extension = 'webp';
      }
      
      if (!filename.contains('.')) {
        filename = '$filename.$extension';
      }
      
      request.files.add(http.MultipartFile.fromBytes(
        'cover_image', 
        fileBytes,
        filename: filename,
        contentType: MediaType('image', extension),
      ));
    }

    final response = await request.send();
    if (response.statusCode != 200 && response.statusCode != 201) {
      final bodyStr = await response.stream.bytesToString();
      throw Exception('Failed to update salon profile: $bodyStr');
    }
  }
}
