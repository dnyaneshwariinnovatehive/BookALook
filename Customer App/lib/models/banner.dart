class PromoBanner {
  final String id;
  final String title;
  final String imageUrl;
  final String mediaKind;
  final String targetScope;
  final String? targetCity;
  final String? targetSalonId;
  final String? actionUrl;

  PromoBanner({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.mediaKind = 'image',
    required this.targetScope,
    this.targetCity,
    this.targetSalonId,
    this.actionUrl,
  });

  /// True if the banner represents an animated GIF or animated WebP.
  bool get isAnimated => mediaKind == 'animated';

  factory PromoBanner.fromJson(Map<String, dynamic> json) {
    final rawKind = json['media_kind']?.toString().toLowerCase().trim();
    final parsedKind = rawKind == 'animated' ? 'animated' : 'image';

    return PromoBanner(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      mediaKind: parsedKind,
      targetScope: json['target_scope']?.toString() ?? 'platform',
      targetCity: json['target_city']?.toString() ?? json['target_city_id']?.toString(),
      targetSalonId: json['target_salon_id']?.toString(),
      actionUrl: json['action_url']?.toString(),
    );
  }
}

