class ServiceCategory {
  final String id;
  final String name;
  final String? iconUrl;

  ServiceCategory({
    required this.id,
    required this.name,
    this.iconUrl,
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      id: json['id'],
      name: json['name'],
      iconUrl: json['icon_url'],
    );
  }
}
