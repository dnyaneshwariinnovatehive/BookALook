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

  /// All 8 configurable features in standardized order.
  List<PlanFeature> get allFeatures {
    final features = <PlanFeature>[];

    // 1. WhatsApp Campaigns (Campaign limit semantics from CampaignEntitlementService)
    if (whatsappCampaignLimit != null) {
      if (whatsappCampaignLimit! > 0) {
        final formattedLimit = NumberFormat('#,##,###').format(whatsappCampaignLimit);
        features.add(
          PlanFeature(
            key: 'whatsapp_campaign_limit',
            label: 'WhatsApp Campaigns',
            description: 'Promotional and automated campaign allowance',
            icon: Icons.campaign_outlined,
            isIncluded: true,
            tierBadge: '$formattedLimit/cycle',
            formattedValue: '$formattedLimit campaigns per cycle',
          ),
        );
      } else {
        // Limit is zero: in backend CampaignEntitlementService, 0 indicates unlimited allowance
        features.add(
          const PlanFeature(
            key: 'whatsapp_campaign_limit',
            label: 'WhatsApp Campaigns',
            description: 'Uncapped promotional campaign allowance',
            icon: Icons.campaign_outlined,
            isIncluded: true,
            tierBadge: 'Unlimited',
            formattedValue: 'Unlimited campaigns per cycle',
          ),
        );
      }
    } else {
      features.add(
        const PlanFeature(
          key: 'whatsapp_campaign_limit',
          label: 'WhatsApp Campaigns',
          description: 'Promotional campaigns not included in this tier',
          icon: Icons.campaign_outlined,
          isIncluded: false,
          formattedValue: 'No campaign allowance',
        ),
      );
    }

    // 2. Client Segmentation
    features.add(
      PlanFeature(
        key: 'has_customer_segmentation',
        label: 'Client Segmentation',
        description: 'Filter clients by visit frequency, spend, and activity',
        icon: Icons.pie_chart_outline_rounded,
        isIncluded: hasCustomerSegmentation,
        formattedValue: hasCustomerSegmentation ? 'Targeted client filtering' : null,
      ),
    );

    // 3. Service-Based Targeting
    features.add(
      PlanFeature(
        key: 'has_service_based_targeting',
        label: 'Service-Based Targeting',
        description: 'Re-engage clients who booked specific salon treatments',
        icon: Icons.content_cut_rounded,
        isIncluded: hasServiceBasedTargeting,
        formattedValue: hasServiceBasedTargeting ? 'Service-specific targeting' : null,
      ),
    );

    // 4. High-Value Client Targeting
    features.add(
      PlanFeature(
        key: 'has_high_value_targeting',
        label: 'High-Value Client Targeting',
        description: 'Exclusive offers tailored for top-spending clientele',
        icon: Icons.auto_awesome_rounded,
        isIncluded: hasHighValueTargeting,
        formattedValue: hasHighValueTargeting ? 'VIP client targeting' : null,
      ),
    );

    // 5. Advanced Business Insights
    features.add(
      PlanFeature(
        key: 'has_advanced_insights',
        label: 'Advanced Business Insights',
        description: 'In-depth revenue trends, popularity, and client retention',
        icon: Icons.insights_rounded,
        isIncluded: hasAdvancedInsights,
        formattedValue: hasAdvancedInsights ? 'Full analytics suite' : null,
      ),
    );

    // 6. Upsell Recommendations
    final hasUpsell = hasUpsellRecommendations != 'none';
    features.add(
      PlanFeature(
        key: 'has_upsell_recommendations',
        label: 'Upsell Recommendations',
        description: 'Smart suggestions to upgrade service selections',
        icon: Icons.trending_up_rounded,
        isIncluded: hasUpsell,
        tierBadge: hasUpsell ? (hasUpsellRecommendations == 'advanced' ? 'Advanced' : 'Basic') : null,
        formattedValue: hasUpsell
            ? (hasUpsellRecommendations == 'advanced' ? 'Advanced AI upsell suggestions' : 'Basic upsell suggestions')
            : null,
      ),
    );

    // 7. Cross-Sell Recommendations
    final hasCrossSell = hasCrossSellRecommendations != 'none';
    features.add(
      PlanFeature(
        key: 'has_cross_sell_recommendations',
        label: 'Cross-Sell Recommendations',
        description: 'Recommend complementary services and products',
        icon: Icons.alt_route_rounded,
        isIncluded: hasCrossSell,
        tierBadge: hasCrossSell ? (hasCrossSellRecommendations == 'advanced' ? 'Advanced' : 'Basic') : null,
        formattedValue: hasCrossSell
            ? (hasCrossSellRecommendations == 'advanced' ? 'Advanced AI service pairings' : 'Basic service pairings')
            : null,
      ),
    );

    // 8. Priority Search Visibility
    features.add(
      PlanFeature(
        key: 'has_priority_visibility',
        label: 'Priority Search Visibility',
        description: 'Higher placement in BookALook customer search listings',
        icon: Icons.verified_rounded,
        isIncluded: hasPriorityVisibility,
        tierBadge: hasPriorityVisibility ? 'Premium' : null,
        formattedValue: hasPriorityVisibility ? 'Boosted discovery ranking' : null,
      ),
    );

    return features;
  }

  /// Returns only features that are enabled/included in this plan.
  List<PlanFeature> get includedFeatures {
    return allFeatures.where((f) => f.isIncluded).toList();
  }
}
