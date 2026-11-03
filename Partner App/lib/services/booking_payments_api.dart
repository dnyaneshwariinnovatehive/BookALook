import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// One payment on a booking: taken online (in the past) or recorded by the salon.
class BookingPayment {
  final String id;
  final double amount;
  final String type;
  final String mode;
  final String source;
  final String? reference;
  final String? note;
  final DateTime? paidAt;

  const BookingPayment({
    required this.id,
    required this.amount,
    required this.type,
    required this.mode,
    required this.source,
    this.reference,
    this.note,
    this.paidAt,
  });

  factory BookingPayment.fromJson(Map<String, dynamic> j) => BookingPayment(
        id: j['id'].toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        type: j['type']?.toString() ?? 'other',
        mode: j['mode']?.toString() ?? 'cash',
        source: j['source']?.toString() ?? 'recorded',
        reference: j['reference']?.toString(),
        note: j['note']?.toString(),
        paidAt: DateTime.tryParse(j['paid_at']?.toString() ?? '')?.toLocal(),
      );
}

/// Money owed back to a customer after a cancellation.
class BookingRefund {
  final String id;
  final double amount;
  final String status;

  /// `salon` when the salon took the money and gives it back itself;
  /// `bookalook` when BookALook does.
  final String? returnedBy;
  final String? reason;

  const BookingRefund({required this.id, required this.amount, required this.status, this.returnedBy, this.reason});

  bool get isDone => status == 'processed';
  bool get salonReturns => returnedBy == 'salon' && !isDone;

  factory BookingRefund.fromJson(Map<String, dynamic> j) => BookingRefund(
        id: j['id'].toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        status: j['status']?.toString() ?? 'pending',
        returnedBy: j['returned_by']?.toString(),
        reason: j['reason']?.toString(),
      );
}

/// Where a booking stands for money.
class PaymentLedger {
  final double total;
  final double advanceDue;
  final double advancePaid;
  final double advanceOutstanding;
  final double paid;
  final double outstanding;

  /// `paid`, `partially_paid`, `unpaid` or `not_required`.
  final String status;
  final List<BookingPayment> payments;
  final List<BookingRefund> refunds;
  final List<String> modes;

  const PaymentLedger({
    required this.total,
    required this.advanceDue,
    required this.advancePaid,
    required this.advanceOutstanding,
    required this.paid,
    required this.outstanding,
    required this.status,
    this.payments = const [],
    this.refunds = const [],
    this.modes = const ['cash', 'upi', 'card', 'bank_transfer', 'other'],
  });

  String get statusLabel => switch (status) {
        'paid' => 'Paid',
        'partially_paid' => 'Partly paid',
        'not_required' => 'Nothing to pay',
        _ => 'Unpaid',
      };

  factory PaymentLedger.fromJson(Map<String, dynamic> j) {
    final s = (j['summary'] as Map?) ?? const {};
    double d(String k) => (s[k] as num?)?.toDouble() ?? 0;
    return PaymentLedger(
      total: d('total'),
      advanceDue: d('advance_due'),
      advancePaid: d('advance_paid'),
      advanceOutstanding: d('advance_outstanding'),
      paid: d('paid'),
      outstanding: d('outstanding'),
      status: s['status']?.toString() ?? 'unpaid',
      payments: ((j['payments'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BookingPayment.fromJson)
          .toList(),
      refunds: ((j['refunds'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BookingRefund.fromJson)
          .toList(),
      modes: ((j['modes'] as List?) ?? const ['cash', 'upi', 'card', 'bank_transfer', 'other'])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Payments the customer made to the salon, recorded by the salon. There is
/// no online payment gateway, so this is how a booking becomes paid.
class BookingPaymentsApi {
  static String _base(String salonId, String appointmentId) =>
      '${ApiConfig.baseUrl}/partner/salons/$salonId/appointments/$appointmentId';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<PaymentLedger> fetch(String salonId, String appointmentId) async {
    final r = await http.get(Uri.parse('${_base(salonId, appointmentId)}/payments'), headers: await _headers());
    if (r.statusCode == 200) return PaymentLedger.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception(_error(r, 'Could not load payments.'));
  }

  static Future<PaymentLedger> record(
    String salonId,
    String appointmentId, {
    required double amount,
    required String type,
    required String mode,
    String? reference,
    String? note,
  }) async {
    final r = await http.post(
      Uri.parse('${_base(salonId, appointmentId)}/payments'),
      headers: await _headers(),
      body: jsonEncode({
        'amount': amount,
        'type': type,
        'mode': mode,
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (note != null && note.isNotEmpty) 'note': note,
      }),
    );
    if (r.statusCode == 201) return PaymentLedger.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception(_error(r, 'Could not record the payment.'));
  }

  static Future<PaymentLedger> refundReturned(String salonId, String appointmentId, String refundId) async {
    final r = await http.post(
      Uri.parse('${_base(salonId, appointmentId)}/refunds/$refundId/returned'),
      headers: await _headers(),
    );
    if (r.statusCode == 200) return PaymentLedger.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    throw Exception(_error(r, 'Could not mark the refund returned.'));
  }

  static String _error(http.Response r, String fallback) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['errors'] is Map) {
        final first = (body['errors'] as Map).values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      if (body is Map && body['message'] != null) return body['message'].toString();
    } catch (_) {}
    return fallback;
  }
}
