import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../services/appointment_service.dart'; // Ensure correct path
import '../../../../utils/time_fmt.dart';
import '../../appointment_details_screen.dart'; // Fixed relative path
import '../../walk_in_screen.dart';
import '../close_day_sheet.dart';

const String _kAllDates = 'All Dates';
const String _kAllProviders = 'All Providers';
const String _kAllServices = 'All Services';
const String _kAllStatus = 'All Status';
const String _kAllSources = 'All Sources';
const String _kCustomDate = 'Custom Date';

/// Labels shown in the status dropdown mapped to the values the API stores.
const Map<String, String> _kStatusValues = {
  'Scheduled': 'scheduled',
  'In Progress': 'in_progress',
  'Completed': 'completed',
  'Cancelled': 'cancelled',
  'No Show': 'no_show',
  'Awaiting Reschedule': 'awaiting_reschedule',
};

const List<String> _kStatusLabels = [
  'Scheduled',
  'In Progress',
  'Completed',
  'Cancelled',
  'No Show',
  'Awaiting Reschedule',
];

/// Labels shown in the source dropdown mapped to `booking_source` values.
const Map<String, String> _kSourceValues = {
  'App': 'online',
  'Walk-in': 'walk_in',
  'Phone': 'phone',
};

const List<String> _kSourceLabels = ['App', 'Walk-in', 'Phone'];

class AppointmentsTab extends StatefulWidget {
  final String salonId;
  const AppointmentsTab({Key? key, required this.salonId}) : super(key: key);

  @override
  State<AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<AppointmentsTab> {
  final PartnerAppointmentService _service = PartnerAppointmentService();
  List<dynamic> _appointments = [];
  bool _isLoading = true;

  // Today is what an admin is running the salon against; the full history is
  // one dropdown away.
  String _selectedDate = 'Today';
  String _selectedProvider = _kAllProviders;
  String _selectedService = _kAllServices;
  String _selectedStatus = _kAllStatus;
  String _selectedSource = _kAllSources;

  /// Set when the date filter is "Custom Date".
  DateTime? _customDate;

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _isLoading = true);
    try {
      // Fetch real data from database
      final data = await _service.getAppointments(widget.salonId);
      setState(() {
        _appointments = data;
        _isLoading = false;
      });
    } catch (e, stack) {
      print('AppointmentsTab error: $e');
      print(stack);
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load appointments')));
    }
  }

  /// Emergency closure. Defaults to whatever day the admin is looking at, so
  /// the button means what it says on screen.
  /// An admin at the desk adds walk-ins too, and picks who serves them.
  Future<void> _openWalkIn() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => WalkInScreen(salonId: widget.salonId)),
    );

    if (added == true) _loadAppointments();
  }

  Future<void> _openCloseDay() async {
    final closed = await CloseDaySheet.show(
      context,
      salonId: widget.salonId,
      initialDate: _filterDate ?? DateTime.now(),
    );

    if (closed) _loadAppointments();
  }

  // ------------------------------------------------------------- filter data

  /// Assigned provider's name, or null when the booking has no provider yet.
  String? _providerName(Map<String, dynamic> apt) {
    final provider = apt['appointed_provider'] ?? apt['serving_provider'];
    final name = provider?['user']?['name'] ?? provider?['name'];
    return (name is String && name.isNotEmpty) ? name : null;
  }

  /// Names of every service on the booking, including mid-appointment additions.
  List<String> _serviceNames(Map<String, dynamic> apt) {
    final lines = [
      ...(apt['services'] as List? ?? []),
      ...(apt['service_additions'] as List? ?? []),
    ];

    return lines
        .map((line) => line['service']?['template']?['name'] ?? line['service']?['name'])
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
  }

  /// The date filter resolved to a concrete day, or null for "All Dates".
  DateTime? get _filterDate {
    final today = DateUtils.dateOnly(DateTime.now());
    switch (_selectedDate) {
      case 'Today':
        return today;
      case 'Yesterday':
        return today.subtract(const Duration(days: 1));
      case 'Tomorrow':
        return today.add(const Duration(days: 1));
      case _kCustomDate:
        return _customDate;
      default:
        return null;
    }
  }

  /// Options built from the appointments actually on screen, so the dropdowns
  /// can never offer a value that filters everything away.
  List<String> get _providerOptions {
    final names = _appointments
        .map((apt) => _providerName(apt as Map<String, dynamic>))
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    return [_kAllProviders, ...names];
  }

  List<String> get _serviceOptions {
    final names = <String>{};
    for (final apt in _appointments) {
      names.addAll(_serviceNames(apt as Map<String, dynamic>));
    }
    final sorted = names.toList()..sort();
    return [_kAllServices, ...sorted];
  }

  /// The 5 filters applied together.
  List<dynamic> get _filteredAppointments {
    final date = _filterDate;

    return _appointments.where((raw) {
      final apt = raw as Map<String, dynamic>;

      if (date != null) {
        final aptDate = DateTime.tryParse('${apt['appointment_date']}');
        if (aptDate == null || !DateUtils.isSameDay(aptDate, date)) return false;
      }

      if (_selectedProvider != _kAllProviders && _providerName(apt) != _selectedProvider) {
        return false;
      }

      if (_selectedService != _kAllServices &&
          !_serviceNames(apt).contains(_selectedService)) {
        return false;
      }

      if (_selectedStatus != _kAllStatus &&
          '${apt['status']}'.toLowerCase() != _kStatusValues[_selectedStatus]) {
        return false;
      }

      if (_selectedSource != _kAllSources &&
          '${apt['booking_source']}'.toLowerCase() != _kSourceValues[_selectedSource]) {
        return false;
      }

      return true;
    }).toList();
  }

  bool get _hasActiveFilter =>
      _selectedDate != 'Today' ||
      _selectedProvider != _kAllProviders ||
      _selectedService != _kAllServices ||
      _selectedStatus != _kAllStatus ||
      _selectedSource != _kAllSources;

  void _clearFilters() {
    setState(() {
      // Back to the default view, not to every appointment ever taken.
      _selectedDate = 'Today';
      _selectedProvider = _kAllProviders;
      _selectedService = _kAllServices;
      _selectedStatus = _kAllStatus;
      _selectedSource = _kAllSources;
      _customDate = null;
    });
  }

  Future<void> _onDateFilterChanged(String? value) async {
    if (value == null) return;

    if (value != _kCustomDate) {
      setState(() {
        _selectedDate = value;
        _customDate = null;
      });
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked == null) return;
    setState(() {
      _selectedDate = _kCustomDate;
      _customDate = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _isLoading ? const <dynamic>[] : _filteredAppointments;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE), // Light background
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilters(),
            Expanded(
              child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9C54F2)))
                : visible.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: visible.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final apt = visible[index];
                        return _buildDynamicAppointmentCard(apt);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final filtered = _appointments.isNotEmpty && _hasActiveFilter;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filtered
                  ? 'No appointments match these filters'
                  : 'No appointments found',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.grey),
            ),
            if (filtered) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _clearFilters,
                child: Text(
                  'Clear filters',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF9C54F2),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Appointments',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1F2937),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _openWalkIn,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_add_alt_1, size: 15, color: Color(0xFF9333EA)),
                      const SizedBox(width: 6),
                      Text(
                        'Walk-in',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF9333EA),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _openCloseDay,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_busy, size: 15, color: Color(0xFFDC2626)),
                      const SizedBox(width: 6),
                      Text(
                        'Close day',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  const [_kAllDates, 'Today', 'Yesterday', 'Tomorrow', _kCustomDate],
                  _selectedDate,
                  _onDateFilterChanged,
                  // Show the day the admin picked rather than the generic label.
                  labelFor: (item) => item == _kCustomDate && _customDate != null
                      ? DateFormat('d MMM').format(_customDate!)
                      : item,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  _providerOptions,
                  _selectedProvider,
                  (v) => setState(() => _selectedProvider = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  _serviceOptions,
                  _selectedService,
                  (v) => setState(() => _selectedService = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown(
                  const [_kAllStatus, ..._kStatusLabels],
                  _selectedStatus,
                  (v) => setState(() => _selectedStatus = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  const [_kAllSources, ..._kSourceLabels],
                  _selectedSource,
                  (v) => setState(() => _selectedSource = v!),
                ),
              ),
              if (_hasActiveFilter) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _clearFilters,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    'Clear',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF9C54F2),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(
    List<String> items,
    String value,
    ValueChanged<String?> onChanged, {
    bool isFullWidth = false,
    String Function(String)? labelFor,
  }) {
    if (!items.contains(value)) value = items.first;

    return Container(
      width: isFullWidth ? double.infinity : null,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black87),
          style: GoogleFonts.outfit(color: const Color(0xFF1F2937), fontSize: 12, fontWeight: FontWeight.w500),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(labelFor?.call(item) ?? item, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDynamicAppointmentCard(Map<String, dynamic> apt) {
    bool isWalkIn = apt['booking_source'] == 'walk_in';
    String customerName = isWalkIn 
        ? (apt['walk_in_customer_name'] ?? 'Walk-In Customer') 
        : (apt['customer'] != null ? apt['customer']['name'] : 'Unknown Customer');
    
    String customerPhone = isWalkIn 
        ? (apt['walk_in_customer_phone'] ?? '') 
        : (apt['customer'] != null ? apt['customer']['phone'] : '');

    String initials = customerName.isNotEmpty ? customerName[0].toUpperCase() : '?';
    String status = (apt['status'] ?? '').toString().toUpperCase();
    
    // Determine colors based on status
    Color statusColor = const Color(0xFFE0F2FE);
    Color statusTextColor = const Color(0xFF0369A1);
    if (status == 'COMPLETED') {
      statusColor = const Color(0xFFDCFCE7);
      statusTextColor = const Color(0xFF15803D);
    } else if (status == 'IN_PROGRESS') {
      statusColor = const Color(0xFFFEF3C7);
      statusTextColor = const Color(0xFFD97706);
    } else if (status == 'CANCELLED' || status == 'NO_SHOW') {
      statusColor = const Color(0xFFFEE2E2);
      statusTextColor = const Color(0xFFDC2626);
    } else if (status == 'AWAITING_RESCHEDULE') {
      // Released by a day closure — waiting on the customer to pick a new slot.
      statusColor = const Color(0xFFFEF3C7);
      statusTextColor = const Color(0xFFB45309);
    }

    // Human-readable badge label, e.g. "In Progress" instead of "IN_PROGRESS".
    final String statusLabel = switch ((apt['status'] ?? '').toString()) {
      'completed' => 'Completed',
      'in_progress' => 'In Progress',
      'cancelled' => 'Cancelled',
      'no_show' => 'No Show',
      'awaiting_reschedule' => 'Awaiting Reschedule',
      _ => 'Scheduled',
    };

    // Determine icon based on source
    IconData sourceIcon = Icons.wifi;
    String sourceName = 'App';
    if (isWalkIn) {
      sourceIcon = Icons.storefront_outlined;
      sourceName = 'Walk-in';
    } else if (apt['booking_source'] == 'phone') {
      sourceIcon = Icons.phone_outlined;
      sourceName = 'Phone';
    }

    String provider = _providerName(apt) ?? 'Any Staff';

    // Parse services
    String serviceNames = _serviceNames(apt).join(', ');
    if (serviceNames.isEmpty) serviceNames = 'General Service';

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => AppointmentDetailsScreen(
            appointment: apt,
            salonId: widget.salonId,
          )
        )).then((_) => _loadAppointments()); // Reload on return
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFF3E8FF),
                  radius: 20,
                  child: Text(
                    initials,
                    style: GoogleFonts.outfit(color: const Color(0xFF9333EA), fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customerName, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1F2937))),
                      if (customerPhone.isNotEmpty)
                        Text(customerPhone, style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(16)),
                  child: Text(statusLabel, style: GoogleFonts.outfit(color: statusTextColor, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Provider: ', style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 13)),
                Text(provider, style: GoogleFonts.outfit(color: const Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Text('Time: ', style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 13)),
                Text(TimeFmt.slot(apt['start_time'], apt['end_time']), style: GoogleFonts.outfit(color: const Color(0xFF1F2937), fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Service: ', style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 13)),
                Expanded(
                  child: Text(
                    serviceNames, 
                    style: GoogleFonts.outfit(color: const Color(0xFF111827), fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFFF3F4F6), height: 1, thickness: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(sourceIcon, size: 16, color: const Color(0xFF9CA3AF)),
                const SizedBox(width: 4),
                Text(sourceName, style: GoogleFonts.outfit(color: const Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('₹${apt['total_amount']}', style: GoogleFonts.outfit(color: const Color(0xFF9333EA), fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
