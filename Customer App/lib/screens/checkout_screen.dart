import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';

/// Sentinel provider key for the "Any Available" option.
const String _kAnyProvider = '__any__';

class CheckoutScreen extends StatefulWidget {
  final String salonId;
  const CheckoutScreen({Key? key, required this.salonId}) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final AppointmentService _appointmentService = AppointmentService();

  List<dynamic> _providers = [];
  bool _isLoadingProviders = true;
  String _providersError = '';

  /// null = nothing picked yet, [_kAnyProvider] = Any Available.
  String? _selectedProviderKey;

  DateTime _selectedDate = DateTime.now();
  String? _selectedTime;
  List<dynamic> _slots = [];
  bool _isLoadingSlots = false;
  bool _isClosed = false;
  String? _closedReason;

  double _totalAmount = 0;
  double _advanceAmount = 0;
  int _totalDuration = 0;

  bool _isBooking = false;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  /// The id sent to the API: null for "Any Available".
  String? get _providerIdForApi =>
      _selectedProviderKey == _kAnyProvider ? null : _selectedProviderKey;

  Future<void> _loadProviders() async {
    setState(() {
      _isLoadingProviders = true;
      _providersError = '';
    });

    try {
      final data = await _appointmentService.getSalonProviders(widget.salonId);
      setState(() {
        _providers = data['providers'] ?? [];
        _totalAmount = _toDouble(data['total_amount']);
        _advanceAmount = _toDouble(data['advance_amount']);
        _totalDuration = (data['total_duration_minutes'] ?? 0) as int;
        _isLoadingProviders = false;
      });
    } catch (e) {
      setState(() {
        _providersError = 'Could not load service providers.';
        _isLoadingProviders = false;
      });
    }
  }

  Future<void> _fetchSlots() async {
    if (_selectedProviderKey == null) return;

    setState(() {
      _isLoadingSlots = true;
      _selectedTime = null;
      _slots = [];
      _isClosed = false;
      _closedReason = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final data = await _appointmentService.getAvailableSlots(
        widget.salonId,
        dateStr,
        providerId: _providerIdForApi,
      );

      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final isToday = dateStr == todayStr;
      final nowTime = TimeOfDay.now();

      final processedSlots = (data['slots'] as List? ?? []).map((slot) {
        if (slot['available'] == true && isToday) {
           final timeStr = slot['time'] as String;
           final parts = timeStr.split(':');
           if (parts.length >= 2) {
             final hour = int.tryParse(parts[0]) ?? 0;
             final minute = int.tryParse(parts[1]) ?? 0;
             if (hour < nowTime.hour || (hour == nowTime.hour && minute <= nowTime.minute)) {
                return {
                  ...slot as Map<String, dynamic>,
                  'available': false,
                  'reason': 'past',
                };
             }
           }
        }
        return slot;
      }).toList();

      setState(() {
        _slots = processedSlots;
        _isClosed = data['closed'] == true;
        _closedReason = data['closed_reason'];
        _totalAmount = _toDouble(data['total_amount']);
        _advanceAmount = _toDouble(data['advance_amount']);
        _totalDuration = (data['total_duration_minutes'] ?? _totalDuration) as int;
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

  void _selectProvider(String key) {
    setState(() {
      _selectedProviderKey = key;
      _selectedTime = null;
    });
    _fetchSlots();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: AppTheme.accentColor),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() => _selectedDate = date);
      _fetchSlots();
    }
  }

  Future<void> _bookAppointment() async {
    if (_selectedTime == null || _selectedProviderKey == null) return;

    setState(() => _isBooking = true);

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      await _appointmentService.bookAppointment(
        widget.salonId,
        dateStr,
        _selectedTime!,
        providerId: _providerIdForApi,
      );

      setState(() => _isBooking = false);

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: AppTheme.lightSuccess, size: 80),
              SizedBox(height: 16),
              Text('Booking Confirmed!', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Your appointment has been successfully booked.', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: AppTheme.lightTextBody)),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext); // Close dialog
                  // `true` tells the cart screen the cart was consumed.
                  Navigator.pop(context, true);
                },
                style: AppTheme.lightTheme.elevatedButtonTheme.style,
                child: Center(child: Text('View My Bookings')),
              )
            ],
          ),
        ),
      );
    } catch (e) {
      setState(() => _isBooking = false);
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
      // The slot may have been taken while the customer was deciding.
      _fetchSlots();
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  /// Human wording for why a block cannot be booked.
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
      appBar: AppBar(title: Text('Book Appointment')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('1. Choose Service Provider'),
            SizedBox(height: 4),
            Text(
              'Staff who cannot perform every service in your cart are shown greyed out.',
              style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody),
            ),
            SizedBox(height: 12),
            _buildProviderList(),

            SizedBox(height: 32),

            _sectionTitle('2. Select Date'),
            SizedBox(height: 12),
            _buildDateField(),

            SizedBox(height: 32),

            _sectionTitle('3. Select Time'),
            if (_totalDuration > 0) ...[
              SizedBox(height: 4),
              Text(
                'Your services take about $_totalDuration minutes.',
                style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextBody),
              ),
            ],
            SizedBox(height: 16),
            _buildSlots(),

            SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading),
      );

  Widget _buildProviderList() {
    if (_isLoadingProviders) {
      return Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: CircularProgressIndicator(color: AppTheme.accentColor),
      ));
    }

    if (_providersError.isNotEmpty) {
      return Text(_providersError, style: GoogleFonts.outfit(color: AppTheme.lightDanger));
    }

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
            ? () => _selectProvider(key)
            : () => _showMessage('$name cannot perform every service in your cart.'),
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
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.lightTextHeading)),
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
              Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate),
                  style: GoogleFonts.outfit(fontSize: 16)),
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

    if (_isClosed) {
      return _hintBox(_closedReason ?? 'No slots available for this date.');
    }

    if (_slots.isEmpty) {
      return _hintBox('No slots available for this date.');
    }

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
                  border: Border.all(
                    color: isSelected ? AppTheme.accentColor : AppTheme.lightBorder,
                  ),
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
    final canBook = _selectedProviderKey != null && _selectedTime != null && !_isBooking;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
                Text('₹${_totalAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.lightTextHeading)),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Advance payable now', style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
                Text('₹${_advanceAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
              ],
            ),
            SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canBook ? _bookAppointment : null,
                style: AppTheme.lightTheme.elevatedButtonTheme.style?.copyWith(
                  padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 16)),
                ),
                child: _isBooking
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Confirm & Pay Advance', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
