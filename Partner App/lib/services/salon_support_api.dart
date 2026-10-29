import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// One open settlement, as the lock screen lists it.
class OpenSettlement {
  final String id;
  final String label;

  /// `pay_salon` when BookALook owes the salon, `salon_owes` the other way.
  final String direction;
  final double amount;

  const OpenSettlement({required this.id, required this.label, required this.direction, required this.amount});

  bool get salonOwes => direction == 'salon_owes';

  factory OpenSettlement.fromJson(Map<String, dynamic> json) => OpenSettlement(
        id: json['id'].toString(),
        label: json['label']?.toString() ?? '',
        direction: json['direction']?.toString() ?? 'pay_salon',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

/// Where the salon stands with BookALook: settlements not yet closed.
class SettlementSummary {
  final int pendingCount;
  final double owedToSalon;
  final int owedToSalonCount;
  final double owedBySalon;
  final int owedBySalonCount;
  final int underReview;
  final int openRequests;
  final List<OpenSettlement> settlements;

  const SettlementSummary({
    required this.pendingCount,
    required this.owedToSalon,
    required this.owedToSalonCount,
    required this.owedBySalon,
    required this.owedBySalonCount,
    required this.underReview,
    required this.openRequests,
    required this.settlements,
  });

  factory SettlementSummary.fromJson(Map<String, dynamic> json) {
    final toSalon = (json['owed_to_salon'] as Map?) ?? const {};
    final bySalon = (json['owed_by_salon'] as Map?) ?? const {};
    return SettlementSummary(
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
      owedToSalon: (toSalon['amount'] as num?)?.toDouble() ?? 0,
      owedToSalonCount: (toSalon['count'] as num?)?.toInt() ?? 0,
      owedBySalon: (bySalon['amount'] as num?)?.toDouble() ?? 0,
      owedBySalonCount: (bySalon['count'] as num?)?.toInt() ?? 0,
      underReview: (bySalon['under_review'] as num?)?.toInt() ?? 0,
      openRequests: (json['open_requests'] as num?)?.toInt() ?? 0,
      settlements: ((json['settlements'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OpenSettlement.fromJson)
          .toList(),
    );
  }
}

/// A message the owner sent BookALook, and the reply if there is one.
class SupportRequest {
  final String id;
  final String topicLabel;
  final String message;
  final String status;
  final String? reply;
  final DateTime? createdAt;
  final DateTime? repliedAt;

  const SupportRequest({
    required this.id,
    required this.topicLabel,
    required this.message,
    required this.status,
    this.reply,
    this.createdAt,
    this.repliedAt,
  });

  bool get isOpen => status == 'open';

  factory SupportRequest.fromJson(Map<String, dynamic> json) => SupportRequest(
        id: json['id'].toString(),
        topicLabel: json['topic_label']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        status: json['status']?.toString() ?? 'open',
        reply: json['reply']?.toString(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
        repliedAt: DateTime.tryParse(json['replied_at']?.toString() ?? '')?.toLocal(),
      );
}

class SupportTopic {
  final String key;
  final String label;
  const SupportTopic(this.key, this.label);
}

/// Settlements and messages to BookALook. Owner only, and reachable even
/// while the salon is locked.
class SalonSupportApi {
  static String get _base => '${ApiConfig.baseUrl}/partner/salons';

  /// Used when the server has not said (offline first load).
  static const defaultTopics = [
    SupportTopic('settlement_query', 'Settlement query'),
    SupportTopic('payout_request', 'Request my payout'),
    SupportTopic('renewal_help', 'Help with renewal'),
    SupportTopic('other', 'Something else'),
  ];

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<SettlementSummary> summary(String salonId) async {
    final response = await http.get(Uri.parse('$_base/$salonId/settlement-summary'), headers: await _headers());
    if (response.statusCode == 200) {
      return SettlementSummary.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_error(response, 'Could not load settlements.'));
  }

  static Future<(List<SupportTopic>, List<SupportRequest>)> requests(String salonId) async {
    final response = await http.get(Uri.parse('$_base/$salonId/support-requests'), headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception(_error(response, 'Could not load your messages.'));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final topics = ((body['topics'] as List?) ?? const [])
        .whereType<Map>()
        .map((t) => SupportTopic(t['key'].toString(), t['label'].toString()))
        .toList();
    final list = ((body['requests'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SupportRequest.fromJson)
        .toList();
    return (topics.isEmpty ? defaultTopics : topics, list);
  }

  static Future<String> send(String salonId, {required String topic, required String message, String? payoutId}) async {
    final response = await http.post(
      Uri.parse('$_base/$salonId/support-requests'),
      headers: await _headers(),
      body: jsonEncode({'topic': topic, 'message': message, 'salon_payout_id': ?payoutId}),
    );
    if (response.statusCode == 201) {
      return (jsonDecode(response.body)['message'] ?? 'Sent to BookALook.').toString();
    }
    throw Exception(_error(response, 'Could not send. Try again.'));
  }

  static String _error(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['errors'] is Map) {
        final first = (body['errors'] as Map).values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      if (body is Map && body['message'] != null) return body['message'].toString();
    } catch (_) {}
    return fallback;
  }
}
