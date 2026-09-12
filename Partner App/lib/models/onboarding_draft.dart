/// A salon a collaborator is building, as it exists on the device.
///
/// Collaborators work inside other people's salons, where the signal is
/// whatever the building allows. So the draft — not the server — is the thing
/// being edited: every change is written to disk, and the submission is a
/// separate act that may fail and be retried without anything being lost.
///
/// Photos are held as file paths into the app's own documents directory rather
/// than the camera's temp folder, because a temp file is gone by the time the
/// signal comes back.
class OnboardingDraft {
  /// The assignment this draft belongs to. A collaborator may only onboard a
  /// salon SuperAdmin assigned them, so a draft without one cannot exist.
  final String enquiryId;

  // Owner — prefilled from the enquiry, correctable on site.
  String ownerName;
  String ownerPhone;
  String ownerEmail;

  // Salon profile.
  String salonName;
  String description;
  String address;
  String? cityId;
  String cityLabel;
  String pincode;
  String salonPhone;
  String genderFocus;
  double? latitude;
  double? longitude;

  /// Seven entries, Sunday first. Always a full week — a day left out would be
  /// ambiguous, and the server reads a missing day as closed.
  List<DraftWorkingDay> workingHours;

  /// Optional. A salon can be submitted as a profile alone and have its menu
  /// priced by the owner later.
  List<DraftService> services;

  /// Absolute paths to photos copied into app storage.
  List<String> photoPaths;
  int coverIndex;

  /// How many photos the salon already has on the server.
  ///
  /// Only ever non-zero on an edit. The device does not hold those files and the
  /// server leaves its gallery alone when a submission carries none, so they
  /// satisfy the "needs a photo" rule without having to be re-taken. Without
  /// this, correcting a typo would demand re-photographing the whole salon.
  int existingPhotoCount;

  /// Set once the draft has been handed to the server and accepted, so a
  /// synced draft can be cleared rather than replayed forever.
  bool submitted;

  /// Why the last submission attempt failed, if it did. Shown to the
  /// collaborator so a validation problem does not look like a dead queue.
  String? lastError;

  DateTime updatedAt;

  OnboardingDraft({
    required this.enquiryId,
    this.ownerName = '',
    this.ownerPhone = '',
    this.ownerEmail = '',
    this.salonName = '',
    this.description = '',
    this.address = '',
    this.cityId,
    this.cityLabel = '',
    this.pincode = '',
    this.salonPhone = '',
    this.genderFocus = 'Unisex',
    this.latitude,
    this.longitude,
    List<DraftWorkingDay>? workingHours,
    List<DraftService>? services,
    List<String>? photoPaths,
    this.coverIndex = 0,
    this.existingPhotoCount = 0,
    this.submitted = false,
    this.lastError,
    DateTime? updatedAt,
  })  : workingHours = workingHours ?? DraftWorkingDay.defaultWeek(),
        services = services ?? [],
        photoPaths = photoPaths ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  /// A new draft seeded with what the enquiry already told us, so the
  /// collaborator confirms rather than retypes.
  factory OnboardingDraft.fromEnquiry(Map<String, dynamic> enquiry) {
    return OnboardingDraft(
      enquiryId: enquiry['id'].toString(),
      ownerName: enquiry['owner_name']?.toString() ?? '',
      ownerPhone: enquiry['phone']?.toString() ?? '',
      salonName: enquiry['salon_name']?.toString() ?? '',
      cityLabel: enquiry['city']?.toString() ?? '',
    );
  }

  /// Refill a draft from a salon that was already submitted and sent back.
  ///
  /// Photos are deliberately not restored: the device no longer holds the
  /// files, and the server replaces the whole gallery on resubmission. A
  /// correction that needs different photos takes them again; one that does not
  /// leaves the list empty, which the server reads as "leave the gallery alone".
  void restoreFrom(Map<String, dynamic> salon) {
    ownerName = salon['owner_name']?.toString() ?? ownerName;
    ownerPhone = salon['owner_phone']?.toString() ?? ownerPhone;
    ownerEmail = salon['owner_email']?.toString() ?? '';
    salonName = salon['salon_name']?.toString() ?? salonName;
    description = salon['description']?.toString() ?? '';
    address = salon['address']?.toString() ?? '';
    cityId = salon['city_id']?.toString();
    pincode = salon['pincode']?.toString() ?? '';
    salonPhone = salon['salon_phone']?.toString() ?? '';
    genderFocus = salon['gender_focus']?.toString() ?? 'Unisex';
    latitude = (salon['latitude'] as num?)?.toDouble();
    longitude = (salon['longitude'] as num?)?.toDouble();

    final hours = salon['working_hours'] as List?;
    if (hours != null && hours.isNotEmpty) {
      // Merged into a full week rather than replacing it, so a salon stored
      // with only its open days still comes back as seven rows.
      final week = DraftWorkingDay.defaultWeek();
      for (final raw in hours) {
        final day = Map<String, dynamic>.from(raw as Map);
        final index = day['day_of_week'] as int;
        week[index] = DraftWorkingDay(
          dayOfWeek: index,
          isClosed: day['is_closed'] == true,
          openTime: day['open_time']?.toString() ?? '10:00',
          closeTime: day['close_time']?.toString() ?? '20:00',
        );
      }
      workingHours = week;
    }

    services = (salon['services'] as List? ?? [])
        .map((raw) => DraftService.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();

    existingPhotoCount = (salon['photo_urls'] as List?)?.length ?? 0;
  }

  /// Everything the profile needs before it can go to SuperAdmin.
  ///
  /// The bar is "a customer could make a decision from this page": a name, a
  /// description, where it is, when it is open, a way to reach the salon, and at
  /// least one photo. Only three things are genuinely optional — the owner's
  /// email, the GPS pin, and the service menu, which the owner can price
  /// themselves later.
  bool get isComplete => missingFields.isEmpty;

  /// Every required field still blank, phrased for a person. Drives both the
  /// per-step gate and the review card, so the two can never disagree.
  List<String> get missingFields => [
        ...missingOn(0),
        ...missingOn(1),
        ...missingOn(2),
      ];

  /// What is missing on one step of the form. Step 3 (services) has nothing
  /// required on it by design.
  List<String> missingOn(int step) => switch (step) {
        0 => [
            if (salonName.trim().isEmpty) 'Salon name',
            if (description.trim().isEmpty) 'Description',
            if (salonPhone.trim().isEmpty) 'Salon phone',
            if (ownerName.trim().isEmpty) 'Owner name',
            if (!_isPhone(ownerPhone)) 'Owner phone (10 digits)',
          ],
        1 => [
            if (address.trim().isEmpty) 'Street address',
            if (cityId == null) 'City',
            if (!_isPincode(pincode)) 'Pincode (6 digits)',
            if (photoPaths.isEmpty && existingPhotoCount == 0) 'At least one photo',
          ],
        2 => [
            if (workingHours.every((day) => day.isClosed)) 'At least one open day',
            if (!workingHours.every((day) => day.isValid))
              'Closing time after opening time on every open day',
          ],
        _ => const [],
      };

  static bool _isPhone(String value) =>
      RegExp(r'^\d{10,15}$').hasMatch(value.trim().replaceAll(RegExp(r'[\s-]'), ''));

  static bool _isPincode(String value) => RegExp(r'^\d{6}$').hasMatch(value.trim());

  Map<String, dynamic> toJson() => {
        'enquiry_id': enquiryId,
        'owner_name': ownerName,
        'owner_phone': ownerPhone,
        'owner_email': ownerEmail,
        'salon_name': salonName,
        'description': description,
        'address': address,
        'city_id': cityId,
        'city_label': cityLabel,
        'pincode': pincode,
        'salon_phone': salonPhone,
        'gender_focus': genderFocus,
        'latitude': latitude,
        'longitude': longitude,
        'working_hours': workingHours.map((d) => d.toJson()).toList(),
        'services': services.map((s) => s.toJson()).toList(),
        'photo_paths': photoPaths,
        'cover_index': coverIndex,
        'existing_photo_count': existingPhotoCount,
        'submitted': submitted,
        'last_error': lastError,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory OnboardingDraft.fromJson(Map<String, dynamic> json) => OnboardingDraft(
        enquiryId: json['enquiry_id'].toString(),
        ownerName: json['owner_name'] ?? '',
        ownerPhone: json['owner_phone'] ?? '',
        ownerEmail: json['owner_email'] ?? '',
        salonName: json['salon_name'] ?? '',
        description: json['description'] ?? '',
        address: json['address'] ?? '',
        cityId: json['city_id'],
        cityLabel: json['city_label'] ?? '',
        pincode: json['pincode'] ?? '',
        salonPhone: json['salon_phone'] ?? '',
        genderFocus: json['gender_focus'] ?? 'Unisex',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        workingHours: (json['working_hours'] as List?)
            ?.map((d) => DraftWorkingDay.fromJson(Map<String, dynamic>.from(d)))
            .toList(),
        services: (json['services'] as List?)
            ?.map((s) => DraftService.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
        photoPaths: (json['photo_paths'] as List?)?.map((p) => p.toString()).toList(),
        coverIndex: json['cover_index'] ?? 0,
        existingPhotoCount: json['existing_photo_count'] ?? 0,
        submitted: json['submitted'] == true,
        lastError: json['last_error'],
        updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      );

  /// The fields the submit endpoint expects, photos excluded — those travel as
  /// files alongside.
  Map<String, String> toFormFields() => {
        if (ownerName.trim().isNotEmpty) 'owner_name': ownerName.trim(),
        if (ownerPhone.trim().isNotEmpty) 'owner_phone': ownerPhone.trim(),
        if (ownerEmail.trim().isNotEmpty) 'owner_email': ownerEmail.trim(),
        'salon_name': salonName.trim(),
        if (description.trim().isNotEmpty) 'description': description.trim(),
        'address': address.trim(),
        'city_id': cityId ?? '',
        if (pincode.trim().isNotEmpty) 'pincode': pincode.trim(),
        if (salonPhone.trim().isNotEmpty) 'salon_phone': salonPhone.trim(),
        'gender_focus': genderFocus,
        if (latitude != null) 'latitude': latitude.toString(),
        if (longitude != null) 'longitude': longitude.toString(),
        'cover_index': coverIndex.toString(),
      };
}

class DraftWorkingDay {
  final int dayOfWeek; // 0 = Sunday
  bool isClosed;
  String openTime; // HH:mm
  String closeTime;

  DraftWorkingDay({
    required this.dayOfWeek,
    this.isClosed = false,
    this.openTime = '10:00',
    this.closeTime = '20:00',
  });

  static const names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  String get name => names[dayOfWeek];

  /// Sunday closed is the common shape and the least surprising default.
  static List<DraftWorkingDay> defaultWeek() =>
      List.generate(7, (day) => DraftWorkingDay(dayOfWeek: day, isClosed: day == 0));

  bool get isValid => isClosed || closeTime.compareTo(openTime) > 0;

  Map<String, dynamic> toJson() => {
        'day_of_week': dayOfWeek,
        'is_closed': isClosed,
        'open_time': isClosed ? null : openTime,
        'close_time': isClosed ? null : closeTime,
      };

  factory DraftWorkingDay.fromJson(Map<String, dynamic> json) => DraftWorkingDay(
        dayOfWeek: json['day_of_week'],
        isClosed: json['is_closed'] == true,
        openTime: json['open_time'] ?? '10:00',
        closeTime: json['close_time'] ?? '20:00',
      );
}

/// One line of the salon's menu: either a pick from the master catalog or
/// something the catalog has never heard of.
class DraftService {
  final String? templateId;
  final String name;
  final String categoryName;
  final int durationMinutes;
  double price;
  String description;

  /// Only set for a custom line — the catalog category it should be filed
  /// under, or 'new_custom' to create one.
  final String? categoryId;

  DraftService({
    this.templateId,
    required this.name,
    required this.categoryName,
    required this.durationMinutes,
    required this.price,
    this.description = '',
    this.categoryId,
  });

  bool get isCustom => templateId == null;

  Map<String, dynamic> toJson() => {
        'template_id': templateId,
        'name': name,
        'category_name': categoryName,
        'duration_minutes': durationMinutes,
        'price': price,
        'description': description,
        'category_id': categoryId,
      };

  factory DraftService.fromJson(Map<String, dynamic> json) => DraftService(
        templateId: json['template_id'],
        name: json['name'] ?? '',
        categoryName: json['category_name'] ?? '',
        durationMinutes: json['duration_minutes'] ?? 30,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        description: json['description'] ?? '',
        categoryId: json['category_id'],
      );

  /// The shape the submit endpoint validates.
  Map<String, dynamic> toPayload() => isCustom
      ? {
          'custom_template_name': name,
          'estimated_duration_minutes': durationMinutes,
          'category_id': categoryId ?? 'new_custom',
          if (categoryId == null || categoryId == 'new_custom')
            'custom_category_name': categoryName,
          'price': price,
          if (description.trim().isNotEmpty) 'description': description.trim(),
        }
      : {
          'template_id': templateId,
          'price': price,
          if (description.trim().isNotEmpty) 'description': description.trim(),
        };
}
