import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

/// What the salon's bookings say about it.
///
/// The server decides how much of this a plan may see and returns the rest as
/// a list of locked sections rather than leaving them out. The screen draws
/// those greyed out, because a salon cannot want an upgrade whose value it has
/// never been shown.
class InsightsApi {
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

  static Future<SalonInsights> fetch(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/insights'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return SalonInsights.fromJson(jsonDecode(response.body));
    }

    // Carry the server's own words up to the screen. A flat "could not load"
    // sends whoever is debugging this to the logs to find out something the
    // response already said.
    throw InsightsUnavailable(_reasonFrom(response.statusCode, response.body));
  }

  static String _reasonFrom(int status, String body) {
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) return 'This account cannot see insights for that salon.';
    if (status == 404) return 'That salon could not be found.';

    try {
      final message = (jsonDecode(body) as Map)['message'];
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {
      // Not JSON — a proxy error page or a crash dump. Fall through.
    }

    return 'The server could not build your insights (error $status).';
  }
}

class InsightsUnavailable implements Exception {
  final String message;

  InsightsUnavailable(this.message);

  @override
  String toString() => message;
}

class SalonInsights {
  final String? planName;
  final bool advanced;

  final Overview overview;
  final List<ServiceStat> services;
  final CampaignStats campaigns;

  final RepeatCustomers? repeatCustomers;
  final PeakHours? peakHours;
  final List<AreaStat> areas;
  final List<ComboSuggestion> recommendedCombos;
  final List<UpsellTip> upsell;
  final List<PairStat> crossSell;

  final List<LockedSection> locked;

  SalonInsights({
    required this.overview,
    required this.services,
    required this.campaigns,
    required this.advanced,
    this.planName,
    this.repeatCustomers,
    this.peakHours,
    this.areas = const [],
    this.recommendedCombos = const [],
    this.upsell = const [],
    this.crossSell = const [],
    this.locked = const [],
  });

  factory SalonInsights.fromJson(Map<String, dynamic> json) {
    final d = json['data'] ?? {};

    return SalonInsights(
      planName: d['plan_name'],
      advanced: d['advanced'] == true,
      overview: Overview.fromJson(d['overview'] ?? {}),
      services: ((d['services'] ?? []) as List).map((r) => ServiceStat.fromJson(r)).toList(),
      campaigns: CampaignStats.fromJson(d['campaigns'] ?? {}),
      repeatCustomers:
          d['repeat_customers'] == null ? null : RepeatCustomers.fromJson(d['repeat_customers']),
      peakHours: d['peak_hours'] == null ? null : PeakHours.fromJson(d['peak_hours']),
      areas: (((d['areas'] ?? {})['areas'] ?? []) as List)
          .map((r) => AreaStat.fromJson(r))
          .toList(),
      recommendedCombos: ((d['recommended_combos'] ?? []) as List)
          .map((r) => ComboSuggestion.fromJson(r))
          .toList(),
      upsell: ((d['upsell'] ?? []) as List).map((r) => UpsellTip.fromJson(r)).toList(),
      crossSell: ((d['cross_sell'] ?? []) as List).map((r) => PairStat.fromJson(r)).toList(),
      locked: ((json['locked'] ?? []) as List).map((r) => LockedSection.fromJson(r)).toList(),
    );
  }
}

class Overview {
  final int customers;
  final int returningCustomers;
  final double repeatRate;
  final int totalVisits;
  final double revenue;
  final double averageBill;
  final double averageVisits;

  Overview({
    this.customers = 0,
    this.returningCustomers = 0,
    this.repeatRate = 0,
    this.totalVisits = 0,
    this.revenue = 0,
    this.averageBill = 0,
    this.averageVisits = 0,
  });

  factory Overview.fromJson(Map<String, dynamic> json) => Overview(
        customers: json['customers'] ?? 0,
        returningCustomers: json['returning_customers'] ?? 0,
        repeatRate: (json['repeat_rate'] as num?)?.toDouble() ?? 0,
        totalVisits: json['total_visits'] ?? 0,
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
        averageBill: (json['average_bill'] as num?)?.toDouble() ?? 0,
        averageVisits: (json['average_visits_per_customer'] as num?)?.toDouble() ?? 0,
      );
}

class ServiceStat {
  final String name;
  final int bookings;
  final double revenue;

  ServiceStat({required this.name, required this.bookings, required this.revenue});

  factory ServiceStat.fromJson(Map<String, dynamic> json) => ServiceStat(
        name: json['name'] ?? '',
        bookings: json['bookings'] ?? 0,
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      );
}

class CampaignStats {
  final int campaigns;
  final int sent;
  final int delivered;
  final int read;
  final double? readRate;

  CampaignStats({
    this.campaigns = 0,
    this.sent = 0,
    this.delivered = 0,
    this.read = 0,
    this.readRate,
  });

  factory CampaignStats.fromJson(Map<String, dynamic> json) => CampaignStats(
        campaigns: json['campaigns'] ?? 0,
        sent: json['sent'] ?? 0,
        delivered: json['delivered'] ?? 0,
        read: json['read'] ?? 0,
        readRate: (json['read_rate'] as num?)?.toDouble(),
      );
}

class RepeatCustomers {
  final List<({String label, int count})> buckets;
  final int atRisk;
  final int atRiskAfterDays;
  final List<TopCustomer> top;

  RepeatCustomers({
    required this.buckets,
    required this.atRisk,
    required this.atRiskAfterDays,
    required this.top,
  });

  factory RepeatCustomers.fromJson(Map<String, dynamic> json) => RepeatCustomers(
        buckets: ((json['buckets'] ?? []) as List)
            .map((r) => (label: (r['label'] ?? '').toString(), count: (r['count'] ?? 0) as int))
            .toList(),
        atRisk: json['at_risk'] ?? 0,
        atRiskAfterDays: json['at_risk_after_days'] ?? 60,
        top: ((json['top_customers'] ?? []) as List).map((r) => TopCustomer.fromJson(r)).toList(),
      );
}

class TopCustomer {
  final String name;
  final int visits;
  final double spend;

  TopCustomer({required this.name, required this.visits, required this.spend});

  factory TopCustomer.fromJson(Map<String, dynamic> json) => TopCustomer(
        name: json['name'] ?? '',
        visits: json['visits'] ?? 0,
        spend: (json['spend'] as num?)?.toDouble() ?? 0,
      );
}

class PeakHours {
  final List<({int hour, String label, int bookings})> byHour;
  final List<({String day, int bookings})> byDay;
  final String? busiest;
  final String? quietest;
  final String? quietestDay;

  /// Days with no bookings at all — almost always closing days rather than
  /// slow ones, and shown as such instead of as an empty bar.
  final List<String> closedDays;

  PeakHours({
    required this.byHour,
    required this.byDay,
    this.busiest,
    this.quietest,
    this.quietestDay,
    this.closedDays = const [],
  });

  factory PeakHours.fromJson(Map<String, dynamic> json) => PeakHours(
        byHour: ((json['by_hour'] ?? []) as List)
            .map((r) => (
                  hour: (r['hour'] ?? 0) as int,
                  label: (r['label'] ?? '').toString(),
                  bookings: (r['bookings'] ?? 0) as int
                ))
            .toList(),
        byDay: ((json['by_day'] ?? []) as List)
            .map((r) =>
                (day: (r['day'] ?? '').toString(), bookings: (r['bookings'] ?? 0) as int))
            .toList(),
        busiest: json['busiest_hour'],
        quietest: json['quietest_hour'],
        quietestDay: json['quietest_day'],
        closedDays:
            ((json['closed_days'] ?? []) as List).map((d) => d.toString()).toList(),
      );
}

class AreaStat {
  final String? subAreaId;
  final String area;
  final int customers;

  AreaStat({required this.area, required this.customers, this.subAreaId});

  factory AreaStat.fromJson(Map<String, dynamic> json) => AreaStat(
        subAreaId: json['sub_area_id'],
        area: json['area'] ?? '',
        customers: json['customers'] ?? 0,
      );
}

class UpsellTip {
  final String from;
  final String to;
  final double uplift;
  final int evidence;

  UpsellTip({required this.from, required this.to, required this.uplift, required this.evidence});

  factory UpsellTip.fromJson(Map<String, dynamic> json) => UpsellTip(
        from: json['from'] ?? '',
        to: json['to'] ?? '',
        uplift: (json['uplift'] as num?)?.toDouble() ?? 0,
        evidence: json['evidence'] ?? 0,
      );
}

class PairStat {
  final List<String> services;

  /// The salon's own service rows, so a pair can be turned into a combo
  /// without the owner having to find them again in a list.
  final List<String> serviceIds;
  final int bookedTogether;
  final bool alreadyACombo;

  PairStat({
    required this.services,
    required this.bookedTogether,
    this.serviceIds = const [],
    this.alreadyACombo = false,
  });

  factory PairStat.fromJson(Map<String, dynamic> json) => PairStat(
        services: ((json['services'] ?? []) as List).map((s) => s.toString()).toList(),
        serviceIds:
            ((json['service_ids'] ?? []) as List).map((s) => s.toString()).toList(),
        bookedTogether: json['booked_together'] ?? 0,
        alreadyACombo: json['already_a_combo'] == true,
      );

  /// Only offerable when the pair is not already packaged and both services
  /// came back identified.
  bool get canBecomeCombo => !alreadyACombo && serviceIds.length >= 2;

  String get comboName => services.join(' + ');
}

/// A pair worth packaging, with the words to explain why.
class ComboSuggestion {
  final List<String> services;
  final List<String> serviceIds;
  final String suggestion;

  ComboSuggestion({
    required this.services,
    required this.serviceIds,
    required this.suggestion,
  });

  factory ComboSuggestion.fromJson(Map<String, dynamic> json) => ComboSuggestion(
        services: ((json['services'] ?? []) as List).map((s) => s.toString()).toList(),
        serviceIds:
            ((json['service_ids'] ?? []) as List).map((s) => s.toString()).toList(),
        suggestion: (json['suggestion'] ?? '').toString(),
      );

  bool get isActionable => serviceIds.length >= 2;

  String get comboName => services.join(' + ');
}

class LockedSection {
  final String key;
  final String name;
  final String reason;

  LockedSection({required this.key, required this.name, required this.reason});

  factory LockedSection.fromJson(Map<String, dynamic> json) => LockedSection(
        key: json['key'] ?? '',
        name: json['name'] ?? '',
        reason: json['reason'] ?? '',
      );
}
