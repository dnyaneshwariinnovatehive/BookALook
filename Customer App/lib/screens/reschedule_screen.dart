import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';
import '../utils/app_haptics.dart';
import '../widgets/initials_avatar.dart';
import '../theme/app_colors.dart';
import '../utils/error_text.dart';
import '../widgets/feedback_states.dart';

/// Moves an existing booking to a new provider / date / slot. Same availability
/// rules as checkout — the booking's own slot does not block itself.
class RescheduleScreen extends StatefulWidget {
  final String appointmentId;

  /// Salon-announced closure on the original date: the reschedule is free and
  /// the cancellation cutoff is waived.
  final bool freeReschedule;

  const RescheduleScreen({
    Key? key,
    required this.appointmentId,
    this.freeReschedule = false,
  }) : super(key: key);

  @override
  State<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends State<RescheduleScreen> {
  final AppointmentService _appointmentService = AppointmentService();

  List<dynamic> _providers = [];
  bool _isLoadingOptions = true;
  String _error = '';

  /// The chosen staff member's id. Always a named person — the booked
  /// provider is the one who scans the customer in.
  String? _selectedProviderKey;
  DateTime? _selectedDate;
  String? _selectedTime;

  List<dynamic> _slots = [];
  bool _isLoadingSlots = false;
  bool _isClosed = false;
  String? _closedReason;

  int _totalDuration = 0;
  String? _currentDate;
  String? _currentTime;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _isLoadingOptions = true;
      _error = '';
    });

    try {
      final data = await _appointmentService.getRescheduleOptions(widget.appointmentId);
      setState(() {
        _providers = data['providers'] ?? [];
        _totalDuration = (data['total_duration_minutes'] ?? 0) as int;
        _currentDate = data['current_date'];
        _currentTime = data['current_time'];
        // Pre-select the staff member who is already assigned.
        _selectedProviderKey = data['current_provider_id']?.toString();
        _selectedDate = _currentDate != null ? DateTime.parse(_currentDate!) : DateTime.now();
        _isLoadingOptions = false;
      });

      if (_selectedProviderKey != null) _fetchSlots();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoadingOptions = false;
      });
    }
  }

  Future<void> _fetchSlots() async {
    if (_selectedProviderKey == null || _selectedDate == null) return;

    setState(() {
      _isLoadingSlots = true;
      _slotsError = null;
      _selectedTime = null;
      _slots = [];
      _isClosed = false;
      _closedReason = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final data = await _appointmentService.getRescheduleOptions(
        widget.appointmentId,
        date: dateStr,
        providerId: _selectedProviderKey,
      );

      setState(() {
        _slots = data['slots'] ?? [];
        _isClosed = data['closed'] == true;
        _closedReason = data['closed_reason'];
        _isLoadingSlots = false;
      });
    } catch (e) {
      setState(() {
        _slots = [];
        _isLoadingSlots = false;
        _slotsError = describeError(e, fallback: 'Could not load the time slots.');
      });
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 30)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: AppTheme.accentColor),
        ),
        child: child!,
      ),
    );

    if (date != null) {
      AppHaptics.selectionClick();
      setState(() => _selectedDate = date);
      _fetchSlots();
    }
  }

  /// Who the customer has picked, in words rather than as an id.
  String get _selectedProviderName {
    if (_selectedProviderKey == null) {
      return 'Assigned staff';
    }
    for (final provider in _providers) {
      if (provider['id'].toString() == _selectedProviderKey) {
        return (provider['name'] ?? 'Staff').toString();
      }
    }
    return 'Assigned staff';
  }

  /// "14:30" or "14:30:00" as "2:30 PM", so the old and new slots read the
  /// same way in the confirmation.
  String _prettyTime(String? time) {
    if (time == null || time.isEmpty) return '—';
    final parts = time.split(':');
    if (parts.length < 2) return time;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return time;
    final suffix = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }

  /// The move is committed server-side as soon as it is pressed, so the
  /// customer is shown the old slot, the new slot and what happens to their
  /// money before it happens.
  Future<bool> _confirmReschedule() async {
    final textHeading = context.colors.textPrimary;
    final textBody = context.colors.textSecondary;
    final textLight = context.colors.textTertiary;
    final accent = AppTheme.accentColor;
    final softBg = context.colors.accentSoft;
    final surface = context.colors.surface;

    final fromDate = _currentDate == null
        ? '—'
        : DateFormat('EEE, MMM d').format(DateTime.parse(_currentDate!));
    final toDate = _selectedDate == null
        ? '—'
        : DateFormat('EEE, MMM d').format(_selectedDate!);

    final sameSlot = _currentDate == DateFormat('yyyy-MM-dd').format(_selectedDate!) &&
        _currentTime == _selectedTime;

    AppHaptics.lightImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: surface,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        title: Text('Reschedule this booking?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20, color: textHeading)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _slotRow('From', '$fromDate · ${_prettyTime(_currentTime)}',
                context.colors.textTertiary, textBody, textLight, !sameSlot),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Icon(Icons.arrow_downward, size: 16, color: textLight),
            ),
            _slotRow('To', '$toDate · ${_prettyTime(_selectedTime)}', accent, accent, textLight, false),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: softBg, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('With $_selectedProviderName',
                      style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: textHeading)),
                  const SizedBox(height: 4),
                  Text(
                    widget.freeReschedule
                        ? 'Free reschedule — the salon closed your original date, so your advance carries over untouched.'
                        : 'Your advance already paid carries over to the new slot. There is nothing more to pay.',
                    style: GoogleFonts.outfit(fontSize: 12, color: textBody),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              sameSlot
                  ? 'This is the slot you are already booked for, so nothing will change.'
                  : 'Your original slot is released. This cannot be undone from here.',
              style: GoogleFonts.outfit(fontSize: 12, color: textLight),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(dialogContext, false);
            },
            child: Text('Go back', style: GoogleFonts.outfit(color: textBody)),
          ),
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(dialogContext, true);
            },
            child: Text(sameSlot ? 'Confirm' : 'Confirm new slot',
                style: GoogleFonts.outfit(color: accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Widget _slotRow(
    String label,
    String value,
    Color valueColor,
    Color labelColor,
    Color textLight,
    bool muted,
  ) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 13, fontWeight: FontWeight.w600, color: labelColor)),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: valueColor,
                decoration: muted ? TextDecoration.lineThrough : TextDecoration.none,
                decorationColor: textLight,
              ),
            ),
          ),
        ],
      );

  Future<void> _confirm() async {
    if (_selectedTime == null || _selectedDate == null) return;

    if (!await _confirmReschedule()) return;

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final result = await _appointmentService.rescheduleAppointment(
        widget.appointmentId,
        dateStr,
        _selectedTime!,
        providerId: _selectedProviderKey,
      );

      if (!mounted) return;
      setState(() => _isSaving = false);
      Navigator.pop(context, true);
      AppHaptics.mediumImpact();
      _toast(result['message'] ?? 'Appointment rescheduled.');
    } catch (e) {
      AppHaptics.error();
      setState(() {
        _isSaving = false;
        _saveError = describeError(e, fallback: 'Could not move your booking. Please try again.');
      });
      _fetchSlots(); // the slot may have been taken meanwhile
    }
  }

  /// Inline feedback, next to what it is about: a failed save above the
  /// Confirm button, a failed slot load in the time section, and a hint
  /// under the section whose greyed-out item was tapped.
  String? _saveError;
  String? _slotsError;
  String? _providerHint;
  String? _dateHint;
  String? _slotHint;

  /// Confirmations only: shown as the screen closes, so vanishing is fine.
  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _hint(String? text, VoidCallback onDismiss) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InlineStatus(message: text, kind: StatusKind.info, onDismiss: onDismiss),
    );
  }

  String _reasonLabel(String? reason) {
    switch (reason) {
      case 'booked':
        return 'Already booked';
      case 'break':
        return 'On a break';
      case 'on_leave':
        return 'On leave';
      case 'provider_off':
        return 'Weekly off';
      case 'outside_shift':
        return 'Outside working hours';
      case 'salon_closing':
        return 'Not enough time before the salon closes';
      case 'past':
        return 'This time has already passed';
      default:
        return 'Unavailable';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reschedule')),
      body: _isLoadingOptions
          ? Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(_error,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(color: context.colors.danger, fontSize: 16)),
                  ),
                )
              : _buildBody(),
      bottomNavigationBar: _isLoadingOptions || _error.isNotEmpty ? null : _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.freeReschedule)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: 20),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.infoBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: context.colors.info),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'The salon is closed on your original date. This reschedule is free — your advance carries over.',
                      style: GoogleFonts.outfit(fontSize: 13, color: context.colors.info),
                    ),
                  ),
                ],
              ),
            ),

          if (_currentDate != null)
            Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Text(
                'Currently booked for ${DateFormat('EEE, MMM d').format(DateTime.parse(_currentDate!))} at $_currentTime.',
                style: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary),
              ),
            ),

          _sectionTitle('1. Service Provider'),
          SizedBox(height: 12),
          _buildProviderList(),
          _hint(_providerHint, () => setState(() => _providerHint = null)),

          SizedBox(height: 32),
          _sectionTitle('2. New Date'),
          SizedBox(height: 12),
          _buildDateField(),
          _hint(_dateHint, () => setState(() => _dateHint = null)),

          SizedBox(height: 32),
          _sectionTitle('3. New Time'),
          if (_totalDuration > 0) ...[
            SizedBox(height: 4),
            Text('Your services take about $_totalDuration minutes.',
                style: GoogleFonts.outfit(fontSize: 13, color: context.colors.textSecondary)),
          ],
          SizedBox(height: 16),
          _buildSlots(),
          _hint(_slotHint, () => setState(() => _slotHint = null)),
          SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
      );

  Widget _buildProviderList() {
    if (_providers.isEmpty) {
      return Text('This salon has no staff available right now.',
          style: GoogleFonts.outfit(color: context.colors.textSecondary));
    }

    return Column(
      children: [
        ..._providers.map((provider) {
          final isEligible = provider['is_eligible'] == true;
          final missing = (provider['missing_service_names'] as List?)?.cast<String>() ?? [];

          return _providerTile(
            key: provider['id'].toString(),
            name: provider['name'] ?? 'Staff',
            subtitle: isEligible
                ? (provider['specialization'] ?? 'Available for all your services')
                : 'Does not perform: ${missing.join(', ')}',
            isEligible: isEligible,
          );
        }),
      ],
    );
  }

  Widget _providerTile({
    required String key,
    required String name,
    required String? subtitle,
    required bool isEligible,
  }) {
    final isSelected = _selectedProviderKey == key;

    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isEligible
            ? () {
                AppHaptics.selectionClick();
                setState(() {
                  _selectedProviderKey = key;
                  _providerHint = null;
                  _dateHint = null;
                  _slotHint = null;
                  _selectedTime = null;
                });
                _fetchSlots();
              }
            : () {
                AppHaptics.error();
                setState(() => _providerHint = '$name cannot perform every service in this booking.');
              },
        child: Opacity(
          opacity: isEligible ? 1.0 : 0.5,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? context.colors.accentSoft : context.colors.surface,
              border: Border.all(
                color: isSelected ? AppTheme.accentColor : context.colors.border,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                // Initials rather than a photo: no human role has one, and a
                // silhouette here reads as a failed image.
                InitialsAvatar(name: name, radius: 22, dimmed: !isEligible),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: GoogleFonts.outfit(
                              fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        SizedBox(height: 2),
                        Text(subtitle,
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: isEligible ? context.colors.textSecondary : context.colors.danger)),
                      ],
                    ],
                  ),
                ),
                if (isSelected) Icon(Icons.check_circle, color: AppTheme.accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateField() {
    final enabled = _selectedProviderKey != null;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: enabled
            ? _pickDate
            : () {
                AppHaptics.error();
                setState(() => _dateHint = 'Choose a service provider first.');
              },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border.all(color: context.colors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedDate == null
                    ? 'Pick a date'
                    : DateFormat('EEEE, MMM d, yyyy').format(_selectedDate!),
                style: GoogleFonts.outfit(fontSize: 16),
              ),
              Icon(Icons.calendar_today, color: AppTheme.accentColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlots() {
    if (_selectedProviderKey == null) {
      return _hintBox('Choose a service provider above to see their free time slots.');
    }
    if (_isLoadingSlots) {
      return Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: CircularProgressIndicator(color: AppTheme.accentColor),
      ));
    }
    if (_slotsError != null) {
      return InlineStatus(message: _slotsError!, onRetry: _fetchSlots);
    }
    if (_isClosed) return _hintBox(_closedReason ?? 'No slots available for this date.');
    if (_slots.isEmpty) return _hintBox('No slots available for this date.');

    final hasAnyAvailable = _slots.any((s) => s['available'] == true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasAnyAvailable)
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'This staff member is fully booked on this date. Try another date or provider.',
              style: GoogleFonts.outfit(fontSize: 13, color: context.colors.warning),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _slots.map<Widget>((slot) {
            final isAvailable = slot['available'] == true;
            final isSelected = _selectedTime == slot['time'];

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: isAvailable
                  ? () {
                      AppHaptics.selectionClick();
                      setState(() {
                        _selectedTime = slot['time'];
                        _slotHint = null;
                      });
                    }
                  : () {
                      AppHaptics.error();
                      setState(() => _slotHint = '${slot['time']} — ${_reasonLabel(slot['reason'])}');
                    },
              child: Container(
                width: (MediaQuery.of(context).size.width - 64) / 3,
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accentColor
                      : isAvailable
                          ? context.colors.surface
                          : context.colors.border,
                  border: Border.all(color: isSelected ? AppTheme.accentColor : context.colors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    slot['time'],
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : isAvailable
                              ? context.colors.textPrimary
                              : context.colors.textTertiary,
                      decoration: isAvailable ? TextDecoration.none : TextDecoration.lineThrough,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 12),
        Text(
          'Greyed out slots are outside working hours or already booked. Tap one to see why.',
          style: GoogleFonts.outfit(fontSize: 12, color: context.colors.textTertiary),
        ),
      ],
    );
  }

  Widget _hintBox(String text) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.accentSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary)),
      );

  Widget _buildBottomBar() {
    final canSave = _selectedTime != null && !_isSaving;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_saveError != null) ...[
              InlineStatus(
                message: _saveError!,
                onDismiss: () => setState(() => _saveError = null),
              ),
              SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSave ? () {
                  AppHaptics.lightImpact();
                  _confirm();
                } : null,
                style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                  padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 16)),
                ),
                child: _isSaving
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Confirm New Slot', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
