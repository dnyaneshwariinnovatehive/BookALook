import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

/// Emergency day closure: shut a trading day and release everything booked on
/// it for a free reschedule.
class SalonClosureApi {
  static String get _baseUrl => '${ApiConfig.baseUrl}/partner';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// What closing [date] would do — shown before the admin confirms, because
  /// cancelling a day of trade should never be a surprise.
  static Future<ClosurePreview> preview(String salonId, String date) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/closures/preview?date=$date'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return ClosurePreview.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  /// Closes the day. Returns the human-readable outcome summary.
  static Future<ClosureResult> closeDay(
    String salonId,
    String date, {
    String? reason,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/closures'),
      headers: await _headers(),
      body: jsonEncode({
        'date': date,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return ClosureResult.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  static Future<List<dynamic>> upcomingClosures(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/closures'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['closures'] as List<dynamic>;
    }
    throw Exception(_errorFrom(response));
  }

  static Future<String> reopenDay(String salonId, String closureId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/salons/$salonId/closures/$closureId'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['message'] ?? 'The day is open again.';
    }
    throw Exception(_errorFrom(response));
  }

  static String _errorFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] != null) return body['message'];
      if (body is Map && body['errors'] != null) {
        final errors = (body['errors'] as Map).values.expand((e) => e as List);
        return errors.join('\n');
      }
    } catch (_) {
      // fall through to the generic message
    }
    return 'Request failed (${response.statusCode}).';
  }
}

class ClosurePreview {
  final String date;
  final bool alreadyClosed;
  final int affectedCount;
  final int customerCount;
  final int walkInCount;
  final int untouchableCount;
  final double advanceCarriedForward;
  final List<dynamic> appointments;

  ClosurePreview({
    required this.date,
    required this.alreadyClosed,
    required this.affectedCount,
    required this.customerCount,
    required this.walkInCount,
    required this.untouchableCount,
    required this.advanceCarriedForward,
    required this.appointments,
  });

  factory ClosurePreview.fromJson(Map<String, dynamic> json) => ClosurePreview(
        date: json['date'] ?? '',
        alreadyClosed: json['already_closed'] == true,
        affectedCount: json['affected_count'] ?? 0,
        customerCount: json['customer_count'] ?? 0,
        walkInCount: json['walk_in_count'] ?? 0,
        untouchableCount: json['untouchable_count'] ?? 0,
        advanceCarriedForward:
            double.tryParse('${json['advance_carried_forward'] ?? 0}') ?? 0,
        appointments: json['appointments'] ?? const [],
      );
}

class ClosureResult {
  final String message;
  final int releasedCount;
  final int notifiedCount;
  final int untouchableCount;
  final double advanceCarriedForward;

  ClosureResult({
    required this.message,
    required this.releasedCount,
    required this.notifiedCount,
    required this.untouchableCount,
    required this.advanceCarriedForward,
  });

  factory ClosureResult.fromJson(Map<String, dynamic> json) => ClosureResult(
        message: json['message'] ?? 'Day closed.',
        releasedCount: json['released_count'] ?? 0,
        notifiedCount: json['notified_count'] ?? 0,
        untouchableCount: json['untouchable_count'] ?? 0,
        advanceCarriedForward:
            double.tryParse('${json['advance_carried_forward'] ?? 0}') ?? 0,
      );
}
