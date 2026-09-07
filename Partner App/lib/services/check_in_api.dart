import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

/// Check a customer in from their QR, then bill them on the way out.
class CheckInApi {
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

  /// Look up who a scanned code belongs to. Writes nothing — the session only
  /// starts once staff confirm, so an accidental scan costs nothing.
  static Future<CheckInTarget> resolve(
    String salonId, {
    String? qrToken,
    String? appointmentId,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/check-in/resolve'),
      headers: await _headers(),
      body: jsonEncode({
        if (qrToken != null) 'qr_token': qrToken,
        if (appointmentId != null) 'appointment_id': appointmentId,
      }),
    );

    if (response.statusCode == 200) {
      return CheckInTarget.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  /// Start the session. [servingProviderId] overrides who does the work.
  static Future<Map<String, dynamic>> start(
    String salonId,
    String appointmentId, {
    String? qrToken,
    String? servingProviderId,
    bool manual = false,
    String? reason,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/appointments/$appointmentId/start'),
      headers: await _headers(),
      body: jsonEncode({
        if (qrToken != null) 'qr_token': qrToken,
        if (servingProviderId != null) 'serving_provider_id': servingProviderId,
        if (manual) 'manual': true,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    );

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(_errorFrom(response));
  }

  static Future<CheckInTarget> bill(String salonId, String appointmentId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/appointments/$appointmentId/bill'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return CheckInTarget.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  /// Take the balance and finish the job in one step — the salon runs no tab.
  static Future<Map<String, dynamic>> collectPayment(
    String salonId,
    String appointmentId, {
    required String paymentMode,
    String? note,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/appointments/$appointmentId/collect-payment'),
      headers: await _headers(),
      body: jsonEncode({
        'payment_mode': paymentMode,
        if (note != null && note.isNotEmpty) 'note': note,
      }),
    );

    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception(_errorFrom(response));
  }

  /// Put an extra service on a bill that is already running.
  ///
  /// [providerId] is who delivered it — it defaults to whoever is serving, but
  /// a second staff member doing the extra is exactly the case this supports.
  static Future<CheckInTarget> addExtraService(
    String salonId,
    String appointmentId, {
    required String serviceId,
    String? providerId,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/appointments/$appointmentId/add-service'),
      headers: await _headers(),
      body: jsonEncode({
        'service_id': serviceId,
        if (providerId != null) 'provider_id': providerId,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return CheckInTarget.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  /// Take an extra back off. Voided server-side, not deleted.
  static Future<CheckInTarget> removeExtraService(
    String salonId,
    String appointmentId,
    String additionId,
  ) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/salons/$salonId/appointments/$appointmentId/additions/$additionId'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return CheckInTarget.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  /// Today's bookings still waiting to be checked in or paid for. Backs the
  /// no-scan path when a customer cannot show their code.
  static Future<List<CheckInAppointment>> pending(String salonId, {String? date}) async {
    final uri = Uri.parse('$_baseUrl/salons/$salonId/check-in/pending')
        .replace(queryParameters: date != null ? {'date': date} : null);

    final response = await http.get(uri, headers: await _headers());

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body)['appointments'] as List<dynamic>;
      return list
          .map((e) => CheckInAppointment.fromJson(e as Map<String, dynamic>))
          .toList();
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

/// An appointment as the check-in screens see it.
class CheckInAppointment {
  final String id;
  final String status;
  final String customerName;
  final String? customerPhone;
  final String startTime;
  final String endTime;
  final String bookedProviderName;
  final String? bookedProviderId;
  final String? servingProviderId;
  final String? servingProviderName;
  final double totalAmount;
  final double advanceAmount;
  final double balanceAmount;
  final String? verificationMethod;
  final String? paymentMode;

  CheckInAppointment({
    required this.id,
    required this.status,
    required this.customerName,
    this.customerPhone,
    required this.startTime,
    required this.endTime,
    required this.bookedProviderName,
    this.bookedProviderId,
    this.servingProviderId,
    this.servingProviderName,
    required this.totalAmount,
    required this.advanceAmount,
    required this.balanceAmount,
    this.verificationMethod,
    this.paymentMode,
  });

  bool get isInProgress => status == 'in_progress';
  bool get isScheduled => status == 'scheduled';

  factory CheckInAppointment.fromJson(Map<String, dynamic> json) => CheckInAppointment(
        id: json['id'].toString(),
        status: json['status'] ?? '',
        customerName: json['customer_name'] ?? 'Customer',
        customerPhone: json['customer_phone'],
        startTime: json['start_time'] ?? '',
        endTime: json['end_time'] ?? '',
        bookedProviderName: json['booked_provider_name'] ?? 'Any staff',
        bookedProviderId: json['booked_provider_id']?.toString(),
        servingProviderId: json['serving_provider_id']?.toString(),
        servingProviderName: json['serving_provider_name'],
        totalAmount: _num(json['total_amount']),
        advanceAmount: _num(json['advance_amount']),
        balanceAmount: _num(json['balance_amount']),
        verificationMethod: json['verification_method'],
        paymentMode: json['payment_mode'],
      );

  static double _num(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
}

class BillLine {
  /// The appointment_services row, or the addition row for an extra.
  final String id;
  final String name;
  final double price;
  final int durationMinutes;
  final String? providerName;
  final bool addedMidAppointment;

  /// Only set on extras: who put it on the bill and when.
  final String? addedByName;
  final DateTime? addedAt;

  BillLine({
    required this.id,
    required this.name,
    required this.price,
    required this.durationMinutes,
    this.providerName,
    required this.addedMidAppointment,
    this.addedByName,
    this.addedAt,
  });

  factory BillLine.fromJson(Map<String, dynamic> json) => BillLine(
        id: json['id']?.toString() ?? '',
        name: json['name'] ?? 'Service',
        price: CheckInAppointment._num(json['price']),
        durationMinutes: json['duration_minutes'] ?? 0,
        providerName: json['provider_name'],
        addedMidAppointment: json['added_mid_appointment'] == true,
        addedByName: json['added_by_name'],
        addedAt: DateTime.tryParse('${json['added_at']}'),
      );
}

class Bill {
  final List<BillLine> lines;
  final double total;
  final double advancePaid;
  final double balanceDue;

  Bill({
    required this.lines,
    required this.total,
    required this.advancePaid,
    required this.balanceDue,
  });

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
        lines: ((json['lines'] as List?) ?? [])
            .map((e) => BillLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: CheckInAppointment._num(json['total']),
        advancePaid: CheckInAppointment._num(json['advance_paid']),
        balanceDue: CheckInAppointment._num(json['balance_due']),
      );
}

class ProviderOption {
  final String id;
  final String name;
  final String? specialization;
  final bool isBookedProvider;
  final bool canPerformAll;

  ProviderOption({
    required this.id,
    required this.name,
    this.specialization,
    required this.isBookedProvider,
    required this.canPerformAll,
  });

  factory ProviderOption.fromJson(Map<String, dynamic> json) => ProviderOption(
        id: json['id'].toString(),
        name: json['name'] ?? 'Staff',
        specialization: json['specialization'],
        isBookedProvider: json['is_booked_provider'] == true,
        canPerformAll: json['can_perform_all'] == true,
      );
}

/// Everything the confirm screen needs after a scan.
class CheckInTarget {
  final CheckInAppointment appointment;
  final Bill bill;
  final List<ProviderOption> providers;
  final String? defaultServingProviderId;
  final bool canStart;
  final String? blockedReason;

  CheckInTarget({
    required this.appointment,
    required this.bill,
    required this.providers,
    this.defaultServingProviderId,
    required this.canStart,
    this.blockedReason,
  });

  factory CheckInTarget.fromJson(Map<String, dynamic> json) => CheckInTarget(
        appointment: CheckInAppointment.fromJson(json['appointment']),
        bill: Bill.fromJson(json['bill'] ?? const {}),
        providers: ((json['providers'] as List?) ?? [])
            .map((e) => ProviderOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        defaultServingProviderId: json['default_serving_provider_id']?.toString(),
        canStart: json['can_start'] == true,
        blockedReason: json['blocked_reason'],
      );
}
