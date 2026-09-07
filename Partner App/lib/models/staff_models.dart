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

  /// The shift this provider actually has stored, one entry per weekday.
  /// Empty when the API did not send them.
  final List<StaffWorkingHour> workingHours;

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
    this.workingHours = const [],
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    final hours = (json['working_hours'] as List?)
            ?.map((h) => StaffWorkingHour.fromJson(h as Map<String, dynamic>))
            .toList() ??
        <StaffWorkingHour>[];
    hours.sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

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
      workingHours: hours,
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

  factory StaffWorkingHour.fromJson(Map<String, dynamic> json) {
    return StaffWorkingHour(
      dayOfWeek: json['day_of_week'] is int
          ? json['day_of_week']
          : int.tryParse('${json['day_of_week']}') ?? 0,
      isWeeklyOff: json['is_weekly_off'] == 1 || json['is_weekly_off'] == true,
      shiftStart: normaliseTime(json['shift_start']),
      shiftEnd: normaliseTime(json['shift_end']),
      breakStart: normaliseTime(json['break_start']),
      breakEnd: normaliseTime(json['break_end']),
    );
  }

  StaffWorkingHour copy() => StaffWorkingHour(
        dayOfWeek: dayOfWeek,
        isWeeklyOff: isWeeklyOff,
        shiftStart: shiftStart,
        shiftEnd: shiftEnd,
        breakStart: breakStart,
        breakEnd: breakEnd,
      );

  /// True when this day matches [other] — used to decide whether a provider is
  /// still on the salon's hours or has been given a custom shift.
  bool sameShiftAs(StaffWorkingHour other) =>
      isWeeklyOff == other.isWeeklyOff &&
      shiftStart == other.shiftStart &&
      shiftEnd == other.shiftEnd;

  /// The API can send `09:00`, `09:00:00` or a full timestamp; the write side
  /// always requires `H:i:s`.
  static String? normaliseTime(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty) return null;

    final match = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(text);
    if (match == null) return null;

    final hour = match.group(1)!.padLeft(2, '0');
    final minute = match.group(2)!;
    final second = match.group(3) ?? '00';
    return '$hour:$minute:$second';
  }

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
