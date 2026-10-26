import 'staff_models.dart';

class AdminProviderStatus {
  final bool isProviderEnabled;
  final AdminProviderProfile? provider;
  final AdminProviderValidation setupValidation;
  final int upcomingAppointmentsCount;

  /// Set when the owner's provider profile belongs to another of their
  /// salons. An owner can be a service provider at one salon only, so this
  /// salon shows [ProviderElsewhere.message] instead of the switch.
  final ProviderElsewhere? providerElsewhere;

  AdminProviderStatus({
    required this.isProviderEnabled,
    this.provider,
    required this.setupValidation,
    required this.upcomingAppointmentsCount,
    this.providerElsewhere,
  });

  factory AdminProviderStatus.fromJson(Map<String, dynamic> json) {
    final elsewhere = json['provider_elsewhere'];
    return AdminProviderStatus(
      isProviderEnabled: json['is_provider_enabled'] == true,
      provider: json['provider'] != null
          ? AdminProviderProfile.fromJson(json['provider'] as Map<String, dynamic>)
          : null,
      setupValidation: AdminProviderValidation.fromJson(
        (json['setup_validation'] as Map<String, dynamic>?) ?? {},
      ),
      upcomingAppointmentsCount: int.tryParse('${json['upcoming_appointments_count']}') ?? 0,
      providerElsewhere: elsewhere is Map
          ? ProviderElsewhere.fromJson(Map<String, dynamic>.from(elsewhere))
          : null,
    );
  }
}

/// The other salon where the owner is a service provider.
class ProviderElsewhere {
  final String salonId;
  final String salonName;
  final bool isActive;
  final String message;

  const ProviderElsewhere({
    required this.salonId,
    required this.salonName,
    required this.isActive,
    required this.message,
  });

  factory ProviderElsewhere.fromJson(Map<String, dynamic> json) {
    final name = json['salon_name']?.toString() ?? 'another salon';
    return ProviderElsewhere(
      salonId: json['salon_id']?.toString() ?? '',
      salonName: name,
      isActive: json['is_active'] == true,
      message: json['message']?.toString() ??
          'You already work as a service provider at $name. An owner can be a service provider at only one salon.',
    );
  }
}

/// The server refused because the owner is a service provider at another
/// salon; [message] says which.
class ProviderElsewhereException implements Exception {
  final ProviderElsewhere elsewhere;
  const ProviderElsewhereException(this.elsewhere);

  String get message => elsewhere.message;

  @override
  String toString() => message;
}

class AdminProviderValidation {
  final bool salonHoursConfigured;
  final bool adminHoursConfigured;
  final bool servicesAssigned;
  final bool isReadyForBooking;

  AdminProviderValidation({
    required this.salonHoursConfigured,
    required this.adminHoursConfigured,
    required this.servicesAssigned,
    required this.isReadyForBooking,
  });

  factory AdminProviderValidation.fromJson(Map<String, dynamic> json) {
    return AdminProviderValidation(
      salonHoursConfigured: json['salon_hours_configured'] == true,
      adminHoursConfigured: json['admin_hours_configured'] == true,
      servicesAssigned: json['services_assigned'] == true,
      isReadyForBooking: json['is_ready_for_booking'] == true,
    );
  }
}

class AdminProviderProfile {
  final String id;
  final String userId;
  final String salonId;
  final String? specialization;
  final bool isActive;
  final bool autoApproveLeave;
  final int servicesCount;
  final List<AdminAssignedService> services;
  final List<StaffWorkingHour> workingHours;

  AdminProviderProfile({
    required this.id,
    required this.userId,
    required this.salonId,
    this.specialization,
    required this.isActive,
    required this.autoApproveLeave,
    required this.servicesCount,
    required this.services,
    required this.workingHours,
  });

  factory AdminProviderProfile.fromJson(Map<String, dynamic> json) {
    final hours = (json['working_hours'] as List?)
            ?.map((h) => StaffWorkingHour.fromJson(h as Map<String, dynamic>))
            .toList() ??
        <StaffWorkingHour>[];
    hours.sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

    final srvs = (json['services'] as List?)
            ?.map((s) => AdminAssignedService.fromJson(s as Map<String, dynamic>))
            .toList() ??
        <AdminAssignedService>[];

    return AdminProviderProfile(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      salonId: json['salon_id'] ?? '',
      specialization: json['specialization'],
      isActive: json['is_active'] == true || json['is_active'] == 1,
      autoApproveLeave: json['auto_approve_leave'] == true || json['auto_approve_leave'] == 1,
      servicesCount: int.tryParse('${json['services_count']}') ?? srvs.length,
      services: srvs,
      workingHours: hours,
    );
  }
}

class AdminAssignedService {
  final String id;
  final String name;
  final double price;

  AdminAssignedService({
    required this.id,
    required this.name,
    required this.price,
  });

  factory AdminAssignedService.fromJson(Map<String, dynamic> json) {
    return AdminAssignedService(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      price: double.tryParse('${json['price']}') ?? 0.0,
    );
  }
}
