import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// A salon's bank details as the server shows them: the account number only
/// ever as its last four digits.
class BankDetails {
  final String? accountHolderName;
  final String? bankName;
  final String? ifsc;
  final String? upiId;
  final String? accountNumberLast4;
  final bool hasRequired;
  final bool hasAny;

  const BankDetails({
    this.accountHolderName,
    this.bankName,
    this.ifsc,
    this.upiId,
    this.accountNumberLast4,
    this.hasRequired = false,
    this.hasAny = false,
  });

  String get maskedAccount => accountNumberLast4 == null ? '' : '•••• $accountNumberLast4';

  factory BankDetails.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const {};
    String? s(String k) {
      final v = j[k]?.toString();
      return (v == null || v.isEmpty) ? null : v;
    }

    return BankDetails(
      accountHolderName: s('account_holder_name'),
      bankName: s('bank_name'),
      ifsc: s('ifsc'),
      upiId: s('upi_id'),
      accountNumberLast4: s('account_number_last4'),
      hasRequired: j['has_required'] == true,
      hasAny: j['has_any'] == true,
    );
  }
}

/// Another of the owner's salons whose account can be reused here
/// ("Same as my other salon"). Masked like any other.
class OtherSalonBank {
  final String salonId;
  final String salonName;
  final BankDetails details;

  const OtherSalonBank({required this.salonId, required this.salonName, required this.details});

  factory OtherSalonBank.fromJson(Map<String, dynamic> json) => OtherSalonBank(
        salonId: json['salon_id']?.toString() ?? '',
        salonName: json['salon_name']?.toString() ?? 'Salon',
        details: BankDetails.fromJson(json),
      );

  static List<OtherSalonBank> listFrom(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((m) => OtherSalonBank.fromJson(Map<String, dynamic>.from(m))).toList()
      : const [];
}

/// The details plus whether the Home tab should show the "not added" warning.
class BankDetailsStatus {
  final BankDetails details;

  /// True only when the salon's plan is live and the transfer details are
  /// still missing.
  final bool showMissingWarning;

  /// The owner's other salons with complete details, to copy from.
  final List<OtherSalonBank> otherSalons;

  const BankDetailsStatus({
    required this.details,
    required this.showMissingWarning,
    this.otherSalons = const [],
  });

  factory BankDetailsStatus.fromJson(Map<String, dynamic> json) => BankDetailsStatus(
        details: BankDetails.fromJson(json['bank_details'] as Map<String, dynamic>?),
        showMissingWarning: json['show_missing_warning'] == true,
        otherSalons: OtherSalonBank.listFrom(json['other_salons']),
      );
}

class BankDetailsApi {
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

  static Future<BankDetailsStatus> fetch(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/bank-details'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return BankDetailsStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_error(response));
  }

  /// Saves the given `bank_*` fields. An empty account number keeps the saved
  /// one. Throws with the server's message (or the first field error).
  static Future<BankDetailsStatus> save(String salonId, Map<String, String> fields) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/salons/$salonId/bank-details'),
      headers: await _headers(),
      body: jsonEncode(fields),
    );

    if (response.statusCode == 200) {
      return BankDetailsStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_error(response));
  }

  /// Copies another of the owner's salons' account onto this one. The server
  /// does the copying, so the full number never reaches the phone.
  static Future<BankDetailsStatus> copyFrom(String salonId, String fromSalonId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/bank-details/copy'),
      headers: await _headers(),
      body: jsonEncode({'from_salon_id': fromSalonId}),
    );

    if (response.statusCode == 200) {
      return BankDetailsStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_error(response));
  }

  /// The owner's salons with complete details, for a branch still being
  /// registered. Empty on any failure: the option simply does not show.
  static Future<List<OtherSalonBank>> savedAccounts() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/bank-details/saved'),
        headers: await _headers(),
      );
      if (response.statusCode != 200) return const [];
      return OtherSalonBank.listFrom((jsonDecode(response.body) as Map)['salons']);
    } catch (_) {
      return const [];
    }
  }

  static String _error(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['errors'] is Map) {
        final first = (body['errors'] as Map).values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      if (body is Map && body['message'] != null) return body['message'].toString();
    } catch (_) {}
    return 'Could not save bank details (${response.statusCode}). Please try again.';
  }
}
