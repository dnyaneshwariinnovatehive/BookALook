class ProviderLeave {
  final String id;
  final String providerId;
  final String leaveDate;
  final String leaveType;
  final bool isFullDay;
  final String? startTime;
  final String? endTime;
  final String? reason;
  String status;
  final Map<String, dynamic>? provider;

  ProviderLeave({
    required this.id,
    required this.providerId,
    required this.leaveDate,
    required this.leaveType,
    required this.isFullDay,
    this.startTime,
    this.endTime,
    this.reason,
    required this.status,
    this.provider,
  });

  factory ProviderLeave.fromJson(Map<String, dynamic> json) {
    return ProviderLeave(
      id: json['id'],
      providerId: json['provider_id'],
      leaveDate: json['leave_date'],
      leaveType: json['leave_type'],
      isFullDay: json['is_full_day'] == 1 || json['is_full_day'] == true,
      startTime: json['start_time'],
      endTime: json['end_time'],
      reason: json['reason'],
      status: json['status'],
      provider: json['provider'],
    );
  }
}
