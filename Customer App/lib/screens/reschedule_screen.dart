import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';

/// Sentinel provider key for the "Any Available" option.
const String _kAnyProvider = '__any__';

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

  String? get _providerIdForApi =>
      _selectedProviderKey == _kAnyProvider ? null : _selectedProviderKey;

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
        providerId: _providerIdForApi,
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
      });
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
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
      setState(() => _selectedDate = date);
      _fetchSlots();
    }
  }

  Future<void> _confirm() async {
    if (_selectedTime == null || _selectedDate == null) return;

    setState(() => _isSaving = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      final result = await _appointmentService.rescheduleAppointment(
        widget.appointmentId,
        dateStr,
        _selectedTime!,
        providerId: _providerIdForApi,
      );

      if (!mounted) return;
      setState(() => _isSaving = false);
      Navigator.pop(context, true);
      _showMessage(result['message'] ?? 'Appointment rescheduled.');
    } catch (e) {
      setState(() => _isSaving = false);
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
      _fetchSlots(); // the slot may have been taken meanwhile
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
                        style: GoogleFonts.outfit(color: AppTheme.lightDanger, fontSize: 16)),
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
                color: AppTheme.lightInfoBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppTheme.lightInfo),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'The salon is closed on your original date. This reschedule is free — your advance carries over.',
                      style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightInfo),
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
                style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody),
              ),
            ),

          _sectionTitle('1. Service Provider'),
          SizedBox(height: 12),
          _buildProviderList(),

          SizedBox(height: 32),
          _sectionTitle('2. New Date'),
          SizedBox(height: 12),
          _buildDateField(),

          SizedBox(height: 32),
          _sectionTitle('3. New Time'),
          if (_totalDuration > 0) ...[
            SizedBox(height: 4),
            Text('Your services take about $_totalDuration minutes.',
                style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody)),
          ],
          SizedBox(height: 16),
          _buildSlots(),
          SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
      );

  Widget _buildProviderList() {
    if (_providers.isEmpty) {
      return Text('This salon has no staff available right now.',
          style: GoogleFonts.outfit(color: AppTheme.lightTextBody));
    }

    final hasEligible = _providers.any((p) => p['is_eligible'] == true);

    return Column(
      children: [
        if (hasEligible)
          _providerTile(
            key: _kAnyProvider,
            name: 'Any Available',
            subtitle: 'We will assign a free staff member for your slot',
            isEligible: true,
            icon: Icons.groups_outlined,
          ),
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
            icon: Icons.person_outline,
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
    required IconData icon,
  }) {
    final isSelected = _selectedProviderKey == key;

    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isEligible
            ? () {
                setState(() {
                  _selectedProviderKey = key;
                  _selectedTime = null;
                });
                _fetchSlots();
              }
            : () => _showMessage('$name cannot perform every service in this booking.'),
        child: Opacity(
          opacity: isEligible ? 1.0 : 0.5,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.lightAccentSoft : AppTheme.lightSurface,
              border: Border.all(
                color: isSelected ? AppTheme.accentColor : AppTheme.lightBorder,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isEligible ? AppTheme.lightAccentSoft : AppTheme.lightBorder,
                  child: Icon(icon, color: isEligible ? AppTheme.accentColor : AppTheme.lightTextLight),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: GoogleFonts.outfit(
                              fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.lightTextHeading)),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        SizedBox(height: 2),
                        Text(subtitle,
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: isEligible ? AppTheme.lightTextBody : AppTheme.lightDanger)),
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
        onTap: enabled ? _pickDate : () => _showMessage('Choose a service provider first.'),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: AppTheme.lightSurface,
            border: Border.all(color: AppTheme.lightBorder),
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
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightWarning),
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
                  ? () => setState(() => _selectedTime = slot['time'])
                  : () => _showMessage('${slot['time']} — ${_reasonLabel(slot['reason'])}'),
              child: Container(
                width: (MediaQuery.of(context).size.width - 64) / 3,
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accentColor
                      : isAvailable
                          ? AppTheme.lightSurface
                          : AppTheme.lightBorder,
                  border: Border.all(color: isSelected ? AppTheme.accentColor : AppTheme.lightBorder),
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
                              ? AppTheme.lightTextHeading
                              : AppTheme.lightTextLight,
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
          style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextLight),
        ),
      ],
    );
  }

  Widget _hintBox(String text) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.lightAccentSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
      );

  Widget _buildBottomBar() {
    final canSave = _selectedTime != null && !_isSaving;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canSave ? _confirm : null,
            style: AppTheme.lightTheme.elevatedButtonTheme.style?.copyWith(
              padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 16)),
            ),
            child: _isSaving
                ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Confirm New Slot', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}
