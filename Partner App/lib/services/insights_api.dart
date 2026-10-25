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

  /// [days] picks the history window. Only Growth may change it; the server
  /// falls back to 30 for any other plan.
  static Future<SalonInsights> fetch(String salonId, {int days = 30}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/insights?days=$days'),
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

  final BasicAnalytics? basicAnalytics;
  final RetentionFunnel? retentionFunnel;

  final RepeatCustomers? repeatCustomers;
  final PeakHours? peakHours;
  final List<AreaStat> areas;
  final List<ComboSuggestion> recommendedCombos;
  final List<UpsellTip> upsell;
  final List<PairStat> crossSell;

  /// History windows this plan may switch between; just [30] below Growth.
  final List<int> periods;
  final PeriodComparison? period;
  final GenderMix? genderMix;
  final VisitGap? visitGap;
  final List<StaffDeepDive> staffDeepDive;
  final List<UpsellLinkStat> upsellLinks;
  final List<QuietHourOffer> quietHourOffers;
  final List<SlowService> slowServices;
  final List<WinBackCustomer> winBack;

  final List<LockedSection> locked;

  /// Whether the plan hides [key], so the screen draws it as a locked card.
  bool isLocked(String key) => locked.any((l) => l.key == key);

  SalonInsights({
    required this.overview,
    required this.services,
    required this.campaigns,
    required this.advanced,
    this.planName,
    this.basicAnalytics,
    this.retentionFunnel,
    this.repeatCustomers,
    this.peakHours,
    this.areas = const [],
    this.recommendedCombos = const [],
    this.upsell = const [],
    this.crossSell = const [],
    this.periods = const [30],
    this.period,
    this.genderMix,
    this.visitGap,
    this.staffDeepDive = const [],
    this.upsellLinks = const [],
    this.quietHourOffers = const [],
    this.slowServices = const [],
    this.winBack = const [],
    this.locked = const [],
  });

  factory SalonInsights.fromJson(Map<String, dynamic> json) {
    final d = json['data'] ?? {};

    return SalonInsights(
      planName: d['plan_name'],
      advanced: d['advanced'] == true,
      overview: Overview.fromJson(Map<String, dynamic>.from((d['overview'] ?? {}) as Map)),
      services: ((d['services'] ?? []) as List)
          .map((r) => ServiceStat.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList(),
      campaigns: CampaignStats.fromJson(Map<String, dynamic>.from((d['campaigns'] ?? {}) as Map)),
      basicAnalytics: d['basic_analytics'] == null
          ? null
          : BasicAnalytics.fromJson(Map<String, dynamic>.from(d['basic_analytics'] as Map)),
      retentionFunnel: d['retention_funnel'] == null
          ? null
          : RetentionFunnel.fromJson(Map<String, dynamic>.from(d['retention_funnel'] as Map)),
      repeatCustomers: d['repeat_customers'] == null
          ? null
          : RepeatCustomers.fromJson(Map<String, dynamic>.from(d['repeat_customers'] as Map)),
      peakHours: d['peak_hours'] == null
          ? null
          : PeakHours.fromJson(Map<String, dynamic>.from(d['peak_hours'] as Map)),
      areas: (((d['areas'] ?? {})['areas'] ?? []) as List)
          .map((r) => AreaStat.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList(),
      recommendedCombos: ((d['recommended_combos'] ?? []) as List)
          .map((r) => ComboSuggestion.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList(),
      upsell: ((d['upsell'] ?? []) as List)
          .map((r) => UpsellTip.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList(),
      crossSell: ((d['cross_sell'] ?? []) as List)
          .map((r) => PairStat.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList(),
      periods: ((d['periods'] ?? [30]) as List).map((p) => (p as num).toInt()).toList(),
      period: d['period'] == null
          ? null
          : PeriodComparison.fromJson(Map<String, dynamic>.from(d['period'] as Map)),
      genderMix: d['gender_mix'] == null
          ? null
          : GenderMix.fromJson(Map<String, dynamic>.from(d['gender_mix'] as Map)),
      visitGap: d['visit_gap'] == null
          ? null
          : VisitGap.fromJson(Map<String, dynamic>.from(d['visit_gap'] as Map)),
      staffDeepDive: _list(d['staff_deep_dive'], StaffDeepDive.fromJson),
      upsellLinks: _list(d['upsell_links'], UpsellLinkStat.fromJson),
      quietHourOffers: _list(d['quiet_hour_offers'], QuietHourOffer.fromJson),
      slowServices: _list(d['slow_services'], SlowService.fromJson),
      winBack: _list(d['win_back'], WinBackCustomer.fromJson),
      locked: ((json['locked'] ?? []) as List)
          .map((r) => LockedSection.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList(),
    );
  }
}

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) =>
    ((raw ?? []) as List).map((r) => parse(Map<String, dynamic>.from(r as Map))).toList();

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// One figure in this period against the same length of time before it.
class PeriodMetric {
  final double current;
  final double previous;

  /// Null when there was nothing before; growth from zero is not a percentage.
  final double? changePercent;

  PeriodMetric({required this.current, required this.previous, this.changePercent});

  factory PeriodMetric.fromJson(Map<String, dynamic> json) => PeriodMetric(
        current: _num(json['current']),
        previous: _num(json['previous']),
        changePercent: (json['change_percent'] as num?)?.toDouble(),
      );
}

class PeriodComparison {
  final int days;
  final PeriodMetric revenue;
  final PeriodMetric visits;
  final PeriodMetric customers;
  final PeriodMetric averageBill;

  PeriodComparison({
    required this.days,
    required this.revenue,
    required this.visits,
    required this.customers,
    required this.averageBill,
  });

  factory PeriodComparison.fromJson(Map<String, dynamic> json) {
    final m = Map<String, dynamic>.from((json['metrics'] ?? {}) as Map);
    PeriodMetric metric(String key) =>
        PeriodMetric.fromJson(Map<String, dynamic>.from((m[key] ?? {}) as Map));
    return PeriodComparison(
      days: _int(json['days']),
      revenue: metric('revenue'),
      visits: metric('visits'),
      customers: metric('customers'),
      averageBill: metric('average_bill'),
    );
  }
}

class GenderSplit {
  final String name;
  final int male;
  final int female;
  final int unknown;

  GenderSplit({required this.name, required this.male, required this.female, required this.unknown});

  int get total => male + female + unknown;

  factory GenderSplit.fromJson(Map<String, dynamic> json) => GenderSplit(
        name: (json['name'] ?? 'All services').toString(),
        male: _int(json['male']),
        female: _int(json['female']),
        unknown: _int(json['unknown']),
      );
}

class GenderMix {
  final GenderSplit overall;
  final List<GenderSplit> services;

  GenderMix({required this.overall, required this.services});

  factory GenderMix.fromJson(Map<String, dynamic> json) => GenderMix(
        overall: GenderSplit.fromJson(Map<String, dynamic>.from((json['overall'] ?? {}) as Map)),
        services: _list(json['services'], GenderSplit.fromJson),
      );
}

class VisitGap {
  final double averageBill;
  final double highestBill;
  final int? averageGapDays;
  final int? medianGapDays;

  VisitGap({required this.averageBill, required this.highestBill, this.averageGapDays, this.medianGapDays});

  factory VisitGap.fromJson(Map<String, dynamic> json) => VisitGap(
        averageBill: _num(json['average_bill']),
        highestBill: _num(json['highest_bill']),
        averageGapDays: (json['average_gap_days'] as num?)?.toInt(),
        medianGapDays: (json['median_gap_days'] as num?)?.toInt(),
      );
}

class StaffDeepDive {
  final String name;
  final int completed;
  final double revenue;
  final double averageBill;
  final double repeatRate;
  final int noShows;

  StaffDeepDive({
    required this.name,
    required this.completed,
    required this.revenue,
    required this.averageBill,
    required this.repeatRate,
    required this.noShows,
  });

  factory StaffDeepDive.fromJson(Map<String, dynamic> json) => StaffDeepDive(
        name: (json['name'] ?? 'Staff').toString(),
        completed: _int(json['completed']),
        revenue: _num(json['revenue']),
        averageBill: _num(json['average_bill']),
        repeatRate: _num(json['repeat_rate']),
        noShows: _int(json['no_shows']),
      );
}

class UpsellLinkStat {
  final String service;
  final String upsell;
  final int bookings;
  final int taken;
  final double? takeRate;
  final double extraRevenue;

  UpsellLinkStat({
    required this.service,
    required this.upsell,
    required this.bookings,
    required this.taken,
    this.takeRate,
    required this.extraRevenue,
  });

  factory UpsellLinkStat.fromJson(Map<String, dynamic> json) => UpsellLinkStat(
        service: (json['service'] ?? '').toString(),
        upsell: (json['upsell'] ?? '').toString(),
        bookings: _int(json['bookings']),
        taken: _int(json['taken']),
        takeRate: (json['take_rate'] as num?)?.toDouble(),
        extraRevenue: _num(json['extra_revenue']),
      );
}

class QuietHourOffer {
  final String label;
  final int bookings;
  final String suggestion;

  QuietHourOffer({required this.label, required this.bookings, required this.suggestion});

  factory QuietHourOffer.fromJson(Map<String, dynamic> json) => QuietHourOffer(
        label: (json['label'] ?? '').toString(),
        bookings: _int(json['bookings']),
        suggestion: (json['suggestion'] ?? '').toString(),
      );
}

class SlowService {
  final String name;
  final int last30Days;
  final int previous30Days;

  /// 'falling' or 'unbooked'.
  final String kind;
  final String suggestion;

  SlowService({
    required this.name,
    required this.last30Days,
    required this.previous30Days,
    required this.kind,
    required this.suggestion,
  });

  factory SlowService.fromJson(Map<String, dynamic> json) => SlowService(
        name: (json['name'] ?? '').toString(),
        last30Days: _int(json['last_30_days']),
        previous30Days: _int(json['previous_30_days']),
        kind: (json['kind'] ?? 'falling').toString(),
        suggestion: (json['suggestion'] ?? '').toString(),
      );
}

class WinBackCustomer {
  final String name;
  final String phone;
  final int visits;
  final double spend;
  final int daysSince;

  WinBackCustomer({
    required this.name,
    required this.phone,
    required this.visits,
    required this.spend,
    required this.daysSince,
  });

  factory WinBackCustomer.fromJson(Map<String, dynamic> json) => WinBackCustomer(
        name: (json['name'] ?? 'Customer').toString(),
        phone: (json['phone'] ?? '').toString(),
        visits: _int(json['visits']),
        spend: _num(json['spend']),
        daysSince: _int(json['days_since']),
      );
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

class BasicAnalytics {
  final RevenueTrend revenueTrend;
  final List<StaffPerformanceStat> staffPerformance;

  BasicAnalytics({
    required this.revenueTrend,
    required this.staffPerformance,
  });

  factory BasicAnalytics.fromJson(Map<String, dynamic> json) => BasicAnalytics(
        revenueTrend: RevenueTrend.fromJson(
            Map<String, dynamic>.from((json['revenue_trend'] ?? {}) as Map)),
        staffPerformance: ((json['staff_performance'] ?? []) as List)
            .map((r) => StaffPerformanceStat.fromJson(
                Map<String, dynamic>.from(r as Map)))
            .toList(),
      );
}

class RevenueTrend {
  final double totalRevenue;
  final int totalBookings;
  final List<WeeklyRevenue> weeks;

  RevenueTrend({
    required this.totalRevenue,
    required this.totalBookings,
    required this.weeks,
  });

  factory RevenueTrend.fromJson(Map<String, dynamic> json) => RevenueTrend(
        totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0.0,
        totalBookings: (json['total_bookings'] as num?)?.toInt() ?? 0,
        weeks: ((json['weeks'] ?? []) as List)
            .map((w) => WeeklyRevenue.fromJson(
                Map<String, dynamic>.from(w as Map)))
            .toList(),
      );
}

class WeeklyRevenue {
  final String label;
  final String period;
  final double revenue;
  final int bookings;

  WeeklyRevenue({
    required this.label,
    required this.period,
    required this.revenue,
    required this.bookings,
  });

  factory WeeklyRevenue.fromJson(Map<String, dynamic> json) => WeeklyRevenue(
        label: (json['label'] ?? '').toString(),
        period: (json['period'] ?? '').toString(),
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
        bookings: (json['bookings'] as num?)?.toInt() ?? 0,
      );
}

class StaffPerformanceStat {
  final String id;
  final String name;
  final int bookings;
  final double revenue;

  StaffPerformanceStat({
    required this.id,
    required this.name,
    required this.bookings,
    required this.revenue,
  });

  factory StaffPerformanceStat.fromJson(Map<String, dynamic> json) => StaffPerformanceStat(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? 'Staff').toString(),
        bookings: (json['bookings'] as num?)?.toInt() ?? 0,
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
      );
}

class RetentionFunnel {
  final int totalCustomers;
  final RetentionFunnelStep firstVisits;
  final RetentionFunnelStep secondVisits;
  final RetentionFunnelStep thirdVisits;
  final RetentionFunnelStep regularVisits;
  final String benchmarkMessage;
  final bool benchmarkIsGood;

  RetentionFunnel({
    required this.totalCustomers,
    required this.firstVisits,
    required this.secondVisits,
    required this.thirdVisits,
    required this.regularVisits,
    required this.benchmarkMessage,
    required this.benchmarkIsGood,
  });

  factory RetentionFunnel.fromJson(Map<String, dynamic> json) => RetentionFunnel(
        totalCustomers: (json['total_customers'] as num?)?.toInt() ?? 0,
        firstVisits: RetentionFunnelStep.fromJson(
            Map<String, dynamic>.from((json['first_visits'] ?? {}) as Map)),
        secondVisits: RetentionFunnelStep.fromJson(
            Map<String, dynamic>.from((json['second_visits'] ?? {}) as Map)),
        thirdVisits: RetentionFunnelStep.fromJson(
            Map<String, dynamic>.from((json['third_visits'] ?? {}) as Map)),
        regularVisits: RetentionFunnelStep.fromJson(
            Map<String, dynamic>.from((json['regular_visits'] ?? {}) as Map)),
        benchmarkMessage: (json['benchmark_message'] ?? '').toString(),
        benchmarkIsGood: json['benchmark_is_good'] == true,
      );
}

class RetentionFunnelStep {
  final int count;
  final double rate;

  RetentionFunnelStep({required this.count, required this.rate});

  factory RetentionFunnelStep.fromJson(Map<String, dynamic> json) => RetentionFunnelStep(
        count: (json['count'] as num?)?.toInt() ?? 0,
        rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      );
}

