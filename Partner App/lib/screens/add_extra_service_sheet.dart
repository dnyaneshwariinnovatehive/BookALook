import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/check_in_api.dart';
import '../services/walk_in_api.dart';
import '../theme/app_theme.dart';

/// Put an extra service on a bill while the customer is still in the chair.
///
/// The customer agreed verbally, so nothing here waits on their phone. What it
/// does insist on is recording who delivered the extra: it defaults to whoever
/// is serving the appointment, but a second staff member stepping in is the
/// case this exists for, and their commission depends on getting it right.
///
/// Returns the refreshed bill when something was added.
class AddExtraServiceSheet extends StatefulWidget {
  final String salonId;
  final String appointmentId;

  /// Whoever is serving the appointment — the default for the extra.
  final String? servingProviderId;
  final String? servingProviderName;

  const AddExtraServiceSheet({
    super.key,
    required this.salonId,
    required this.appointmentId,
    this.servingProviderId,
    this.servingProviderName,
  });

  static Future<CheckInTarget?> show(
    BuildContext context, {
    required String salonId,
    required String appointmentId,
    String? servingProviderId,
    String? servingProviderName,
  }) {
    return showModalBottomSheet<CheckInTarget>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddExtraServiceSheet(
        salonId: salonId,
        appointmentId: appointmentId,
        servingProviderId: servingProviderId,
        servingProviderName: servingProviderName,
      ),
    );
  }

  @override
  State<AddExtraServiceSheet> createState() => _AddExtraServiceSheetState();
}

class _AddExtraServiceSheetState extends State<AddExtraServiceSheet> {
  final _searchController = TextEditingController();

  WalkInOptions? _options;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  String? _serviceId;
  String? _providerId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _providerId = widget.servingProviderId;
    _load();
    _searchController.addListener(
      () => setState(() => _search = _searchController.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Same catalogue the walk-in desk uses: the salon's live, priced services
      // and its staff.
      final options = await WalkInApi.options(widget.salonId);
      if (!mounted) return;
      setState(() {
        _options = options;
        _providerId ??= options.defaultProviderId;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  WalkInService? get _selectedService =>
      _options?.services.where((s) => s.id == _serviceId).firstOrNull;

  WalkInProvider? get _selectedProvider =>
      _options?.providers.where((p) => p.id == _providerId).firstOrNull;

  bool get _providerIsUntrained {
    final provider = _selectedProvider;
    final service = _selectedService;
    if (provider == null || service == null) return false;
    return !provider.serviceIds.contains(service.id);
  }

  Map<String, List<WalkInService>> get _visible {
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

  Future<void> _add() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final target = await CheckInApi.addExtraService(
        widget.salonId,
        widget.appointmentId,
        serviceId: _serviceId!,
        providerId: _providerId,
      );

      if (!mounted) return;
      Navigator.pop(context, target);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _options == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error ?? 'Could not load services.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(color: AppTheme.lightDanger)),
                          ),
                        )
                      : _buildBody(scrollController),
            ),
            if (!_isLoading && _options != null) _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController controller) {
    final grouped = _visible;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      children: [
        Text('Add to the bill',
            style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'Added as its own line — the original booking is left as it is.',
          style: GoogleFonts.outfit(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 18),

        _buildProviderPicker(),

        const SizedBox(height: 20),
        TextField(
          controller: _searchController,
          enabled: !_isSubmitting,
          decoration: InputDecoration(
            hintText: 'Search services',
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (grouped.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _search.isEmpty
                    ? 'This salon has no active services.'
                    : 'No services match "$_search".',
                style: GoogleFonts.outfit(color: Colors.grey.shade600),
              ),
            ),
          )
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

        if (_error != null) ...[
          const SizedBox(height: 12),
          _notice(_error!, AppTheme.lightDanger),
        ],
      ],
    );
  }

  Widget _buildProviderPicker() {
    final providers = _options!.providers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who is doing this extra?',
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          widget.servingProviderName != null
              ? '${widget.servingProviderName} is serving this appointment. '
                  'Change it if someone else does the extra — the commission follows.'
              : 'Commission for this line goes to whoever you pick.',
          style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _providerId,
              isExpanded: true,
              hint: Text('Choose a staff member', style: GoogleFonts.outfit()),
              onChanged: _isSubmitting ? null : (v) => setState(() => _providerId = v),
              items: providers
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(p.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                            ),
                            if (p.id == widget.servingProviderId)
                              _tag('Serving', AppTheme.accentColor),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
        if (_providerIsUntrained) ...[
          const SizedBox(height: 10),
          _notice(
            '${_selectedProvider!.name} is not assigned to ${_selectedService!.name}. '
            'You can still go ahead — the line is credited to them.',
            AppTheme.lightWarning,
          ),
        ],
      ],
    );
  }

  Widget _buildServiceTile(WalkInService service) {
    final selected = _serviceId == service.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isSubmitting ? null : () => setState(() => _serviceId = service.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentColor.withValues(alpha: 0.06) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.accentColor : Colors.transparent,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
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

  Widget _notice(String text, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: GoogleFonts.outfit(fontSize: 12.5, color: color)),
      );

  Widget _tag(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );

  Widget _buildFooter() {
    final service = _selectedService;
    final canAdd = service != null && _providerId != null && !_isSubmitting;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            if (service != null)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('+ ₹${service.price.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(service.name,
                      style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
                ],
              )
            else
              Text('Pick a service',
                  style: GoogleFonts.outfit(fontSize: 15, color: Colors.grey.shade600)),
            const Spacer(),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: canAdd ? _add : null,
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
                    : Text('Add to bill',
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
