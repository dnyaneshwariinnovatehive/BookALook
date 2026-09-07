import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'check_in_api.dart';

/// Customers who arrive without a booking.
class WalkInApi {
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

  static Future<WalkInOptions> options(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/walk-in/options'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return WalkInOptions.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  /// Price, duration and any diary clash, before anything is written.
  static Future<WalkInPreview> preview(
    String salonId, {
    required List<String> serviceIds,
    String? providerId,
    String? startTime,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/walk-in/preview'),
      headers: await _headers(),
      body: jsonEncode({
        'services': serviceIds,
        if (providerId != null) 'provider_id': providerId,
        if (startTime != null) 'start_time': startTime,
      }),
    );

    if (response.statusCode == 200) {
      return WalkInPreview.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  /// Creates the walk-in. Throws [WalkInConflict] when the chosen staff member
  /// is already busy and the caller has not chosen to squeeze it in.
  static Future<WalkInResult> create(
    String salonId, {
    required String customerName,
    String? customerPhone,
    String? gender,
    required List<String> serviceIds,
    String? providerId,
    String? startTime,
    bool allowOverlap = false,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/appointments/walk-in'),
      headers: await _headers(),
      body: jsonEncode({
        'customer_name': customerName,
        if (customerPhone != null && customerPhone.isNotEmpty) 'customer_phone': customerPhone,
        if (gender != null) 'gender': gender,
        'services': serviceIds,
        if (providerId != null) 'provider_id': providerId,
        if (startTime != null) 'start_time': startTime,
        if (allowOverlap) 'allow_overlap': true,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return WalkInResult.fromJson(jsonDecode(response.body));
    }

    if (response.statusCode == 409) {
      final body = jsonDecode(response.body);
      throw WalkInConflict(
        body['message'] ?? 'That staff member is already busy.',
        ((body['conflicts'] as List?) ?? [])
            .map((e) => WalkInConflictEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }

    throw Exception(_errorFrom(response));
  }

  static String _errorFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] != null) return body['message'];
      if (body is Map && body['errors'] != null) {
        return (body['errors'] as Map).values.expand((e) => e as List).join('\n');
      }
    } catch (_) {
      // fall through
    }
    return 'Request failed (${response.statusCode}).';
  }
}

/// The staff member is busy at the proposed time.
class WalkInConflict implements Exception {
  final String message;
  final List<WalkInConflictEntry> conflicts;

  WalkInConflict(this.message, this.conflicts);

  @override
  String toString() => message;
}

class WalkInConflictEntry {
  final String startTime;
  final String endTime;
  final String customerName;

  WalkInConflictEntry({
    required this.startTime,
    required this.endTime,
    required this.customerName,
  });

  factory WalkInConflictEntry.fromJson(Map<String, dynamic> json) => WalkInConflictEntry(
        startTime: json['start_time'] ?? '',
        endTime: json['end_time'] ?? '',
        customerName: json['customer_name'] ?? 'Customer',
      );
}

class WalkInService {
  final String id;
  final String name;
  final String category;
  final double price;
  final int durationMinutes;

  WalkInService({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.durationMinutes,
  });

  factory WalkInService.fromJson(Map<String, dynamic> json) => WalkInService(
        id: json['id'].toString(),
        name: json['name'] ?? 'Service',
        category: json['category'] ?? 'Other',
        price: double.tryParse('${json['price'] ?? 0}') ?? 0,
        durationMinutes: json['duration_minutes'] ?? 30,
      );
}

class WalkInProvider {
  final String id;
  final String name;
  final String? specialization;
  final List<String> serviceIds;

  WalkInProvider({
    required this.id,
    required this.name,
    this.specialization,
    required this.serviceIds,
  });

  /// Whether this staff member is trained on everything in the basket.
  bool canDoAll(Set<String> ids) => ids.every(serviceIds.contains);

  factory WalkInProvider.fromJson(Map<String, dynamic> json) => WalkInProvider(
        id: json['id'].toString(),
        name: json['name'] ?? 'Staff',
        specialization: json['specialization'],
        serviceIds: ((json['service_ids'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

class WalkInOptions {
  final List<WalkInService> services;
  final List<WalkInProvider> providers;

  /// Set when the caller is a staff member serving their own walk-in.
  final String? defaultProviderId;

  /// Admins choose who serves; a provider is always themselves.
  final bool canChooseProvider;

  WalkInOptions({
    required this.services,
    required this.providers,
    this.defaultProviderId,
    required this.canChooseProvider,
  });

  factory WalkInOptions.fromJson(Map<String, dynamic> json) => WalkInOptions(
        services: ((json['services'] as List?) ?? [])
            .map((e) => WalkInService.fromJson(e as Map<String, dynamic>))
            .toList(),
        providers: ((json['providers'] as List?) ?? [])
            .map((e) => WalkInProvider.fromJson(e as Map<String, dynamic>))
            .toList(),
        defaultProviderId: json['default_provider_id']?.toString(),
        canChooseProvider: json['can_choose_provider'] == true,
      );
}

class WalkInPreview {
  final double total;
  final int durationMinutes;
  final String startsAt;
  final String endsAt;
  final List<WalkInConflictEntry> conflicts;

  WalkInPreview({
    required this.total,
    required this.durationMinutes,
    required this.startsAt,
    required this.endsAt,
    required this.conflicts,
  });

  factory WalkInPreview.fromJson(Map<String, dynamic> json) => WalkInPreview(
        total: double.tryParse('${json['total'] ?? 0}') ?? 0,
        durationMinutes: json['duration_minutes'] ?? 0,
        startsAt: json['starts_at'] ?? '',
        endsAt: json['ends_at'] ?? '',
        conflicts: ((json['conflicts'] as List?) ?? [])
            .map((e) => WalkInConflictEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class WalkInResult {
  final String message;
  final CheckInAppointment appointment;
  final Bill bill;

  WalkInResult({
    required this.message,
    required this.appointment,
    required this.bill,
  });

  factory WalkInResult.fromJson(Map<String, dynamic> json) => WalkInResult(
        message: json['message'] ?? 'Walk-in created.',
        appointment: CheckInAppointment.fromJson(json['appointment']),
        bill: Bill.fromJson(json['bill'] ?? const {}),
      );
}
