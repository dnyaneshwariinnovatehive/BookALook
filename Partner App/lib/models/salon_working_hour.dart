class SalonWorkingHour {
  final int dayOfWeek;
  bool isClosed;
  String? openTime;
  String? closeTime;

  SalonWorkingHour({
    required this.dayOfWeek,
    required this.isClosed,
    this.openTime,
    this.closeTime,
  });

  factory SalonWorkingHour.fromJson(Map<String, dynamic> json) {
    return SalonWorkingHour(
      dayOfWeek: json['day_of_week'],
      isClosed: json['is_closed'] == 1 || json['is_closed'] == true,
      openTime: json['open_time'],
      closeTime: json['close_time'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day_of_week': dayOfWeek,
      'is_closed': isClosed,
      'open_time': openTime,
      'close_time': closeTime,
    };
  }
}
