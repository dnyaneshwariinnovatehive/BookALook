import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// One individual feature capability within a subscription plan.
class PlanFeature {
  final String key;
  final String label;
  final String? description;
  final IconData icon;
  final bool isIncluded;
  final String? tierBadge; // e.g. 'Basic', 'Advanced', 'Unlimited'
  final String? formattedValue; // e.g. '250 campaigns per cycle'

  const PlanFeature({
    required this.key,
    required this.label,
    this.description,
    required this.icon,
    required this.isIncluded,
    this.tierBadge,
    this.formattedValue,
  });
}

/// A subscription plan configured in SuperAdmin and returned by the Laravel API.
class SubscriptionPlan {
  final String id;
  final String name;
  final double price;
  final int validityDays;
  final int? whatsappCampaignLimit;
  final int? whatsappMessageLimit;
  final bool hasCustomerSegmentation;
  final bool hasServiceBasedTargeting;
  final bool hasHighValueTargeting;
  final bool hasAdvancedInsights;
  final String hasUpsellRecommendations;
  final String hasCrossSellRecommendations;
  final bool hasPriorityVisibility;
  final bool isActive;
  final bool isCommissionPlan;
  final Map<String, dynamic> rawJson;

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.validityDays,
    this.whatsappCampaignLimit,
    this.whatsappMessageLimit,
    required this.hasCustomerSegmentation,
    required this.hasServiceBasedTargeting,
    required this.hasHighValueTargeting,
    required this.hasAdvancedInsights,
    required this.hasUpsellRecommendations,
    required this.hasCrossSellRecommendations,
    required this.hasPriorityVisibility,
    required this.isActive,
    required this.isCommissionPlan,
    required this.rawJson,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    double parsePrice(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int parseValidityDays(dynamic value) {
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 30;
      return 30;
    }

    int? parseOptionalInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    bool parseBool(dynamic value) {
      if (value == true || value == 1 || value == '1' || value == 'true') {
        return true;
      }
      return false;
    }

    String parseTier(dynamic value) {
      if (value == null) return 'none';
      final s = value.toString().toLowerCase().trim();
      if (s == 'basic' || s == 'advanced') return s;
      return 'none';
    }

    return SubscriptionPlan(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Plan',
      price: parsePrice(json['price']),
      validityDays: parseValidityDays(json['validity_days']),
      whatsappCampaignLimit: parseOptionalInt(json['whatsapp_campaign_limit']),
      whatsappMessageLimit: parseOptionalInt(json['whatsapp_message_limit']),
      hasCustomerSegmentation: parseBool(json['has_customer_segmentation']),
      hasServiceBasedTargeting: parseBool(json['has_service_based_targeting']),
      hasHighValueTargeting: parseBool(json['has_high_value_targeting']),
      hasAdvancedInsights: parseBool(json['has_advanced_insights']),
      hasUpsellRecommendations: parseTier(json['has_upsell_recommendations']),
      hasCrossSellRecommendations: parseTier(json['has_cross_sell_recommendations']),
      hasPriorityVisibility: parseBool(json['has_priority_visibility']),
      isActive: json['is_active'] == null ? true : parseBool(json['is_active']),
      isCommissionPlan: parseBool(json['is_commission_plan']),
      rawJson: json,
    );
  }

  /// Formatted price with the rupee symbol (e.g. ₹1,999).
  String get formattedPrice {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: price % 1 == 0 ? 0 : 2,
    );
    return formatter.format(price);
  }

  /// Formatted cycle duration (e.g. "30 days" or "1 month").
  String get formattedDuration {
    if (validityDays == 30) return '30 days';
    if (validityDays == 365) return '1 year';
    return '$validityDays days';
  }

  /// Every feature a plan can carry, in the same order for every plan, so two
  /// plans can be compared line by line. Plans differ only in insights and
  /// revenue suggestions; bookings, staff, payroll and payouts are the same on
  /// all of them.
  List<PlanFeature> get allFeatures {
    final upsellAdvanced = hasUpsellRecommendations == 'advanced';
    final crossSellAdvanced = hasCrossSellRecommendations == 'advanced';
    final growth = hasAdvancedInsights;

    PlanFeature always(String key, String label, String description, IconData icon) =>
        PlanFeature(key: key, label: label, description: description, icon: icon, isIncluded: true);

    PlanFeature growthOnly(String key, String label, String description, IconData icon) =>
        PlanFeature(key: key, label: label, description: description, icon: icon, isIncluded: growth);

    return [
      // Know your salon: every plan.
      always('overview', 'Business overview', 'Bookings, revenue, customers and repeat rate', Icons.dashboard_outlined),
      always('revenue_trend', 'Revenue trend', 'The last 30 days, week by week', Icons.show_chart_rounded),
      always('service_performance', 'Service performance', 'Bookings and revenue for each service', Icons.content_cut_rounded),
      always('staff_performance', 'Staff performance', 'Bookings and revenue for each provider', Icons.groups_outlined),
      always('retention', 'Retention summary', 'Who came once, came back, or became a regular', Icons.loop_rounded),
      PlanFeature(
        key: 'upsell',
        label: 'Upsell tips',
        description: upsellAdvanced
            ? 'Every trade-up customers make, with the extra ₹ each brings'
            : 'The top 2 trade-ups your customers make',
        icon: Icons.trending_up_rounded,
        isIncluded: true,
        tierBadge: upsellAdvanced ? 'Full' : 'Basic',
      ),
      PlanFeature(
        key: 'cross_sell',
        label: 'Cross-sell pairs',
        description: crossSellAdvanced
            ? 'Every pair booked together, with the revenue behind it'
            : 'The top 3 services booked together',
        icon: Icons.alt_route_rounded,
        isIncluded: true,
        tierBadge: crossSellAdvanced ? 'Full' : 'Basic',
      ),

      // Grow your revenue: analytics.
      growthOnly('period', 'Longer history', '30, 90 and 365 days, compared with the period before', Icons.date_range_rounded),
      growthOnly('peak_hours', 'Peak & quiet hours', 'Busy and empty hours by day of the week', Icons.schedule_rounded),
      growthOnly('repeat_customers', 'Repeat customers', 'Your regulars, and who has stopped coming', Icons.favorite_border_rounded),
      growthOnly('areas', 'Customer areas', 'Which neighbourhoods your customers come from', Icons.place_outlined),
      growthOnly('gender_mix', 'Customer mix', 'Men and women split for each service', Icons.wc_rounded),
      growthOnly('visit_gap', 'Average bill & visit gap', 'What a visit is worth and how often customers return', Icons.receipt_long_outlined),
      growthOnly('staff_deep_dive', 'Staff deep-dive', 'Average bill, repeat rate and no-shows per provider', Icons.person_search_outlined),

      // Grow your revenue: suggestions.
      growthOnly('recommended_combos', 'Recommended combos', 'Ready-made combo ideas, created in one tap', Icons.auto_awesome_rounded),
      growthOnly('upsell_links', 'Upsell link performance', 'How often your upsell links are added at booking', Icons.link_rounded),
      growthOnly('quiet_hour_offers', 'Quiet-hour offer ideas', 'Offer ideas to fill your emptiest hours', Icons.lightbulb_outline_rounded),
      growthOnly('slow_services', 'Slow-service alerts', 'Services losing bookings, with what to do', Icons.trending_down_rounded),
      growthOnly('win_back', 'Win-back list', 'Regulars who stopped coming, with numbers to call', Icons.phone_callback_outlined),
    ];
  }

  /// Returns only features that are enabled/included in this plan.
  List<PlanFeature> get includedFeatures {
    return allFeatures.where((f) => f.isIncluded).toList();
  }
}
