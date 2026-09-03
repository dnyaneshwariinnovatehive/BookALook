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

  ServiceTemplate({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.estimatedDurationMinutes,
    this.isCustom = false,
    this.category,
  });

  factory ServiceTemplate.fromJson(Map<String, dynamic> json) {
    return ServiceTemplate(
      id: json['id'],
      categoryId: json['category_id'],
      name: json['name'],
      estimatedDurationMinutes: json['estimated_duration_minutes'] ?? 30,
      isCustom: json['is_custom'] == 1 || json['is_custom'] == true,
      category: json['category'] != null ? ServiceCategory.fromJson(json['category']) : null,
    );
  }
}

class SalonService {
  final String id;
  final String salonId;
  final String templateId;
  final double price;
  final String? description;
  final ServiceTemplate? template;

  SalonService({
    required this.id,
    required this.salonId,
    required this.templateId,
    required this.price,
    this.description,
    this.template,
  });

  factory SalonService.fromJson(Map<String, dynamic> json) {
    return SalonService(
      id: json['id'],
      salonId: json['salon_id'],
      templateId: json['template_id'],
      price: double.parse(json['price'].toString()),
      description: json['description'],
      template: json['template'] != null ? ServiceTemplate.fromJson(json['template']) : null,
    );
  }
}
