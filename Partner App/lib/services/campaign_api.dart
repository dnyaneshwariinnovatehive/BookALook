import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

/// WhatsApp marketing.
///
/// Nothing here decides what the salon is allowed to do. The server owns every
/// entitlement — which templates are unlocked, which audiences may be targeted,
/// how much of the month's allowance is left — and this only carries the answer
/// up to the screen. An app can be out of date or lying about its plan; the
/// quota has to be enforced somewhere that cannot be.
class CampaignApi {
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

  /// Templates, audiences and the allowance, in one call.
  static Future<CampaignOptions> options(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/campaigns/options'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      return CampaignOptions.fromJson(jsonDecode(response.body));
    }

    throw Exception('Could not load your marketing options.');
  }

  /// How many people an audience reaches. Spends nothing, so it is safe to
  /// call on every change to the filters.
  static Future<AudiencePreview> preview(String salonId, Map<String, dynamic> audience) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/campaigns/preview'),
      headers: await _headers(),
      body: jsonEncode({'audience': audience}),
    );

    final body = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return AudiencePreview.fromJson(body['preview']);
    }

    throw CampaignRefused(body['message'] ?? 'Could not work out who this would reach.',
        upgradeRequired: body['upgrade_required'] == true);
  }

  static Future<List<Campaign>> list(String salonId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/salons/$salonId/campaigns'),
      headers: await _headers(),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final rows = (body['data']?['data'] ?? []) as List;
      return rows.map((row) => Campaign.fromJson(row)).toList();
    }

    throw Exception('Could not load your campaigns.');
  }

  static Future<Campaign> send({
    required String salonId,
    required String templateId,
    required String name,
    required Map<String, dynamic> audience,
    required Map<String, String> variables,
    String? scheduledFor,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/salons/$salonId/campaigns'),
      headers: await _headers(),
      body: jsonEncode({
        'campaign_template_id': templateId,
        'name': name,
        'audience': audience,
        'variables': variables,
        if (scheduledFor != null) 'scheduled_for': scheduledFor,
        'send_now': scheduledFor == null,
      }),
    );

    final body = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return Campaign.fromJson(body['data']);
    }

    throw CampaignRefused(body['message'] ?? 'Could not send that campaign.',
        upgradeRequired: body['upgrade_required'] == true);
  }
}

/// A refusal the salon can act on — usually by upgrading.
class CampaignRefused implements Exception {
  final String message;
  final bool upgradeRequired;

  CampaignRefused(this.message, {this.upgradeRequired = false});

  @override
  String toString() => message;
}

class CampaignOptions {
  final Entitlement entitlement;
  final List<CampaignTemplate> templates;
  final List<AudienceSegment> segments;

  CampaignOptions({required this.entitlement, required this.templates, required this.segments});

  factory CampaignOptions.fromJson(Map<String, dynamic> json) => CampaignOptions(
        entitlement: Entitlement.fromJson(json['entitlement'] ?? {}),
        templates: ((json['templates'] ?? []) as List)
            .map((row) => CampaignTemplate.fromJson(row))
            .toList(),
        segments: ((json['segments'] ?? []) as List)
            .map((row) => AudienceSegment.fromJson(row))
            .toList(),
      );
}

class Entitlement {
  final bool hasPlan;
  final bool canSend;
  final String? planName;
  final String? reason;

  /// Null when the plan does not cap that allowance at all, which is a
  /// different thing from having plenty left.
  final int? campaignsRemaining;
  final int? messagesRemaining;
  final int campaignsUsed;
  final int campaignLimit;
  final int messagesUsed;
  final int messageLimit;

  final bool quietHoursNow;
  final int quietStart;
  final int quietEnd;
  final String? cycleEnd;

  Entitlement({
    required this.hasPlan,
    required this.canSend,
    this.planName,
    this.reason,
    this.campaignsRemaining,
    this.messagesRemaining,
    this.campaignsUsed = 0,
    this.campaignLimit = 0,
    this.messagesUsed = 0,
    this.messageLimit = 0,
    this.quietHoursNow = false,
    this.quietStart = 21,
    this.quietEnd = 9,
    this.cycleEnd,
  });

  factory Entitlement.fromJson(Map<String, dynamic> json) {
    final campaigns = json['campaigns'] ?? {};
    final messages = json['messages'] ?? {};
    final quiet = json['quiet_hours'] ?? {};

    return Entitlement(
      hasPlan: json['has_plan'] == true,
      canSend: json['can_send'] == true,
      planName: json['plan_name'],
      reason: json['reason'],
      campaignsRemaining: campaigns['remaining'],
      messagesRemaining: messages['remaining'],
      campaignsUsed: campaigns['used'] ?? 0,
      campaignLimit: campaigns['limit'] ?? 0,
      messagesUsed: messages['used'] ?? 0,
      messageLimit: messages['limit'] ?? 0,
      quietHoursNow: quiet['active_now'] == true,
      quietStart: quiet['start'] ?? 21,
      quietEnd: quiet['end'] ?? 9,
      cycleEnd: json['cycle_end'],
    );
  }

  bool get campaignsUncapped => campaignLimit == 0;
  bool get messagesUncapped => messageLimit == 0;
}

class CampaignTemplate {
  final String id;
  final String key;
  final String name;
  final String category;
  final String categoryLabel;
  final String? description;
  final String bodyPreview;
  final List<TemplateVariable> variables;
  final Map<String, dynamic>? defaultAudience;

  /// Shown but not usable on this plan. Deliberately visible rather than
  /// hidden — a salon cannot want what it cannot see.
  final bool locked;

  CampaignTemplate({
    required this.id,
    required this.key,
    required this.name,
    required this.category,
    required this.categoryLabel,
    required this.bodyPreview,
    required this.variables,
    this.description,
    this.defaultAudience,
    this.locked = false,
  });

  factory CampaignTemplate.fromJson(Map<String, dynamic> json) => CampaignTemplate(
        id: json['id'],
        key: json['key'] ?? '',
        name: json['name'] ?? '',
        category: json['category'] ?? '',
        categoryLabel: json['category_label'] ?? '',
        description: json['description'],
        bodyPreview: json['body_preview'] ?? '',
        variables: ((json['variables'] ?? []) as List)
            .map((row) => TemplateVariable.fromJson(row))
            .toList(),
        defaultAudience: json['default_audience'] == null
            ? null
            : Map<String, dynamic>.from(json['default_audience']),
        locked: json['locked'] == true,
      );

  /// The variables the owner has to type. Anything the server fills per
  /// customer — their name, the salon's — is not their problem.
  List<TemplateVariable> get askable =>
      variables.where((v) => v.source == 'input').toList();

  /// The message as it will arrive, with the owner's answers filled in.
  String render(Map<String, String> values) {
    var body = bodyPreview;

    for (var i = 0; i < variables.length; i++) {
      final variable = variables[i];
      final value = variable.source == 'input'
          ? (values[variable.key]?.isNotEmpty == true ? values[variable.key]! : variable.example)
          : variable.example;
      body = body.replaceAll('{{${i + 1}}}', value);
    }

    return body;
  }
}

class TemplateVariable {
  final String key;
  final String label;
  final String example;
  final String source;

  TemplateVariable({
    required this.key,
    required this.label,
    required this.example,
    required this.source,
  });

  factory TemplateVariable.fromJson(Map<String, dynamic> json) => TemplateVariable(
        key: json['key'] ?? '',
        label: json['label'] ?? '',
        example: json['example'] ?? '',
        source: json['source'] ?? 'input',
      );
}

class AudienceSegment {
  final String key;
  final String name;
  final String description;
  final bool locked;

  AudienceSegment({
    required this.key,
    required this.name,
    required this.description,
    this.locked = false,
  });

  factory AudienceSegment.fromJson(Map<String, dynamic> json) => AudienceSegment(
        key: json['key'] ?? '',
        name: json['name'] ?? '',
        description: json['description'] ?? '',
        locked: json['locked'] == true,
      );
}

class AudiencePreview {
  final int matched;
  final int reachable;
  final int willSend;
  final int beyondAllowance;
  final Map<String, int> skipped;

  AudiencePreview({
    required this.matched,
    required this.reachable,
    required this.willSend,
    required this.beyondAllowance,
    required this.skipped,
  });

  factory AudiencePreview.fromJson(Map<String, dynamic> json) => AudiencePreview(
        matched: json['matched'] ?? 0,
        reachable: json['reachable'] ?? 0,
        willSend: json['will_send'] ?? 0,
        beyondAllowance: json['beyond_allowance'] ?? 0,
        skipped: Map<String, int>.from(json['skipped'] ?? {}),
      );

  /// Why people were left out, in words an owner would use.
  String? get skipExplanation {
    if (skipped.isEmpty) return null;

    final parts = <String>[];
    skipped.forEach((reason, count) {
      parts.add(switch (reason) {
        'opted_out' => '$count asked not to be messaged',
        'no_consent' => '$count have not agreed to offers yet',
        'invalid_phone' => '$count have an unusable phone number',
        _ => '$count skipped',
      });
    });

    return parts.join(', ');
  }
}

class Campaign {
  final String id;
  final String name;
  final String status;
  final String? template;
  final int recipientsCount;
  final int sentCount;
  final int deliveredCount;
  final int readCount;
  final int failedCount;
  final int skippedCount;
  final double? readRate;
  final String? createdAt;
  final String? scheduledFor;
  final String? failureReason;

  Campaign({
    required this.id,
    required this.name,
    required this.status,
    this.template,
    this.recipientsCount = 0,
    this.sentCount = 0,
    this.deliveredCount = 0,
    this.readCount = 0,
    this.failedCount = 0,
    this.skippedCount = 0,
    this.readRate,
    this.createdAt,
    this.scheduledFor,
    this.failureReason,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) => Campaign(
        id: json['id'],
        name: json['name'] ?? '',
        status: json['status'] ?? 'draft',
        template: json['template'],
        recipientsCount: json['recipients_count'] ?? 0,
        sentCount: json['sent_count'] ?? 0,
        deliveredCount: json['delivered_count'] ?? 0,
        readCount: json['read_count'] ?? 0,
        failedCount: json['failed_count'] ?? 0,
        skippedCount: json['skipped_count'] ?? 0,
        readRate: (json['read_rate'] as num?)?.toDouble(),
        createdAt: json['created_at'],
        scheduledFor: json['scheduled_for'],
        failureReason: json['failure_reason'],
      );
}
