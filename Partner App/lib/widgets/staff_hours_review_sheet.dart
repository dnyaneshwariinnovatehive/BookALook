import 'package:flutter/material.dart';

import '../models/salon_working_hour.dart';
import '../models/staff_models.dart';
import '../services/salon_settings_api.dart';
import '../services/staff_api.dart';
import '../theme/app_theme.dart';

/// Saves one staff member's custom week.
typedef SaveStaffHours = Future<void> Function({
  required String salonId,
  required String staffId,
  required List<StaffWorkingHour> hours,
});

Future<void> _saveWithApi({
  required String salonId,
  required String staffId,
  required List<StaffWorkingHour> hours,
}) {
  return StaffApi.updateStaff(
    salonId: salonId,
    staffId: staffId,
    useSalonWorkingHours: false,
    workingHours: hours,
  );
}

const _dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/// One day whose salon hours just changed.
class SalonDayChange {
  final int dayOfWeek;
  final SalonWorkingHour before;
  final SalonWorkingHour after;

  const SalonDayChange({required this.dayOfWeek, required this.before, required this.after});

  bool get nowClosed => after.isClosed;
  bool get newlyOpen => before.isClosed && !after.isClosed;
}

/// "09:00", "09:00:00" and "9:00" all read as the same time.
String? _hm(String? t) {
  final parts = (t ?? '').split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

int _minutes(String? t) {
  final hm = _hm(t);
  if (hm == null) return -1;
  final parts = hm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String _fmt(String? t) {
  final m = _minutes(t);
  if (m < 0) return '--';
  final h = m ~/ 60, min = m % 60;
  final suffix = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${min.toString().padLeft(2, '0')} $suffix';
}

String _salonText(SalonWorkingHour h) => h.isClosed ? 'closed' : '${_fmt(h.openTime)} – ${_fmt(h.closeTime)}';

/// The days whose salon hours differ between [before] and [after].
List<SalonDayChange> salonHourChanges(List<SalonWorkingHour> before, List<SalonWorkingHour> after) {
  final changes = <SalonDayChange>[];
  for (final now in after) {
    final was = before.where((b) => b.dayOfWeek == now.dayOfWeek).firstOrNull;
    if (was == null) continue;

    final same = was.isClosed == now.isClosed &&
        (now.isClosed || (_hm(was.openTime) == _hm(now.openTime) && _hm(was.closeTime) == _hm(now.closeTime)));
    if (!same) changes.add(SalonDayChange(dayOfWeek: now.dayOfWeek, before: was, after: now));
  }
  changes.sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
  return changes;
}

/// Whether the sheet has anything to ask or warn about.
bool staffHoursSheetNeeded({
  required List<SalonDayChange> changes,
  required List<StaffMember> staff,
  required WorkingHoursSaveResult result,
}) {
  final hasCustom = staff.any((s) => s.isActive && !s.useSalonHours);
  final askableDay = changes.any((c) => !c.nowClosed);
  return (hasCustom && askableDay) || result.bookingsOutsideHours.isNotEmpty || result.trimmed.isNotEmpty;
}

/// Shown after the owner saves new salon hours.
///
/// Staff on salon hours were moved by the server and are only mentioned.
/// Staff on their own hours are asked about **only the days that changed**:
/// keep their shift, extend it to the new salon hours, or set a time. Shifts
/// that no longer fitted were already trimmed by the server and say so, and
/// bookings now outside the hours are flagged but never moved.
///
/// Returns how many staff schedules were changed, or null when skipped.
Future<int?> showStaffHoursReviewSheet(
  BuildContext context, {
  required String salonId,
  required List<StaffMember> staff,
  required List<SalonDayChange> changes,
  WorkingHoursSaveResult result = const WorkingHoursSaveResult(),
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
      changes: changes,
      result: result,
      save: save,
    ),
  );
}

enum DayChoice { keep, salon, custom }

class _Row {
  final StaffMember member;
  final SalonDayChange change;
  final StaffWorkingHour current;
  final TrimmedShift? trimmed;
  DayChoice choice = DayChoice.keep;
  String? start;
  String? end;

  _Row(this.member, this.change, this.current, this.trimmed);

  bool get offNow => current.isWeeklyOff || current.shiftStart == null || current.shiftEnd == null;
}

class StaffHoursReviewSheet extends StatefulWidget {
  final String salonId;
  final List<StaffMember> staff;
  final List<SalonDayChange> changes;
  final WorkingHoursSaveResult result;
  final SaveStaffHours save;

  const StaffHoursReviewSheet({
    super.key,
    required this.salonId,
    required this.staff,
    required this.changes,
    this.result = const WorkingHoursSaveResult(),
    this.save = _saveWithApi,
  });

  @override
  State<StaffHoursReviewSheet> createState() => _StaffHoursReviewSheetState();
}

class _StaffHoursReviewSheetState extends State<StaffHoursReviewSheet> {
  late final List<StaffMember> _following;
  late final List<StaffMember> _custom;
  late final List<_Row> _rows;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final active = widget.staff.where((s) => s.isActive).toList();
    _following = active.where((s) => s.useSalonHours).toList();
    _custom = active.where((s) => !s.useSalonHours).toList();

    _rows = [
      for (final change in widget.changes.where((c) => !c.nowClosed))
        for (final member in _custom)
          _Row(
            member,
            change,
            _dayOf(member, change.dayOfWeek),
            widget.result.trimmed
                .where((t) => t.providerId == member.id && t.dayOfWeek == change.dayOfWeek)
                .firstOrNull,
          ),
    ];
  }

  StaffWorkingHour _dayOf(StaffMember m, int day) =>
      m.workingHours.where((h) => h.dayOfWeek == day).firstOrNull ??
      StaffWorkingHour(dayOfWeek: day, isWeeklyOff: true);

  String _name(StaffMember m) {
    final n = m.user?['name']?.toString() ?? 'Staff member';
    return m.isAdminProvider ? '$n (You)' : n;
  }

  void _extendEveryone() {
    setState(() {
      for (final r in _rows) {
        r.choice = DayChoice.salon;
      }
    });
  }

  Future<void> _pick(_Row r, {required bool start}) async {
    final current = start ? (r.start ?? r.current.shiftStart ?? r.change.after.openTime) : (r.end ?? r.current.shiftEnd ?? r.change.after.closeTime);
    final m = _minutes(current);
    final picked = await showTimePicker(
      context: context,
      initialTime: m < 0 ? const TimeOfDay(hour: 10, minute: 0) : TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (picked == null || !mounted) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
    setState(() {
      r.choice = DayChoice.custom;
      r.start ??= StaffWorkingHour.normaliseTime(r.current.shiftStart ?? r.change.after.openTime);
      r.end ??= StaffWorkingHour.normaliseTime(r.current.shiftEnd ?? r.change.after.closeTime);
      if (start) {
        r.start = value;
      } else {
        r.end = value;
      }
    });
  }

  String? _problem(_Row r) {
    if (r.choice != DayChoice.custom) return null;
    final s = _minutes(r.start), e = _minutes(r.end);
    final day = _dayNames[r.change.dayOfWeek];
    if (s < 0 || e < 0) return '${_name(r.member)}: set both times for $day.';
    if (e <= s) return '${_name(r.member)}: $day must end after it starts.';
    if (s < _minutes(r.change.after.openTime) || e > _minutes(r.change.after.closeTime)) {
      return '${_name(r.member)}: $day must be within the salon hours (${_salonText(r.change.after)}).';
    }
    return null;
  }

  Future<void> _save() async {
    for (final r in _rows) {
      final p = _problem(r);
      if (p != null) {
        setState(() => _error = p);
        return;
      }
    }

    final byMember = <String, List<_Row>>{};
    for (final r in _rows.where((r) => r.choice != DayChoice.keep)) {
      byMember.putIfAbsent(r.member.id, () => []).add(r);
    }

    if (byMember.isEmpty) {
      Navigator.pop(context, 0);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    var updated = 0;
    final failed = <String>[];

    for (final entry in byMember.entries) {
      final member = entry.value.first.member;
      // Their whole week as it is, with only the changed days replaced.
      final week = [for (var d = 0; d < 7; d++) _dayOf(member, d).copy()];
      for (final r in entry.value) {
        final day = week[r.change.dayOfWeek];
        day.isWeeklyOff = false;
        if (r.choice == DayChoice.salon) {
          day.shiftStart = StaffWorkingHour.normaliseTime(r.change.after.openTime);
          day.shiftEnd = StaffWorkingHour.normaliseTime(r.change.after.closeTime);
        } else {
          day.shiftStart = r.start;
          day.shiftEnd = r.end;
        }
        // A break that no longer fits the new shift is dropped.
        if (day.breakStart != null &&
            (_minutes(day.breakStart) < _minutes(day.shiftStart) || _minutes(day.breakEnd) > _minutes(day.shiftEnd))) {
          day.breakStart = null;
          day.breakEnd = null;
        }
      }

      try {
        await widget.save(salonId: widget.salonId, staffId: member.id, hours: week);
        updated++;
      } catch (_) {
        failed.add(_name(member));
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
    final closedDays = widget.changes.where((c) => c.nowClosed).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text('Staff hours for the new salon times',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Salon hours are saved. Choose what happens to staff on their own hours, for the days that changed.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (widget.result.bookingsOutsideHours.isNotEmpty) _bookingsWarning(),
                if (_following.isNotEmpty) _followingNote(),
                for (final c in closedDays) _closedNote(c),
                if (_rows.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const ValueKey('staff_hours_extend_all'),
                      onPressed: _saving ? null : _extendEveryone,
                      icon: const Icon(Icons.open_in_full_rounded, size: 16),
                      label: const Text('Extend everyone to salon hours'),
                    ),
                  ),
                  for (final change in widget.changes.where((c) => !c.nowClosed)) _daySection(change),
                ],
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(_error!, key: const ValueKey('staff_hours_error'), style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _rows.isEmpty
                ? ElevatedButton(
                    key: const ValueKey('staff_hours_done'),
                    onPressed: () => Navigator.pop(context, 0),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor, foregroundColor: Colors.white),
                    child: const Text('Done'),
                  )
                : Row(
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
    );
  }

  Widget _note({required Key key, required IconData icon, required Color color, required String text}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.35))),
        ],
      ),
    );
  }

  Widget _bookingsWarning() {
    final parts = widget.result.bookingsOutsideHours.entries
        .map((e) => '${e.value} on ${_dayNames[e.key]}')
        .join(', ');
    final total = widget.result.bookingsOutsideHours.values.fold<int>(0, (a, b) => a + b);
    return _note(
      key: const ValueKey('staff_hours_bookings_warning'),
      icon: Icons.warning_amber_rounded,
      color: Colors.orange.shade800,
      text: '$total upcoming booking${total == 1 ? '' : 's'} now fall${total == 1 ? 's' : ''} outside the salon hours '
          '($parts). They have not been moved — contact the customers or reschedule them.',
    );
  }

  Widget _followingNote() {
    final names = _following.map(_name).join(', ');
    return _note(
      key: const ValueKey('staff_hours_following_note'),
      icon: Icons.sync_rounded,
      color: AppTheme.accentColor,
      text: '$names ${_following.length == 1 ? 'follows' : 'follow'} salon hours — moved to the new times.',
    );
  }

  Widget _closedNote(SalonDayChange c) {
    return _note(
      key: ValueKey('staff_hours_closed_${c.dayOfWeek}'),
      icon: Icons.event_busy_rounded,
      color: Colors.grey.shade700,
      text: '${_dayNames[c.dayOfWeek]} — salon now closed. Everyone is off that day.',
    );
  }

  Widget _daySection(SalonDayChange change) {
    final rows = _rows.where((r) => r.change.dayOfWeek == change.dayOfWeek).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      key: ValueKey('staff_hours_day_${change.dayOfWeek}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_dayNames[change.dayOfWeek], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(
            'Salon now ${_salonText(change.after)} (was ${_salonText(change.before)})',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
          ),
          const Divider(height: 18),
          for (final r in rows) _row(r),
        ],
      ),
    );
  }

  Widget _row(_Row r) {
    final keepLabel = r.offNow ? 'Stay off' : 'Keep ${_fmt(r.current.shiftStart)} – ${_fmt(r.current.shiftEnd)}';
    final salonLabel = r.offNow
        ? 'Work ${_fmt(r.change.after.openTime)} – ${_fmt(r.change.after.closeTime)}'
        : 'Extend to ${_fmt(r.change.after.openTime)} – ${_fmt(r.change.after.closeTime)}';
    final id = '${r.member.id}_${r.change.dayOfWeek}';

    return Padding(
      key: ValueKey('staff_hours_row_$id'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(_name(r.member), style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(
                r.offNow ? 'Off' : 'Works ${_fmt(r.current.shiftStart)} – ${_fmt(r.current.shiftEnd)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          if (r.trimmed != null && !r.trimmed!.becameDayOff)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Trimmed from ${_fmt(r.trimmed!.fromStart)} – ${_fmt(r.trimmed!.fromEnd)} to fit the salon hours.',
                key: ValueKey('staff_hours_trimmed_$id'),
                style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                key: ValueKey('staff_hours_keep_$id'),
                label: Text(keepLabel),
                selected: r.choice == DayChoice.keep,
                onSelected: _saving ? null : (_) => setState(() => r.choice = DayChoice.keep),
              ),
              ChoiceChip(
                key: ValueKey('staff_hours_salon_$id'),
                label: Text(salonLabel),
                selected: r.choice == DayChoice.salon,
                onSelected: _saving ? null : (_) => setState(() => r.choice = DayChoice.salon),
              ),
              ChoiceChip(
                key: ValueKey('staff_hours_custom_$id'),
                label: Text(r.choice == DayChoice.custom ? '${_fmt(r.start)} – ${_fmt(r.end)}' : 'Set time…'),
                selected: r.choice == DayChoice.custom,
                onSelected: _saving ? null : (_) => _pick(r, start: true),
              ),
            ],
          ),
          if (r.choice == DayChoice.custom)
            Row(
              children: [
                TextButton(onPressed: _saving ? null : () => _pick(r, start: true), child: Text('Start ${_fmt(r.start)}')),
                TextButton(onPressed: _saving ? null : () => _pick(r, start: false), child: Text('End ${_fmt(r.end)}')),
              ],
            ),
        ],
      ),
    );
  }
}
