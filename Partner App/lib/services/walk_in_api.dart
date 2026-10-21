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

  /// History of walk-in customers with metrics, search and filters.
  static Future<WalkInHistoryResponse> history(
    String salonId, {
    String? search,
    String? date,
    String? status,
    String? scope,
    String? providerId,
    int page = 1,
    int perPage = 50,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (date != null && date.isNotEmpty) 'date': date,
      if (status != null && status.isNotEmpty) 'status': status,
      if (scope != null && scope.isNotEmpty) 'scope': scope,
      if (providerId != null && providerId.isNotEmpty) 'provider_id': providerId,
    };

    final uri = Uri.parse('$_baseUrl/salons/$salonId/walk-in/history')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _headers());

    if (response.statusCode == 200) {
      return WalkInHistoryResponse.fromJson(jsonDecode(response.body));
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

class WalkInHistoryResponse {
  final WalkInHistorySummary summary;
  final List<WalkInHistoryItem> walkIns;
  final int currentPage;
  final int lastPage;
  final int total;
  final String? viewerRole;
  final String? viewerProviderId;

  WalkInHistoryResponse({
    required this.summary,
    required this.walkIns,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.viewerRole,
    this.viewerProviderId,
  });

  factory WalkInHistoryResponse.fromJson(Map<String, dynamic> json) {
    final pag = json['pagination'] as Map<String, dynamic>? ?? {};
    final viewer = json['viewer'] as Map<String, dynamic>? ?? {};
    return WalkInHistoryResponse(
      summary: WalkInHistorySummary.fromJson(json['summary'] as Map<String, dynamic>? ?? {}),
      walkIns: ((json['walk_ins'] as List?) ?? [])
          .map((e) => WalkInHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentPage: pag['current_page'] ?? 1,
      lastPage: pag['last_page'] ?? 1,
      total: pag['total'] ?? 0,
      viewerRole: viewer['role']?.toString(),
      viewerProviderId: viewer['provider_id']?.toString(),
    );
  }
}

class WalkInHistorySummary {
  final int totalWalkIns;
  final int todayWalkIns;
  final int inProgress;
  final int completed;
  final double totalRevenue;

  WalkInHistorySummary({
    required this.totalWalkIns,
    required this.todayWalkIns,
    required this.inProgress,
    required this.completed,
    required this.totalRevenue,
  });

  factory WalkInHistorySummary.fromJson(Map<String, dynamic> json) => WalkInHistorySummary(
        totalWalkIns: json['total_walk_ins'] ?? 0,
        todayWalkIns: json['today_walk_ins'] ?? 0,
        inProgress: json['in_progress'] ?? 0,
        completed: json['completed'] ?? 0,
        totalRevenue: double.tryParse('${json['total_revenue'] ?? 0}') ?? 0.0,
      );
}

class WalkInHistoryItem {
  final String id;
  final String status;
  final String bookingSource;
  final String appointmentDate;
  final String startTime;
  final String endTime;
  final String? startedAt;
  final String? completedAt;
  final String customerName;
  final String customerPhone;
  final String? customerGender;
  final String? appointedProviderName;
  final String? servingProviderName;
  final List<WalkInHistoryServiceLine> services;
  final List<WalkInHistoryAdditionLine> serviceAdditions;
  final double totalAmount;
  final double advanceAmount;
  final double balanceAmount;
  final double? finalBilledAmount;
  final String? paymentMode;
  final String? paymentCollectedAt;
  final String? paymentCollectedByName;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? manualCheckInReason;

  WalkInHistoryItem({
    required this.id,
    required this.status,
    required this.bookingSource,
    required this.appointmentDate,
    required this.startTime,
    required this.endTime,
    this.startedAt,
    this.completedAt,
    required this.customerName,
    required this.customerPhone,
    this.customerGender,
    this.appointedProviderName,
    this.servingProviderName,
    required this.services,
    required this.serviceAdditions,
    required this.totalAmount,
    required this.advanceAmount,
    required this.balanceAmount,
    this.finalBilledAmount,
    this.paymentMode,
    this.paymentCollectedAt,
    this.paymentCollectedByName,
    this.invoiceId,
    this.invoiceNumber,
    this.manualCheckInReason,
  });

  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isScheduled => status == 'scheduled';
  bool get isCancelled => status == 'cancelled' || status == 'no_show';
  bool get hasBalance => balanceAmount > 0;

  double get displayAmount => finalBilledAmount ?? totalAmount;

  factory WalkInHistoryItem.fromJson(Map<String, dynamic> json) {
    final appProvider = json['appointed_provider'] as Map<String, dynamic>?;
    final servProvider = json['serving_provider'] as Map<String, dynamic>?;

    return WalkInHistoryItem(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'scheduled',
      bookingSource: json['booking_source']?.toString() ?? 'walk_in',
      appointmentDate: json['appointment_date']?.toString() ?? '',
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
      startedAt: json['started_at']?.toString(),
      completedAt: json['completed_at']?.toString(),
      customerName: json['customer_name']?.toString() ?? 'Walk-in',
      customerPhone: json['customer_phone']?.toString() ?? '',
      customerGender: json['customer_gender']?.toString(),
      appointedProviderName: appProvider?['name']?.toString(),
      servingProviderName: servProvider?['name']?.toString(),
      services: ((json['services'] as List?) ?? [])
          .map((e) => WalkInHistoryServiceLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      serviceAdditions: ((json['service_additions'] as List?) ?? [])
          .map((e) => WalkInHistoryAdditionLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalAmount: double.tryParse('${json['total_amount'] ?? 0}') ?? 0.0,
      advanceAmount: double.tryParse('${json['advance_amount'] ?? 0}') ?? 0.0,
      balanceAmount: double.tryParse('${json['balance_amount'] ?? 0}') ?? 0.0,
      finalBilledAmount: json['final_billed_amount'] != null
          ? double.tryParse('${json['final_billed_amount']}')
          : null,
      paymentMode: json['payment_mode']?.toString(),
      paymentCollectedAt: json['payment_collected_at']?.toString(),
      paymentCollectedByName: json['payment_collected_by_name']?.toString(),
      invoiceId: json['invoice_id']?.toString(),
      invoiceNumber: json['invoice_number']?.toString(),
      manualCheckInReason: json['manual_check_in_reason']?.toString(),
    );
  }
}

class WalkInHistoryServiceLine {
  final String id;
  final String name;
  final String category;
  final double price;
  final int durationMinutes;
  final String? servingProviderName;
  final String? lineStatus;

  WalkInHistoryServiceLine({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.durationMinutes,
    this.servingProviderName,
    this.lineStatus,
  });

  factory WalkInHistoryServiceLine.fromJson(Map<String, dynamic> json) => WalkInHistoryServiceLine(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Service',
        category: json['category']?.toString() ?? 'General',
        price: double.tryParse('${json['price'] ?? 0}') ?? 0.0,
        durationMinutes: json['duration_minutes'] ?? 0,
        servingProviderName: json['serving_provider_name']?.toString(),
        lineStatus: json['line_status']?.toString(),
      );
}

class WalkInHistoryAdditionLine {
  final String id;
  final String name;
  final double price;
  final int durationMinutes;
  final String? providerName;
  final String? addedByName;
  final String status;
  final String? addedAt;

  WalkInHistoryAdditionLine({
    required this.id,
    required this.name,
    required this.price,
    required this.durationMinutes,
    this.providerName,
    this.addedByName,
    required this.status,
    this.addedAt,
  });

  factory WalkInHistoryAdditionLine.fromJson(Map<String, dynamic> json) =>
      WalkInHistoryAdditionLine(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Additional Service',
        price: double.tryParse('${json['price'] ?? 0}') ?? 0.0,
        durationMinutes: json['duration_minutes'] ?? 0,
        providerName: json['provider_name']?.toString(),
        addedByName: json['added_by_name']?.toString(),
        status: json['status']?.toString() ?? 'active',
        addedAt: json['added_at']?.toString(),
      );
}

