class PromoBanner {
  final String id;
  final String title;
  final String imageUrl;
  final String targetScope;
  final String? targetCity;
  final String? targetSalonId;
  final String? actionUrl;

  PromoBanner({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.targetScope,
    this.targetCity,
    this.targetSalonId,
    this.actionUrl,
  });

  factory PromoBanner.fromJson(Map<String, dynamic> json) {
    return PromoBanner(
      id: json['id'],
      title: json['title'],
      imageUrl: json['image_url'],
      targetScope: json['target_scope'],
      targetCity: json['target_city'],
      targetSalonId: json['target_salon_id'],
      actionUrl: json['action_url'],
    );
  }
}
