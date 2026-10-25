import 'package:flutter/material.dart';

import '../models/salon_working_hour.dart';
import '../models/staff_models.dart';
import '../services/staff_api.dart';
import '../theme/app_theme.dart';

/// Saves one provider's choice. [followSalon] true means "use the salon's
/// hours" (the server copies them); false means [hours] is their own shift.
typedef SaveStaffHours = Future<void> Function({
  required String salonId,
  required String staffId,
  required bool followSalon,
  List<StaffWorkingHour>? hours,
});

Future<void> _saveWithApi({
  required String salonId,
  required String staffId,
  required bool followSalon,
  List<StaffWorkingHour>? hours,
}) {
  return StaffApi.updateStaff(
    salonId: salonId,
    staffId: staffId,
    useSalonWorkingHours: followSalon,
    workingHours: followSalon ? null : hours,
  );
}

/// Shown right after the owner saves new salon hours: every provider, with
/// the choice to put them on the new salon hours or give them their own.
///
/// Providers already following the salon have been moved over by the server;
/// they are listed so the owner can see it, and can still opt one out.
/// Returns how many providers were changed, or null when skipped.
Future<int?> showStaffHoursReviewSheet(
  BuildContext context, {
  required String salonId,
  required List<StaffMember> staff,
  required List<SalonWorkingHour> salonHours,
  SaveStaffHours save = _saveWithApi,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => StaffHoursReviewSheet(
      salonId: salonId,
      staff: staff,
      salonHours: salonHours,
      save: save,
    ),
  );
}

class StaffHoursReviewSheet extends StatefulWidget {
  final String salonId;
  final List<StaffMember> staff;
  final List<SalonWorkingHour> salonHours;
  final SaveStaffHours save;

  const StaffHoursReviewSheet({
    super.key,
    required this.salonId,
    required this.staff,
    required this.salonHours,
    this.save = _saveWithApi,
  });

  @override
  State<StaffHoursReviewSheet> createState() => _StaffHoursReviewSheetState();
}

class _ProviderDraft {
  final StaffMember member;
  bool followSalon;
  bool expanded = false;
  bool edited = false;
  final List<StaffWorkingHour> hours;

  _ProviderDraft(this.member, this.hours) : followSalon = member.useSalonHours;

  bool get changed => followSalon != member.useSalonHours || (!followSalon && edited);
}

class _StaffHoursReviewSheetState extends State<StaffHoursReviewSheet> {
  static const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  late final List<_ProviderDraft> _drafts;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _drafts = widget.staff.where((s) => s.isActive).map((s) {
      // Start a custom schedule from what they have, or from the salon's
      // hours when nothing is stored yet.
      final hours = s.workingHours.length == 7
          ? s.workingHours.map((h) => h.copy()).toList()
          : widget.salonHours.map(_fromSalon).toList();
      return _ProviderDraft(s, hours);
    }).toList();
  }

  StaffWorkingHour _fromSalon(SalonWorkingHour h) => StaffWorkingHour(
        dayOfWeek: h.dayOfWeek,
        isWeeklyOff: h.isClosed,
        shiftStart: h.isClosed ? null : StaffWorkingHour.normaliseTime(h.openTime),
        shiftEnd: h.isClosed ? null : StaffWorkingHour.normaliseTime(h.closeTime),
      );

  SalonWorkingHour? _salonDay(int day) {
    for (final h in widget.salonHours) {
      if (h.dayOfWeek == day) return h;
    }
    return null;
  }

  static int _minutes(String? t) {
    final parts = (t ?? '').split(':');
    if (parts.length < 2) return -1;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  /// Days on which a custom shift now falls outside the salon's hours.
  List<String> _conflicts(_ProviderDraft d) {
    if (d.followSalon) return const [];
    final out = <String>[];
    for (final h in d.hours) {
      if (h.isWeeklyOff) continue;
      final salon = _salonDay(h.dayOfWeek);
      if (salon == null) continue;
      if (salon.isClosed ||
          _minutes(h.shiftStart) < _minutes(salon.openTime) ||
          _minutes(h.shiftEnd) > _minutes(salon.closeTime)) {
        out.add(_days[h.dayOfWeek]);
      }
    }
    return out;
  }

  String _fmt(String? t) {
    final m = _minutes(t);
    if (m < 0) return '--';
    final h = m ~/ 60, min = m % 60;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${min.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _pickTime(_ProviderDraft d, StaffWorkingHour h, {required bool start}) async {
    final current = start ? h.shiftStart : h.shiftEnd;
    final m = _minutes(current);
    final picked = await showTimePicker(
      context: context,
      initialTime: m < 0 ? const TimeOfDay(hour: 10, minute: 0) : TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (picked == null) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
    setState(() {
      if (start) {
        h.shiftStart = value;
      } else {
        h.shiftEnd = value;
      }
      d.edited = true;
    });
  }

  String? _invalid(_ProviderDraft d) {
    if (d.followSalon) return null;
    for (final h in d.hours) {
      if (h.isWeeklyOff) continue;
      if (h.shiftStart == null || h.shiftEnd == null) {
        return '${d.member.user?['name'] ?? 'A provider'}: set both times for ${_days[h.dayOfWeek]}.';
      }
      if (_minutes(h.shiftEnd) <= _minutes(h.shiftStart)) {
        return '${d.member.user?['name'] ?? 'A provider'}: ${_days[h.dayOfWeek]} must end after it starts.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    for (final d in _drafts.where((d) => d.changed)) {
      final problem = _invalid(d);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    var updated = 0;
    final failed = <String>[];
    for (final d in _drafts.where((d) => d.changed)) {
      try {
        await widget.save(
          salonId: widget.salonId,
          staffId: d.member.id,
          followSalon: d.followSalon,
          hours: d.followSalon ? null : d.hours,
        );
        updated++;
      } catch (_) {
        failed.add(d.member.user?['name']?.toString() ?? 'a provider');
      }
    }

    if (!mounted) return;
    if (failed.isNotEmpty) {
      setState(() {
        _saving = false;
        _error = 'Could not update ${failed.join(', ')}. Try again.';
      });
      return;
    }
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Update staff hours?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Salon hours are saved. Choose, for each person, whether they work the new salon hours or their own.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [for (final d in _drafts) _providerCard(d)],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('staff_hours_skip'),
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      key: const ValueKey('staff_hours_save'),
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save staff hours'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerCard(_ProviderDraft d) {
    final name = d.member.user?['name']?.toString() ?? 'Staff member';
    final conflicts = _conflicts(d);

    return Container(
      key: ValueKey('staff_hours_card_${d.member.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: conflicts.isNotEmpty ? Colors.orange.shade300 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.member.isAdminProvider ? '$name (You)' : name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              const Text('Use salon hours', style: TextStyle(fontSize: 12)),
              Switch(
                key: ValueKey('staff_hours_follow_${d.member.id}'),
                value: d.followSalon,
                onChanged: (v) => setState(() {
                  d.followSalon = v;
                  if (!v) d.expanded = true;
                }),
              ),
            ],
          ),
          if (d.followSalon)
            Text('Works the new salon hours.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
          else ...[
            if (conflicts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Outside the new salon hours on ${conflicts.join(', ')}.',
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            InkWell(
              onTap: () => setState(() => d.expanded = !d.expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(d.expanded ? 'Hide custom hours' : 'Edit custom hours',
                        style: const TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.w600, fontSize: 13)),
                    Icon(d.expanded ? Icons.expand_less : Icons.expand_more, color: AppTheme.accentColor, size: 18),
                  ],
                ),
              ),
            ),
            if (d.expanded) ...d.hours.map((h) => _dayRow(d, h)),
          ],
        ],
      ),
    );
  }

  Widget _dayRow(_ProviderDraft d, StaffWorkingHour h) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(_days[h.dayOfWeek], style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: h.isWeeklyOff
                ? Text('Off', style: TextStyle(color: Colors.grey.shade600))
                : Row(
                    children: [
                      TextButton(onPressed: () => _pickTime(d, h, start: true), child: Text(_fmt(h.shiftStart))),
                      const Text('–'),
                      TextButton(onPressed: () => _pickTime(d, h, start: false), child: Text(_fmt(h.shiftEnd))),
                    ],
                  ),
          ),
          const Text('Off', style: TextStyle(fontSize: 12)),
          Checkbox(
            value: h.isWeeklyOff,
            onChanged: (v) => setState(() {
              h.isWeeklyOff = v ?? false;
              if (!h.isWeeklyOff) {
                final salon = _salonDay(h.dayOfWeek);
                h.shiftStart ??= StaffWorkingHour.normaliseTime(salon?.openTime) ?? '10:00:00';
                h.shiftEnd ??= StaffWorkingHour.normaliseTime(salon?.closeTime) ?? '19:00:00';
              }
              d.edited = true;
            }),
          ),
        ],
      ),
    );
  }
}
