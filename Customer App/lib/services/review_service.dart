import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:customer_app/services/http_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Rating a visit, reporting one, and reading what other people said.
class ReviewService {
  static String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Visits the customer has had but not yet rated.
  ///
  /// Returns empty on any failure. A rating prompt is a courtesy, not a
  /// feature to interrupt someone with an error over.
  static Future<List<dynamic>> pending() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/customer/reviews/pending'),
        headers: await _headers(),
      );

      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body);
      return body['success'] == true ? (body['data'] as List? ?? const []) : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Submit a rating, and optionally a report alongside it.
  ///
  /// Throws [ReviewRefused] with the server's own wording when it says no —
  /// "you have already reviewed this visit" is worth reading.
  static Future<Map<String, dynamic>> submit({
    required String appointmentId,
    required int rating,
    String? comment,
    bool raiseComplaint = false,
    String? complaintSubject,
    String? complaintDescription,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/customer/appointments/$appointmentId/review'),
      headers: await _headers(),
      body: jsonEncode({
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
        'raise_complaint': raiseComplaint,
        if (raiseComplaint) 'complaint_subject': complaintSubject,
        if (raiseComplaint) 'complaint_description': complaintDescription,
      }),
    );

    final body = _decode(response.body);

    if (response.statusCode == 200 || response.statusCode == 201) return body;

    throw ReviewRefused(_messageFrom(body, response.statusCode));
  }

  /// A salon's reviews, page by page. Open to signed-out readers too.
  static Future<Map<String, dynamic>?> forSalon(
    String salonId, {
    int page = 1,
    int? rating,
    bool withComment = false,
  }) async {
    try {
      final query = {
        'page': '$page',
        if (rating != null) 'rating': '$rating',
        if (withComment) 'with_comment': '1',
      };

      final response = await http.get(
        Uri.parse('$_baseUrl/customer/salons/$salonId/reviews')
            .replace(queryParameters: query),
        headers: await _headers(),
      );

      if (response.statusCode != 200) return null;
      final body = _decode(response.body);
      return body['success'] == true ? body : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static String _messageFrom(Map<String, dynamic> body, int status) {
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }

    return body['message']?.toString() ?? 'Could not save your review ($status).';
  }
}

/// The server declined the review — already given, too old, or not yours.
class ReviewRefused implements Exception {
  final String message;

  ReviewRefused(this.message);

  @override
  String toString() => message;
}
