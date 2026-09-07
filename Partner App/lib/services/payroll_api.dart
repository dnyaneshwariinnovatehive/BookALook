import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

/// Monthly staff pay, and the salon's own copy of the weekly settlement.
class PayrollApi {
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

  /// Every staff member's pay for [month] (YYYY-MM).
  static Future<PayrollMonth> forSalon(String salonId, String month) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/payroll?month=$month'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return PayrollMonth.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  /// The signed-in staff member's own payslip, plus earlier months.
  static Future<MyPayroll> mine(String month) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/me/payroll?month=$month'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return MyPayroll.fromJson(jsonDecode(response.body));
    }
    throw Exception(_errorFrom(response));
  }

  /// One staff member's payslip with the service lines behind the commission.
  static Future<Payslip> forStaff(String salonId, String providerId, String month) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/payroll/staff/$providerId?month=$month'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return Payslip.fromJson(jsonDecode(response.body)['payslip']);
    }
    throw Exception(_errorFrom(response));
  }

  static Future<Payslip> setPaid(
    String salonId,
    String payslipId, {
    required bool paid,
    String? reference,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/payroll/$payslipId/${paid ? 'mark-paid' : 'mark-unpaid'}'),
      headers: await _headers(),
      body: jsonEncode({
        if (paid && reference != null && reference.isNotEmpty) 'payment_reference': reference,
      }),
    );

    if (response.statusCode == 200) {
      return Payslip.fromJson(jsonDecode(response.body)['payslip']);
    }
    throw Exception(_errorFrom(response));
  }

  /// What the platform settled with this salon, week by week.
  static Future<SalonPayouts> salonPayouts(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/payouts'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return SalonPayouts.fromJson(jsonDecode(response.body));
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

double _num(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;

/// One commission-earning service line.
class CommissionLine {
  final String date;
  final String service;
  final String source;
  final double charged;
  final double rate;
  final double commission;
  final bool addedMidAppointment;

  CommissionLine({
    required this.date,
    required this.service,
    required this.source,
    required this.charged,
    required this.rate,
    required this.commission,
    required this.addedMidAppointment,
  });

  factory CommissionLine.fromJson(Map<String, dynamic> json) => CommissionLine(
        date: json['date'] ?? '',
        service: json['service'] ?? 'Service',
        source: json['source'] ?? '',
        charged: _num(json['charged']),
        rate: _num(json['rate']),
        commission: _num(json['commission']),
        addedMidAppointment: json['added_mid_appointment'] == true,
      );
}

class Payslip {
  final String id;
  final String providerId;
  final String providerName;
  final String monthLabel;

  final double baseSalary;
  final int workingDays;
  final double dailyRate;

  final double paidLeaveDays;
  final double unpaidLeaveDays;
  final double unpaidLeaveDeduction;

  final double commissionPercentage;
  final double commissionEarned;
  final double otherAdjustments;
  final double totalPayable;

  final String status;
  final String? paymentReference;
  final List<CommissionLine> commissionLines;

  Payslip({
    required this.id,
    required this.providerId,
    required this.providerName,
    required this.monthLabel,
    required this.baseSalary,
    required this.workingDays,
    required this.dailyRate,
    required this.paidLeaveDays,
    required this.unpaidLeaveDays,
    required this.unpaidLeaveDeduction,
    required this.commissionPercentage,
    required this.commissionEarned,
    required this.otherAdjustments,
    required this.totalPayable,
    required this.status,
    this.paymentReference,
    this.commissionLines = const [],
  });

  bool get isPaid => status == 'paid';

  factory Payslip.fromJson(Map<String, dynamic> json) => Payslip(
        id: json['id'].toString(),
        providerId: json['provider_id'].toString(),
        providerName: json['provider_name'] ?? 'Staff',
        monthLabel: json['month_label'] ?? '',
        baseSalary: _num(json['base_salary']),
        workingDays: json['working_days_in_month'] ?? 0,
        dailyRate: _num(json['daily_rate']),
        paidLeaveDays: _num(json['paid_leave_days']),
        unpaidLeaveDays: _num(json['unpaid_leave_days']),
        unpaidLeaveDeduction: _num(json['unpaid_leave_deduction']),
        commissionPercentage: _num(json['commission_percentage']),
        commissionEarned: _num(json['commission_earned']),
        otherAdjustments: _num(json['other_adjustments']),
        totalPayable: _num(json['total_payable']),
        status: json['status'] ?? 'pending',
        paymentReference: json['payment_reference'],
        commissionLines: ((json['commission_lines'] as List?) ?? [])
            .map((e) => CommissionLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PayrollMonth {
  final String monthLabel;
  final int staff;
  final double baseSalary;
  final double commission;
  final double deductions;
  final double payable;
  final double paid;
  final List<Payslip> payslips;

  PayrollMonth({
    required this.monthLabel,
    required this.staff,
    required this.baseSalary,
    required this.commission,
    required this.deductions,
    required this.payable,
    required this.paid,
    required this.payslips,
  });

  factory PayrollMonth.fromJson(Map<String, dynamic> json) {
    final totals = (json['totals'] as Map<String, dynamic>?) ?? const {};

    return PayrollMonth(
      monthLabel: json['month_label'] ?? '',
      staff: totals['staff'] ?? 0,
      baseSalary: _num(totals['base_salary']),
      commission: _num(totals['commission']),
      deductions: _num(totals['deductions']),
      payable: _num(totals['payable']),
      paid: _num(totals['paid']),
      payslips: ((json['payslips'] as List?) ?? [])
          .map((e) => Payslip.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MyPayroll {
  final Payslip current;
  final List<Payslip> history;

  MyPayroll({required this.current, required this.history});

  factory MyPayroll.fromJson(Map<String, dynamic> json) => MyPayroll(
        current: Payslip.fromJson(json['payslip']),
        history: ((json['history'] as List?) ?? [])
            .map((e) => Payslip.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SalonPayoutRecord {
  final String weekStart;
  final String weekEnd;
  final int appointments;
  final double revenue;
  final double advancesHeld;
  final String billingType;
  final double commissionPercentage;
  final double commissionDeducted;
  final double walletRedeemed;
  final double netAmount;
  final String status;
  final String? reference;

  SalonPayoutRecord({
    required this.weekStart,
    required this.weekEnd,
    required this.appointments,
    required this.revenue,
    required this.advancesHeld,
    required this.billingType,
    required this.commissionPercentage,
    required this.commissionDeducted,
    required this.walletRedeemed,
    required this.netAmount,
    required this.status,
    this.reference,
  });

  factory SalonPayoutRecord.fromJson(Map<String, dynamic> json) => SalonPayoutRecord(
        weekStart: json['cycle_week_start_date'] ?? '',
        weekEnd: json['cycle_week_end_date'] ?? '',
        appointments: json['appointments_count'] ?? 0,
        revenue: _num(json['appointment_revenue']),
        advancesHeld: _num(json['gross_amount']),
        billingType: json['billing_type'] ?? 'flat',
        commissionPercentage: _num(json['commission_percentage']),
        commissionDeducted: _num(json['commission_deducted']),
        walletRedeemed: _num(json['wallet_redeemed_amount']),
        netAmount: _num(json['net_amount']),
        status: json['status'] ?? 'pending',
        reference: json['distribution_reference'],
      );
}

class SalonPayouts {
  final double commissionLifetime;
  final double receivedLifetime;
  final List<SalonPayoutRecord> payouts;

  SalonPayouts({
    required this.commissionLifetime,
    required this.receivedLifetime,
    required this.payouts,
  });

  factory SalonPayouts.fromJson(Map<String, dynamic> json) {
    final totals = (json['totals'] as Map<String, dynamic>?) ?? const {};

    return SalonPayouts(
      commissionLifetime: _num(totals['commission_deducted_lifetime']),
      receivedLifetime: _num(totals['received_lifetime']),
      payouts: ((json['payouts'] as List?) ?? [])
          .map((e) => SalonPayoutRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
