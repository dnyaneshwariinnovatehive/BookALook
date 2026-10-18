import 'staff_models.dart';

class AdminProviderStatus {
  final bool isProviderEnabled;
  final AdminProviderProfile? provider;
  final AdminProviderValidation setupValidation;
  final int upcomingAppointmentsCount;

  AdminProviderStatus({
    required this.isProviderEnabled,
    this.provider,
    required this.setupValidation,
    required this.upcomingAppointmentsCount,
  });

  factory AdminProviderStatus.fromJson(Map<String, dynamic> json) {
    return AdminProviderStatus(
      isProviderEnabled: json['is_provider_enabled'] == true,
      provider: json['provider'] != null
          ? AdminProviderProfile.fromJson(json['provider'] as Map<String, dynamic>)
          : null,
      setupValidation: AdminProviderValidation.fromJson(
        (json['setup_validation'] as Map<String, dynamic>?) ?? {},
      ),
      upcomingAppointmentsCount: int.tryParse('${json['upcoming_appointments_count']}') ?? 0,
    );
  }
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
