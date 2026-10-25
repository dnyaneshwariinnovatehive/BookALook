class ServiceCategory {
  final String id;
  final String name;
  final String? iconUrl;
  final bool isCustom;
  final List<ServiceTemplate>? templates;

  ServiceCategory({
    required this.id,
    required this.name,
    this.iconUrl,
    this.isCustom = false,
    this.templates,
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      id: json['id'],
      name: json['name'],
      iconUrl: json['icon_url'],
      isCustom: json['is_custom'] == 1 || json['is_custom'] == true,
      templates: json['templates'] != null 
        ? (json['templates'] as List).map((i) => ServiceTemplate.fromJson(i)).toList()
        : null,
    );
  }
}

class ServiceTemplate {
  final String id;
  final String categoryId;
  final String name;
  final int estimatedDurationMinutes;
  final bool isCustom;
  final ServiceCategory? category;

  /// Who the superadmin says this service is for, in every salon.
  final String genderFocus;

  /// What this salon may offer it as. A gendered template is locked to its
  /// gender; a Unisex one may be narrowed. Null when the server did not say,
  /// in which case [allowedGenders] works it out from [genderFocus].
  final List<String>? allowedGenderFocus;

  ServiceTemplate({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.estimatedDurationMinutes,
    this.isCustom = false,
    this.category,
    this.genderFocus = 'Unisex',
    this.allowedGenderFocus,
  });

  static const genders = ['Unisex', 'Men Only', 'Women Only'];

  List<String> get allowedGenders =>
      allowedGenderFocus ?? (genderFocus == 'Unisex' ? genders : [genderFocus]);

  factory ServiceTemplate.fromJson(Map<String, dynamic> json) {
    return ServiceTemplate(
      id: json['id'],
      categoryId: json['category_id'],
      name: json['name'],
      estimatedDurationMinutes: json['estimated_duration_minutes'] ?? 30,
      isCustom: json['is_custom'] == 1 || json['is_custom'] == true,
      category: json['category'] != null ? ServiceCategory.fromJson(json['category']) : null,
      genderFocus: json['gender_focus']?.toString() ?? 'Unisex',
      allowedGenderFocus: (json['allowed_gender_focus'] as List?)?.map((g) => g.toString()).toList(),
    );
  }
}

/// The master catalogue as one salon may use it.
class MasterCatalog {
  final List<ServiceCategory> categories;
  final String salonGenderFocus;

  /// What a brand-new custom service may be at this salon.
  final List<String> customAllowedGenderFocus;

  MasterCatalog({
    required this.categories,
    this.salonGenderFocus = 'Unisex',
    this.customAllowedGenderFocus = ServiceTemplate.genders,
  });
}

class SalonService {
  final String id;
  final String salonId;
  final String templateId;
  final double price;
  final String? description;
  final ServiceTemplate? template;

  /// The add-ons the owner recommends with this service, in their order.
  final List<String> linkedServiceIds;

  SalonService({
    required this.id,
    required this.salonId,
    required this.templateId,
    required this.price,
    this.description,
    this.template,
    this.linkedServiceIds = const [],
  });

  factory SalonService.fromJson(Map<String, dynamic> json) {
    return SalonService(
      id: json['id'],
      salonId: json['salon_id'],
      templateId: json['template_id'],
      price: double.parse(json['price'].toString()),
      description: json['description'],
      template: json['template'] != null ? ServiceTemplate.fromJson(json['template']) : null,
      linkedServiceIds: (json['linked_service_ids'] as List?)?.map((id) => id.toString()).toList() ?? const [],
    );
  }
}

class UnassignedServiceItem {
  final String id;
  final String name;
  final String categoryName;
  final double price;
  final String? genderFocus;
  final int? durationMinutes;

  UnassignedServiceItem({
    required this.id,
    required this.name,
    required this.categoryName,
    required this.price,
    this.genderFocus,
    this.durationMinutes,
  });

  factory UnassignedServiceItem.fromJson(Map<String, dynamic> json) {
    return UnassignedServiceItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Service',
      categoryName: json['category_name']?.toString() ?? 'General',
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
      genderFocus: json['gender_focus']?.toString(),
      durationMinutes: json['duration_minutes'] != null
          ? int.tryParse(json['duration_minutes'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category_name': categoryName,
    'price': price,
    'gender_focus': genderFocus,
    'duration_minutes': durationMinutes,
  };
}
