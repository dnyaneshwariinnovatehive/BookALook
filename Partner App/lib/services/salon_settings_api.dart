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

  /// Saves the salon's week. The server moves staff on salon hours to it,
  /// trims custom shifts that no longer fit, and reports both those trims and
  /// any booking now outside the hours.
  static Future<WorkingHoursSaveResult> updateWorkingHours(String salonId, List<SalonWorkingHour> hours) async {
    final body = {
      'working_hours': hours.map((h) => h.toJson()).toList(),
    };

    final response = await http.put(
      Uri.parse('$baseUrl/salons/$salonId/working-hours'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      String errorMessage = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['errors'] is Map) {
            final errors = decoded['errors'] as Map;
            final firstErrorList = errors.values.first;
            if (firstErrorList is List && firstErrorList.isNotEmpty) {
              errorMessage = firstErrorList.first.toString();
            } else {
              errorMessage = firstErrorList.toString();
            }
          } else if (decoded['message'] != null) {
            errorMessage = decoded['message'].toString();
          }
        }
      } catch (_) {}
      throw Exception(errorMessage);
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return WorkingHoursSaveResult.fromJson(decoded);
    } catch (_) {}
    return const WorkingHoursSaveResult();
  }

  static Future<Map<String, dynamic>> updateSalonProfile({
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
    final bodyStr = await response.stream.bytesToString();
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to update salon profile: $bodyStr');
    }
    
    final json = jsonDecode(bodyStr);
    return json['salon'] as Map<String, dynamic>;
  }
}

/// What saving the salon's hours did beyond saving them.
class WorkingHoursSaveResult {
  /// Custom shifts the server cut back to fit the new hours.
  final List<TrimmedShift> trimmed;

  /// Upcoming bookings now outside the hours, by day of week (0 = Sunday).
  final Map<int, int> bookingsOutsideHours;

  const WorkingHoursSaveResult({this.trimmed = const [], this.bookingsOutsideHours = const {}});

  factory WorkingHoursSaveResult.fromJson(Map<String, dynamic> json) => WorkingHoursSaveResult(
        trimmed: ((json['trimmed_shifts'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => TrimmedShift.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        bookingsOutsideHours: {
          for (final e in ((json['bookings_outside_hours'] as List?) ?? []).whereType<Map>())
            int.tryParse('${e['day_of_week']}') ?? 0: int.tryParse('${e['count']}') ?? 0,
        },
      );
}

class TrimmedShift {
  final String providerId;
  final String name;
  final int dayOfWeek;
  final String? fromStart;
  final String? fromEnd;

  /// Null when the day became a day off.
  final String? toStart;
  final String? toEnd;

  const TrimmedShift({
    required this.providerId,
    required this.name,
    required this.dayOfWeek,
    this.fromStart,
    this.fromEnd,
    this.toStart,
    this.toEnd,
  });

  bool get becameDayOff => toStart == null || toEnd == null;

  factory TrimmedShift.fromJson(Map<String, dynamic> json) {
    final from = (json['from'] as List?) ?? const [];
    final to = (json['to'] as List?) ?? const [];
    return TrimmedShift(
      providerId: '${json['provider_id']}',
      name: json['name']?.toString() ?? 'Staff',
      dayOfWeek: int.tryParse('${json['day_of_week']}') ?? 0,
      fromStart: from.isNotEmpty ? from[0]?.toString() : null,
      fromEnd: from.length > 1 ? from[1]?.toString() : null,
      toStart: to.isNotEmpty ? to[0]?.toString() : null,
      toEnd: to.length > 1 ? to[1]?.toString() : null,
    );
  }
}
