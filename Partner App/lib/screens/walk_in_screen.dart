import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/walk_in_api.dart';
import '../theme/app_theme.dart';
import 'collect_payment_sheet.dart';

/// Add a customer who walked in off the street.
///
/// The same form serves staff and admins: a staff member is always serving
/// their own walk-in, while an admin picks who is doing the work. The running
/// total and finish time are shown as services are picked, because the person
/// at the desk has to quote a price before the customer sits down.
class WalkInScreen extends StatefulWidget {
  final String salonId;

  /// Embedded as a dashboard tab rather than pushed as its own page.
  final bool embedded;

  const WalkInScreen({
    Key? key,
    required this.salonId,
    this.embedded = false,
  }) : super(key: key);

  @override
  State<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends State<WalkInScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _searchController = TextEditingController();

  WalkInOptions? _options;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;

  final Set<String> _selectedServiceIds = {};
  String? _providerId;
  String _gender = 'Female';

  /// null means "start now"; otherwise a time later today.
  TimeOfDay? _startLater;

  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _searchController.addListener(() {
      setState(() => _search = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final options = await WalkInApi.options(widget.salonId);
      if (!mounted) return;
      setState(() {
        _options = options;
        _providerId = options.defaultProviderId ??
            (options.providers.length == 1 ? options.providers.first.id : null);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // ------------------------------------------------------------- derived

  List<WalkInService> get _selectedServices =>
      (_options?.services ?? []).where((s) => _selectedServiceIds.contains(s.id)).toList();

  double get _total => _selectedServices.fold(0.0, (sum, s) => sum + s.price);

  int get _duration => _selectedServices.fold(0, (sum, s) => sum + s.durationMinutes);

  WalkInProvider? get _selectedProvider =>
      _options?.providers.where((p) => p.id == _providerId).firstOrNull;

  /// Services the chosen staff member is not assigned to. Shown as a caution,
  /// not a block — salons reassign work all the time.
  List<WalkInService> get _untrainedFor {
    final provider = _selectedProvider;
    if (provider == null) return const [];
    return _selectedServices.where((s) => !provider.serviceIds.contains(s.id)).toList();
  }

  DateTime get _startsAt {
    final now = DateTime.now();
    if (_startLater == null) return now;
    return DateTime(now.year, now.month, now.day, _startLater!.hour, _startLater!.minute);
  }

  DateTime get _endsAt => _startsAt.add(Duration(minutes: _duration));

  bool get _canSubmit =>
      !_isSubmitting &&
      _nameController.text.trim().isNotEmpty &&
      _selectedServiceIds.isNotEmpty &&
      _providerId != null;

  Map<String, List<WalkInService>> get _visibleByCategory {
    final grouped = <String, List<WalkInService>>{};

    for (final service in _options?.services ?? <WalkInService>[]) {
      final matches = _search.isEmpty ||
          service.name.toLowerCase().contains(_search) ||
          service.category.toLowerCase().contains(_search);
      if (!matches) continue;
      grouped.putIfAbsent(service.category, () => []).add(service);
    }

    return grouped;
  }

  // ------------------------------------------------------------- actions

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startLater ?? TimeOfDay.now(),
      helpText: 'Start later today',
    );

    if (picked == null) return;
    setState(() => _startLater = picked);
  }

  Future<void> _submit({bool allowOverlap = false}) async {
    setState(() => _isSubmitting = true);

    try {
      final result = await WalkInApi.create(
        widget.salonId,
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        gender: _gender,
        serviceIds: _selectedServiceIds.toList(),
        providerId: _providerId,
        startTime: _startLater == null
            ? null
            : DateFormat('yyyy-MM-dd HH:mm:ss').format(_startsAt),
        allowOverlap: allowOverlap,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      await _onCreated(result);
    } on WalkInConflict catch (conflict) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      await _offerOverride(conflict);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _offerOverride(WalkInConflict conflict) async {
    final squeeze = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Already busy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_selectedProvider?.name ?? 'That staff member'} already has:'),
            const SizedBox(height: 8),
            ...conflict.conflicts.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${c.startTime}–${c.endTime}  ${c.customerName}'),
                )),
            const SizedBox(height: 12),
            const Text('Add this walk-in anyway, or pick someone else?'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Pick someone else')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add anyway')),
        ],
      ),
    );

    if (squeeze == true) await _submit(allowOverlap: true);
  }

  Future<void> _onCreated(WalkInResult result) async {
    final startedNow = result.appointment.isInProgress;

    // Reset for the next customer — the desk usually has a queue.
    setState(() {
      _nameController.clear();
      _phoneController.clear();
      _selectedServiceIds.clear();
      _startLater = null;
      _searchController.clear();
    });

    if (!startedNow) {
      _showMessage(result.message);
      if (!widget.embedded && mounted) Navigator.pop(context, true);
      return;
    }

    // Walk-ins pay at the counter, so offer the bill straight away.
    final goToBill = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Walk-in started'),
        content: Text(
          '${result.appointment.customerName} is now in progress with '
          '${result.appointment.servingProviderName ?? 'your staff'}.\n\n'
          '₹${result.bill.balanceDue.toStringAsFixed(0)} to collect when they are done.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Add another')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Go to bill')),
        ],
      ),
    );

    if (goToBill == true && mounted) {
      await CollectPaymentSheet.show(
        context,
        salonId: widget.salonId,
        appointmentId: result.appointment.id,
      );
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showError(String text) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not added'),
        content: Text(text),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _loadError != null
            ? _buildLoadError()
            : _buildForm();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text('Add walk-in',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.black87)),
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.black87),
            ),
      body: widget.embedded ? SafeArea(child: body) : body,
      bottomNavigationBar: _isLoading || _loadError != null ? null : _buildFooter(),
    );
  }

  Widget _buildLoadError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadOptions, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        if (widget.embedded) ...[
          Text('Add walk-in customer',
              style: GoogleFonts.outfit(
                  fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF1F2937))),
          const SizedBox(height: 16),
        ],

        _sectionTitle('Customer'),
        const SizedBox(height: 10),
        _field(
          controller: _nameController,
          hint: 'Name',
          icon: Icons.person_outline,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _field(
          controller: _phoneController,
          hint: 'Phone (optional)',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final option in const ['Female', 'Male', 'Other'])
              Expanded(child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _chip(
                  label: option,
                  selected: _gender == option,
                  onTap: () => setState(() => _gender = option),
                ),
              )),
          ],
        ),

        const SizedBox(height: 26),
        _buildProviderSection(),

        const SizedBox(height: 26),
        _buildTimingSection(),

        const SizedBox(height: 26),
        _buildServicesSection(),
      ],
    );
  }

  Widget _buildProviderSection() {
    final options = _options!;

    if (!options.canChooseProvider) {
      // A staff member always serves their own walk-in.
      final me = _selectedProvider;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.person, size: 20, color: AppTheme.accentColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Serving: ${me?.name ?? 'You'}',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Who is serving?'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _providerId == null ? AppTheme.lightWarning : Colors.transparent,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _providerId,
              isExpanded: true,
              hint: Text('Choose a staff member', style: GoogleFonts.outfit()),
              onChanged: _isSubmitting ? null : (v) => setState(() => _providerId = v),
              items: options.providers
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          p.specialization != null && p.specialization!.isNotEmpty
                              ? '${p.name}  ·  ${p.specialization}'
                              : p.name,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        if (_untrainedFor.isNotEmpty) ...[
          const SizedBox(height: 10),
          _notice(
            '${_selectedProvider!.name} is not assigned to '
            '${_untrainedFor.map((s) => s.name).join(', ')}. '
            'You can still go ahead — the work is credited to them.',
            AppTheme.lightWarning,
          ),
        ],
      ],
    );
  }

  Widget _buildTimingSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('When'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _chip(
                  label: 'Start now',
                  selected: _startLater == null,
                  onTap: () => setState(() => _startLater = null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _chip(
                  label: _startLater == null
                      ? 'Later today'
                      : _startLater!.format(context),
                  selected: _startLater != null,
                  onTap: _pickStartTime,
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildServicesSection() {
    final grouped = _visibleByCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle('Services'),
            const Spacer(),
            if (_selectedServiceIds.isNotEmpty)
              Text('${_selectedServiceIds.length} selected',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.accentColor)),
          ],
        ),
        const SizedBox(height: 10),
        _field(
          controller: _searchController,
          hint: 'Search services',
          icon: Icons.search,
        ),
        const SizedBox(height: 12),
        if (_options!.services.isEmpty)
          _notice('This salon has no active services yet.', AppTheme.lightWarning)
        else if (grouped.isEmpty)
          _notice('No services match "$_search".', Colors.grey.shade700)
        else
          ...grouped.entries.map((entry) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Text(entry.key.toUpperCase(),
                        style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                            color: Colors.grey.shade500)),
                  ),
                  ...entry.value.map(_buildServiceTile),
                ],
              )),
      ],
    );
  }

  Widget _buildServiceTile(WalkInService service) {
    final selected = _selectedServiceIds.contains(service.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isSubmitting
            ? null
            : () => setState(() {
                  if (selected) {
                    _selectedServiceIds.remove(service.id);
                  } else {
                    _selectedServiceIds.add(service.id);
                  }
                }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.accentColor : Colors.transparent,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 22,
                color: selected ? AppTheme.accentColor : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.name,
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${service.durationMinutes} min',
                        style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Text('₹${service.price.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  /// Running total and finish time, so the desk can quote before committing.
  Widget _buildFooter() {
    final hasServices = _selectedServiceIds.isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasServices
                          ? '₹${_total.toStringAsFixed(0)}'
                          : 'Pick a service',
                      style: GoogleFonts.outfit(
                          fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1F2937)),
                    ),
                    if (hasServices)
                      Text(
                        '$_duration min · '
                        '${DateFormat('h:mm a').format(_startsAt)} – ${DateFormat('h:mm a').format(_endsAt)}',
                        style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
                      ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? () => _submit() : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(_startLater == null ? 'Start now' : 'Book it',
                            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- widgets

  Widget _sectionTitle(String text) => Text(text,
      style: GoogleFonts.outfit(
          fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1F2937)));

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        enabled: !_isSubmitting,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );

  Widget _chip({required String label, required bool selected, required VoidCallback onTap}) =>
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isSubmitting ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: GoogleFonts.outfit(
                color: selected ? Colors.white : const Color(0xFF6B7280),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              )),
        ),
      );

  Widget _notice(String text, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: GoogleFonts.outfit(fontSize: 12.5, color: color)),
      );
}
