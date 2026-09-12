import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/onboarding_draft.dart';
import 'api_config.dart';

/// Everything the collaborator side of the partner app asks the server for.
class CollaboratorApi {
  static String get _baseUrl => '${ApiConfig.baseUrl}/partner/collaborator';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Assignments still waiting to be onboarded. Includes any whose salon
  /// SuperAdmin sent back, flagged with `needs_correction`.
  static Future<List<dynamic>> assignedEnquiries() async {
    final response = await http.get(Uri.parse('$_baseUrl/assigned-enquiries'), headers: await _headers());
    return _list(response);
  }

  /// Salons this collaborator has submitted, and where each one got to.
  static Future<List<dynamic>> onboardedSalons() async {
    final response = await http.get(Uri.parse('$_baseUrl/onboarded-salons'), headers: await _headers());
    return _list(response);
  }

  /// Existing salons SuperAdmin assigned from the directory — already
  /// registered, already owned, just put in this collaborator's care.
  static Future<List<dynamic>> assignedSalons() async {
    final response = await http.get(Uri.parse('$_baseUrl/assigned-salons'), headers: await _headers());
    return _list(response);
  }

  /// The collaborator's own record and their running tally.
  static Future<Map<String, dynamic>?> profile() async {
    final response = await http.get(Uri.parse('$_baseUrl/me'), headers: await _headers());

    if (response.statusCode != 200) return null;
    final body = _decode(response.body);
    return body['success'] == true ? Map<String, dynamic>.from(body['data']) : null;
  }

  /// Save contact details. Phone is not among them — it is the login identity.
  ///
  /// Throws [OnboardingRejected] carrying the server's own wording when the
  /// values are refused, so the form can show why rather than "failed".
  static Future<void> updateProfile(Map<String, dynamic> fields) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/me'),
      headers: {...await _headers(), 'Content-Type': 'application/json'},
      body: jsonEncode(fields),
    );

    if (response.statusCode == 200) return;

    final body = _decode(response.body);

    if (response.statusCode >= 400 && response.statusCode < 500) {
      throw OnboardingRejected(_messageFrom(body, response.statusCode));
    }

    throw HttpException('Could not save your profile (${response.statusCode}).');
  }

  /// Salons this collaborator onboarded whose plan is running out or has run
  /// out. Empty on failure — an alert list that cannot load must not break the
  /// screen it sits on.
  static Future<List<dynamic>> alerts() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/alerts'), headers: await _headers());
      return _list(response);
    } catch (_) {
      return [];
    }
  }

  /// What a previously submitted salon already holds, so a rejection can be
  /// corrected rather than retyped. Null when it cannot be reached — the
  /// collaborator then starts from the enquiry, which is worse but not broken.
  static Future<Map<String, dynamic>?> submittedSalon(String salonId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/salons/$salonId/submission'),
        headers: await _headers(),
      );

      if (response.statusCode != 200) return null;
      final body = _decode(response.body);
      return body['success'] == true ? Map<String, dynamic>.from(body['data']) : null;
    } catch (_) {
      return null;
    }
  }

  /// The standard service catalog, for pricing a salon's menu on site.
  static Future<List<dynamic>> masterCatalog() async {
    final response = await http.get(Uri.parse('$_baseUrl/master-catalog'), headers: await _headers());

    if (response.statusCode != 200) return [];
    final body = jsonDecode(response.body);
    return body['categories'] as List<dynamic>? ?? [];
  }

  /// Hand a finished draft to the server.
  ///
  /// Throws [OnboardingRejected] when the server refused the content — a bad
  /// draft must not sit in the sync queue retrying forever. Any other failure
  /// (no signal, server down) throws normally and the caller keeps the draft
  /// queued.
  static Future<Map<String, dynamic>> submit(OnboardingDraft draft) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/enquiries/${draft.enquiryId}/onboard'),
    )..headers.addAll(await _headers());

    request.fields.addAll(draft.toFormFields());
    request.fields['working_hours'] =
        jsonEncode(draft.workingHours.map((d) => d.toJson()).toList());
    request.fields['services'] =
        jsonEncode(draft.services.map((s) => s.toPayload()).toList());

    for (final path in draft.photoPaths) {
      final file = File(path);
      // A photo the OS cleaned up must not sink the whole submission — the
      // profile matters more than the gallery.
      if (await file.exists()) {
        request.files.add(await http.MultipartFile.fromPath('photos[]', path));
      }
    }

    final response = await http.Response.fromStream(await request.send());
    final body = _decode(response.body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return body;
    }

    // 4xx is the server saying the draft itself is wrong. Retrying it
    // unchanged will fail identically, so it stops being a queue problem and
    // becomes something the collaborator has to fix.
    if (response.statusCode >= 400 && response.statusCode < 500) {
      throw OnboardingRejected(_messageFrom(body, response.statusCode));
    }

    throw HttpException('Submission failed (${response.statusCode}).');
  }

  static List<dynamic> _list(http.Response response) {
    if (response.statusCode != 200) return [];
    final body = _decode(response.body);
    return body['success'] == true ? (body['data'] as List<dynamic>? ?? []) : [];
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  /// Laravel returns a message for a refusal and a field map for a validation
  /// failure; the collaborator needs to read either one.
  static String _messageFrom(Map<String, dynamic> body, int status) {
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }

    return body['message']?.toString() ?? 'The server refused this submission ($status).';
  }
}

/// The server looked at the draft and said no. Distinct from a network failure
/// so the sync queue can stop retrying and surface it instead.
class OnboardingRejected implements Exception {
  final String message;

  OnboardingRejected(this.message);

  @override
  String toString() => message;
}
