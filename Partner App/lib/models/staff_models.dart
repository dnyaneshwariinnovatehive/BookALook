class StaffMember {
  final String id;
  final String userId;
  final String salonId;
  final String? specialization;
  final double baseSalary;
  final double commissionPercentage;
  final bool isActive;
  final Map<String, dynamic>? user;
  final List<dynamic>? services;

  StaffMember({
    required this.id,
    required this.userId,
    required this.salonId,
    this.specialization,
    required this.baseSalary,
    required this.commissionPercentage,
    required this.isActive,
    this.user,
    this.services,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'],
      userId: json['user_id'],
      salonId: json['salon_id'],
      specialization: json['specialization'],
      baseSalary: double.tryParse(json['base_salary'].toString()) ?? 0.0,
      commissionPercentage: double.tryParse(json['commission_percentage'].toString()) ?? 0.0,
      isActive: json['is_active'] == 1 || json['is_active'] == true,
      user: json['user'],
      services: json['services'],
    );
  }
}

class StaffWorkingHour {
  final int dayOfWeek;
  bool isWeeklyOff;
  String? shiftStart;
  String? shiftEnd;
  String? breakStart;
  String? breakEnd;

  StaffWorkingHour({
    required this.dayOfWeek,
    required this.isWeeklyOff,
    this.shiftStart,
    this.shiftEnd,
    this.breakStart,
    this.breakEnd,
  });

  Map<String, dynamic> toJson() {
    return {
      'day_of_week': dayOfWeek,
      'is_weekly_off': isWeeklyOff,
      'shift_start': shiftStart,
      'shift_end': shiftEnd,
      'break_start': breakStart,
      'break_end': breakEnd,
    };
  }
}
