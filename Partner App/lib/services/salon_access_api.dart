import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

/// Whether the salon is trading, and what to do about it if not.
class SalonAccessApi {
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

  static Future<SalonAccess> check(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/access'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return SalonAccess.fromJson(jsonDecode(response.body));
    }

    throw Exception('Could not check the salon status.');
  }
}

/// What a Commission Model salon owes BookALook, and the steps SuperAdmin's
/// policy has applied because of it. Lifts by itself once the salon pays.
class CommissionDues {
  final double owed;
  final String? dueDate;
  final int? daysOverdue;
  final int underReview;
  final List<String> actions;
  final String? stage;
  final String? stageLabel;
  final String? message;
  final String? nextLabel;
  final String? nextOn;

  const CommissionDues({
    required this.owed,
    this.dueDate,
    this.daysOverdue,
    this.underReview = 0,
    this.actions = const [],
    this.stage,
    this.stageLabel,
    this.message,
    this.nextLabel,
    this.nextOn,
  });

  bool get owesAnything => owed > 0;
  bool get isOverdue => (daysOverdue ?? -1) >= 0;
  bool has(String step) => actions.contains(step);

  /// Worth a banner on Home: anything from the warning step up, or a
  /// reminder that the due date is close.
  bool get showBanner => owesAnything && actions.isNotEmpty;

  factory CommissionDues.fromJson(Map<String, dynamic> json) {
    final next = json['next'] as Map<String, dynamic>?;
    return CommissionDues(
      owed: (json['owed'] as num?)?.toDouble() ?? 0,
      dueDate: json['due_date']?.toString(),
      daysOverdue: (json['days_overdue'] as num?)?.toInt(),
      underReview: (json['under_review'] as num?)?.toInt() ?? 0,
      actions: ((json['actions'] as List?) ?? const []).map((e) => e.toString()).toList(),
      stage: json['stage']?.toString(),
      stageLabel: json['stage_label']?.toString(),
      message: json['message']?.toString(),
      nextLabel: next?['label']?.toString(),
      nextOn: next?['on']?.toString(),
    );
  }
}

class SalonAccess {
  final String salonName;
  final bool isLocked;
  final String? reason;
  final String? expiredOn;
  final int? daysRemaining;

  /// True for the owner; staff can only ask them to renew.
  final bool canRenew;

  final String? planName;
  final String? adminName;
  final String? adminPhone;

  /// Reward coins the salon can put towards a plan, and what they are worth.
  /// A newly approved salon arrives here with its welcome bonus already in,
  /// which is the difference between "pay ₹1999" and "pay nothing".
  final int walletCoins;
  final double walletValueInr;
  final DateTime? welcomeBonusGrantedAt;

  final bool hasPendingRequest;
  final Map<String, dynamic>? pendingRequest;
  final Map<String, dynamic>? latestRejectedRequest;

  /// Commission Model salons only: unpaid dues and the steps in force.
  final CommissionDues? dues;

  /// Customers cannot book right now (unpaid commission), though the app
  /// itself is open.
  final bool bookingsPaused;

  SalonAccess({
    required this.salonName,
    required this.isLocked,
    this.reason,
    this.expiredOn,
    this.daysRemaining,
    required this.canRenew,
    this.planName,
    this.adminName,
    this.adminPhone,
    this.walletCoins = 0,
    this.walletValueInr = 0,
    this.welcomeBonusGrantedAt,
    this.hasPendingRequest = false,
    this.pendingRequest,
    this.latestRejectedRequest,
    this.dues,
    this.bookingsPaused = false,
  });

  /// Locked because the salon owes commission, not because a plan ran out.
  bool get isCommissionLock => reason == 'commission_unsettled';

  /// A plan that ran out, as opposed to a salon that was never approved.
  bool get isSubscriptionProblem =>
      reason == 'subscription_expired' || reason == 'no_subscription';

  /// Approved, but has never held a plan. Nothing has "ended" for this salon —
  /// it is standing at the start line, so the lock screen has to sell the
  /// first purchase rather than chase a renewal.
  bool get hasNeverSubscribed => reason == 'no_subscription';

  /// A payment submission was received and is currently waiting on SuperAdmin review.
  bool get isPendingApproval => hasPendingRequest && pendingRequest != null;

  /// The most recent payment submission was rejected/not accepted.
  bool get hasRejectedPayment =>
      !hasPendingRequest && latestRejectedRequest != null;

  factory SalonAccess.fromJson(Map<String, dynamic> json) {
    final subscription = json['subscription'] as Map<String, dynamic>?;
    final admin = json['salon_admin'] as Map<String, dynamic>?;

    return SalonAccess(
      salonName: json['salon_name'] ?? 'Your salon',
      isLocked: json['is_locked'] == true,
      reason: json['reason'],
      expiredOn: json['expired_on'],
      daysRemaining: json['days_remaining'],
      canRenew: json['can_renew'] == true,
      planName: subscription?['plan_name'],
      adminName: admin?['name'],
      adminPhone: admin?['phone'],
      walletCoins: (json['wallet_coins'] as num?)?.toInt() ?? 0,
      walletValueInr: (json['wallet_value_inr'] as num?)?.toDouble() ?? 0,
      welcomeBonusGrantedAt: json['welcome_bonus_granted_at'] != null
          ? DateTime.tryParse(json['welcome_bonus_granted_at'])
          : null,
      hasPendingRequest:
          json['has_pending_request'] == true ||
          json['pending_request'] != null,
      pendingRequest: json['pending_request'] as Map<String, dynamic>?,
      latestRejectedRequest:
          json['latest_rejected_request'] as Map<String, dynamic>?,
      dues: json['dues'] is Map<String, dynamic>
          ? CommissionDues.fromJson(json['dues'] as Map<String, dynamic>)
          : null,
      bookingsPaused: json['bookings_paused'] == true,
    );
  }

  /// True when there are coins worth showing off on the plan screen.
  bool get hasCoins => walletCoins > 0 && walletValueInr > 0;
}
