import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../theme/app_theme.dart';
import '../services/appointment_service.dart';
import '../utils/app_haptics.dart';
import '../widgets/initials_avatar.dart';
import '../theme/app_colors.dart';
import '../utils/error_text.dart';
import '../widgets/feedback_states.dart';

/// Granularity of the booking grid the API returns. Mirrors
/// `AvailabilityService::SLOT_MINUTES` on the server.
const int _kSlotMinutes = 30;

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

  /// The chosen staff member's id, or null until one is picked. There is no
  /// "any staff" choice: the booked provider is the one who scans the
  /// customer's QR at the salon, so every booking names a person.
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
  String? _pendingPaymentAppointmentId;
  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _loadProviders();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (_pendingPaymentAppointmentId == null) return;
    
    setState(() => _isBooking = true);
    try {
      await _appointmentService.confirmPayment(
        _pendingPaymentAppointmentId!,
        response.paymentId ?? '',
        response.signature ?? ''
      );
      _showSuccessDialog();
    } catch (e) {
      _setBookingError(describeError(e,
          fallback: 'We could not confirm your booking yet. If the payment went through, '
              'it will appear in My Bookings shortly.'));
    } finally {
      setState(() => _isBooking = false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    final reason = response.message?.trim() ?? '';
    _setBookingError(reason.isNotEmpty ? reason : 'Payment did not go through. Please try again.');
    if (_pendingPaymentAppointmentId != null) {
      _appointmentService.abandonPayment(_pendingPaymentAppointmentId!);
      _pendingPaymentAppointmentId = null;
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    _toast('Continuing with ${response.walletName}.');
  }

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
      _slotsError = null;
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
        providerId: _selectedProviderKey,
      );

      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final isToday = dateStr == todayStr;
      final nowTime = TimeOfDay.now();

      final processedSlots = (data['slots'] as List? ?? []).where((slot) {
        if (isToday) {
           final timeStr = slot['time'] as String;
           final parts = timeStr.split(':');
           if (parts.length >= 2) {
             final hour = int.tryParse(parts[0]) ?? 0;
             final minute = int.tryParse(parts[1]) ?? 0;
             if (hour < nowTime.hour || (hour == nowTime.hour && minute <= nowTime.minute)) {
                return false;
             }
           }
        }
        return true;
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
      if (mounted) {
        setState(() => _slotsError = describeError(e, fallback: 'Could not load the time slots.'));
      }
    }
  }

  void _selectProvider(String key) {
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

  /// Midnight today, so date comparisons are not skewed by the clock.
  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// "yyyy-MM-dd" for a date — the key both the chips and the API use.
  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  void _selectDate(DateTime date) {
    AppHaptics.selectionClick();
    setState(() => _selectedDate = date);
    _fetchSlots();
  }

  Future<void> _pickDate() async {
    final first = _today();
    final last = first.add(const Duration(days: 30));
    // showDatePicker asserts initialDate is inside the range.
    var initial = _selectedDate;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
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
      _selectDate(date);
    }
  }

  Future<void> _bookAppointment() async {
    if (_selectedTime == null || _selectedProviderKey == null) return;

    setState(() {
      _isBooking = true;
      _bookingError = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final response = await _appointmentService.bookAppointment(
        widget.salonId,
        dateStr,
        _selectedTime!,
        providerId: _selectedProviderKey,
      );

      setState(() => _isBooking = false);

      final isPaymentRequired = response['payment_required'] == true;
      
      if (!isPaymentRequired) {
        _showSuccessDialog();
        return;
      }

      final payment = response['payment'];
      final appointmentId = payment['appointment_id'];
      _pendingPaymentAppointmentId = appointmentId;

      if (payment['is_demo'] == true) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text('Demo Payment'),
            content: Text('Simulate a successful payment for ₹${payment['amount']}?'),
            actions: [
              TextButton(
                onPressed: () {
                  AppHaptics.lightImpact();
                  Navigator.pop(dialogContext);
                  _appointmentService.abandonPayment(appointmentId);
                  _pendingPaymentAppointmentId = null;
                },
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  AppHaptics.lightImpact();
                  Navigator.pop(dialogContext);
                  setState(() => _isBooking = true);
                  try {
                    await _appointmentService.demoPay(appointmentId);
                    _showSuccessDialog();
                  } catch (e) {
                    _setBookingError(describeError(e, fallback: 'Payment did not go through. Please try again.'));
                  } finally {
                    setState(() => _isBooking = false);
                  }
                },
                child: Text('Pay (Demo)'),
              ),
            ],
          ),
        );
      } else {
        var options = {
          'key': payment['key'],
          'amount': payment['amount_in_paise'],
          'name': payment['name'],
          'description': 'Appointment Booking',
          'order_id': payment['order_id'],
        };
        _razorpay.open(options);
      }
    } catch (e) {
      AppHaptics.error();
      setState(() => _isBooking = false);
      _setBookingError(describeError(e, fallback: 'We could not book that slot. Please try again.'));
      // The slot may have been taken while the customer was deciding.
      _fetchSlots();
    }
  }

  void _showSuccessDialog() {
    if (!mounted) return;
    AppHaptics.success();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: context.colors.success, size: 80),
            SizedBox(height: 16),
            Text('Booking Confirmed!', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Your appointment has been successfully booked.', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: context.colors.textSecondary)),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                // `true` tells the cart screen the cart was consumed.
                Navigator.pop(context, true);
              },
              style: Theme.of(context).elevatedButtonTheme.style,
              child: Center(child: Text('View My Bookings')),
            )
          ],
        ),
      ),
    );
  }

  /// Inline feedback, each shown next to what it is about rather than in a
  /// SnackBar over the booking bar. A failed payment or booking sits above
  /// the Pay button; a hint about a greyed-out provider, date or slot sits
  /// under that section and is replaced by the next tap.
  String? _bookingError;
  String? _slotsError;
  String? _providerHint;
  String? _dateHint;
  String? _slotHint;

  void _setBookingError(String text) {
    if (!mounted) return;
    AppHaptics.error();
    setState(() => _bookingError = text);
  }

  /// Confirmations only: a message that may vanish without loss.
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

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  /// "HH:mm" (or "HH:mm:ss") as minutes past midnight, or null if unparseable.
  int? _minutesOfDay(dynamic timeStr) {
    final parts = '$timeStr'.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// True for the blocks after the chosen start that the appointment will run
  /// into. A 180-minute booking starting at 10:00 covers 10:30 through 12:30.
  bool _isWithinSelectedBooking(dynamic slotTime) {
    if (_selectedTime == null || _totalDuration <= 0) return false;

    final start = _minutesOfDay(_selectedTime);
    final slot = _minutesOfDay(slotTime);
    if (start == null || slot == null) return false;

    return slot > start && slot < start + _totalDuration;
  }

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
              style: GoogleFonts.outfit(fontSize: 13, color: context.colors.textSecondary),
            ),
            SizedBox(height: 12),
            _buildProviderList(),
            _hint(_providerHint, () => setState(() => _providerHint = null)),

            SizedBox(height: 32),

            _sectionTitle('2. Select Date'),
            SizedBox(height: 12),
            _buildDatePicker(),
            _hint(_dateHint, () => setState(() => _dateHint = null)),

            SizedBox(height: 32),

            _sectionTitle('3. Select Time'),
            if (_totalDuration > 0) ...[
              SizedBox(height: 4),
              Text(
                'Your services take about $_totalDuration minutes.',
                style: GoogleFonts.outfit(fontSize: 13, color: context.colors.textSecondary),
              ),
            ],
            SizedBox(height: 16),
            _buildSlots(),
            _hint(_slotHint, () => setState(() => _slotHint = null)),

            SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
      );

  Widget _buildProviderList() {
    if (_isLoadingProviders) {
      return Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: CircularProgressIndicator(color: AppTheme.accentColor),
      ));
    }

    if (_providersError.isNotEmpty) {
      return Text(_providersError, style: GoogleFonts.outfit(color: context.colors.danger));
    }

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
            ? () => _selectProvider(key)
            : () {
                AppHaptics.error();
                setState(() => _providerHint = '$name cannot perform every service in your cart.');
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
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textPrimary)),
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

  /// Step 2 offers one-tap "Today" and "Tomorrow", plus a calendar button that
  /// still opens the full 30-day picker.
  Widget _buildDatePicker() {
    final enabled = _selectedProviderKey != null;
    final today = _today();
    final tomorrow = today.add(const Duration(days: 1));
    final selected = _dateKey(_selectedDate);
    final isCustom = selected != _dateKey(today) && selected != _dateKey(tomorrow);

    void guard(void Function() action) {
      if (!enabled) {
        AppHaptics.error();
        setState(() => _dateHint = 'Choose a service provider first.');
        return;
      }
      action();
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _dateTile(
                  label: 'Today',
                  date: today,
                  isSelected: selected == _dateKey(today),
                  onTap: () => guard(() => _selectDate(today)),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _dateTile(
                  label: 'Tomorrow',
                  date: tomorrow,
                  isSelected: selected == _dateKey(tomorrow),
                  onTap: () => guard(() => _selectDate(tomorrow)),
                ),
              ),
              SizedBox(width: 12),
              _calendarButton(
                isActive: isCustom,
                onTap: () => guard(_pickDate),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            isCustom
                ? 'Selected: ${DateFormat('EEEE, MMM d, yyyy').format(_selectedDate)}'
                : 'Pick Today or Tomorrow, or tap the calendar to choose any other date.',
            style: GoogleFonts.outfit(fontSize: 12, color: context.colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime date,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppTheme.accentColor : context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    DateFormat('EEE, MMM d').format(date),
                    style: GoogleFonts.outfit(fontSize: 12, color: context.colors.textSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: AppTheme.accentColor, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _calendarButton({required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 52,
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? context.colors.accentSoft : context.colors.surface,
          border: Border.all(
            color: isActive ? AppTheme.accentColor : context.colors.border,
            width: isActive ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Icon(Icons.calendar_today, size: 20, color: AppTheme.accentColor),
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
              style: GoogleFonts.outfit(fontSize: 13, color: context.colors.warning),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _slots.map<Widget>((slot) {
            final isAvailable = slot['available'] == true;
            final isSelected = _selectedTime == slot['time'];
            // Blocks the chosen start time will run into. They are filled the
            // same purple as the start block so the whole appointment reads as
            // one continuous booking.
            final isOccupied = !isSelected && _isWithinSelectedBooking(slot['time']);

            Color background;
            Color textColor;
            Color borderColor = context.colors.border;

            if (isSelected || isOccupied) {
              background = AppTheme.accentColor;
              textColor = Colors.white;
              borderColor = AppTheme.accentColor;
            } else if (isAvailable) {
              background = context.colors.surface;
              textColor = context.colors.textPrimary;
            } else {
              background = context.colors.border;
              textColor = context.colors.textTertiary;
            }

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              // Greying a block is only a preview of the span — tapping a free
              // one still moves the start time there.
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: (MediaQuery.of(context).size.width - 64) / 3,
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: background,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppTheme.accentColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: textColor,
                      decoration: isAvailable || isOccupied
                          ? TextDecoration.none
                          : TextDecoration.lineThrough,
                    ),
                    child: Text(slot['time']),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 12),
        Text(
          _selectedTime != null && _totalDuration > _kSlotMinutes
              ? 'All the purple blocks together are your $_totalDuration minute appointment, starting at $_selectedTime.'
              : 'Greyed out slots are outside working hours or already booked. Tap one to see why.',
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
    final canBook = _selectedProviderKey != null && _selectedTime != null && !_isBooking;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_bookingError != null) ...[
              InlineStatus(
                message: _bookingError!,
                onDismiss: () => setState(() => _bookingError = null),
              ),
              SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary)),
                Text('₹${_totalAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
              ],
            ),
            SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Advance payable now', style: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary)),
                Text('₹${_advanceAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
              ],
            ),
            SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canBook ? () {
                  AppHaptics.lightImpact();
                  _bookAppointment();
                } : null,
                style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
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
