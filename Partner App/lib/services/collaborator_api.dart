import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// The collaborator's own inbox — notices about the salons assigned to them.
  ///
  /// Returns an empty inbox on failure, like [alerts]. The bell and the screen
  /// behind it are glanceable; neither may become an error page because a
  /// request failed, and neither is worth a retry queue.
  static Future<CollaboratorInbox> notifications({int limit = 50}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/notifications?limit=$limit'),
        headers: await _headers(),
      );

      if (response.statusCode != 200) return const CollaboratorInbox();

      final body = _decode(response.body);
      if (body['success'] != true) return const CollaboratorInbox();

      final items = body['notifications'] as List<dynamic>? ?? const [];

      return CollaboratorInbox(
        notifications: items
            .whereType<Map<String, dynamic>>()
            .map(CollaboratorNotification.fromJson)
            .toList(),
        unreadCount: (body['unread_count'] as num?)?.toInt() ?? 0,
        importantCount: (body['important_count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const CollaboratorInbox();
    }
  }

  /// Mark one read. Fails silently — a stuck dot is not worth interrupting the
  /// collaborator over, and the next list refresh tells the truth anyway.
  static Future<void> markNotificationRead(String id) async {
    try {
      await http.post(Uri.parse('$_baseUrl/notifications/$id/read'), headers: await _headers());
    } catch (_) {}
  }

  /// Mark the whole inbox read. Same reasoning as above.
  static Future<void> markAllNotificationsRead() async {
    try {
      await http.post(Uri.parse('$_baseUrl/notifications/read-all'), headers: await _headers());
    } catch (_) {}
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
      if (kIsWeb) {
        final res = await http.get(Uri.parse(path));
        request.files.add(http.MultipartFile.fromBytes('photos[]', res.bodyBytes, filename: 'photo.jpg'));
      } else {
        final file = File(path);
        // A photo the OS cleaned up must not sink the whole submission — the
        // profile matters more than the gallery.
        if (await file.exists()) {
          request.files.add(await http.MultipartFile.fromPath('photos[]', path));
        }
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

/// One notice in the collaborator inbox.
///
/// [daysLeft] is deliberately nullable rather than 0-when-lapsed: "expires
/// today" and "expired on some date in the past" are different things for a
/// collaborator, and collapsing them into one number makes the second one look
/// urgent instead of final.
class CollaboratorNotification {
  final String id;
  final String title;
  final String message;
  final String type;
  final String? action;
  final String? salonId;
  final String? salonName;
  final String? ownerPhone;
  final int? daysLeft;
  final bool lapsed;
  final bool read;
  final bool important;
  final DateTime? createdAt;

  const CollaboratorNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.action,
    this.salonId,
    this.salonName,
    this.ownerPhone,
    this.daysLeft,
    this.lapsed = false,
    this.read = false,
    this.important = false,
    this.createdAt,
  });

  /// Read state under the name the screen thinks in.
  bool get isRead => read;

  /// Whether the card offers a "call the owner" button.
  ///
  /// Needs all three: the action the server chose, a number to dial, and a salon
  /// that is still assigned. Without the salon the call cannot be placed from
  /// the right context, and after a reassignment the notice is history anyway.
  bool get canCallOwner =>
      action == 'call_owner' &&
      (ownerPhone ?? '').isNotEmpty &&
      (salonId ?? '').isNotEmpty;

  factory CollaboratorNotification.fromJson(Map<String, dynamic> json) {
    final rawDays = (json['days_left'] as num?)?.toInt();

    return CollaboratorNotification(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      action: json['action']?.toString(),
      salonId: json['salon_id']?.toString(),
      salonName: json['salon_name']?.toString(),
      ownerPhone: json['owner_phone']?.toString(),
      daysLeft: rawDays != null && rawDays >= 0 ? rawDays : null,
      lapsed: json['lapsed'] == true || (rawDays != null && rawDays < 0),
      read: json['is_read'] == true || json['read'] == true,
      important: json['important'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  CollaboratorNotification copyWith({bool? read}) => CollaboratorNotification(
        id: id,
        title: title,
        message: message,
        type: type,
        action: action,
        salonId: salonId,
        salonName: salonName,
        ownerPhone: ownerPhone,
        daysLeft: daysLeft,
        lapsed: lapsed,
        read: read ?? this.read,
        important: important,
        createdAt: createdAt,
      );
}

/// The inbox plus the counters the bell badge needs.
///
/// Carrying the counts means the bell can show an unread number after the list
/// has already been discarded, instead of the collaborator being told they have
/// nothing to read the moment the screen is popped.
class CollaboratorInbox {
  final List<CollaboratorNotification> notifications;
  final int unreadCount;
  final int importantCount;

  const CollaboratorInbox({
    this.notifications = const [],
    this.unreadCount = 0,
    this.importantCount = 0,
  });
}
