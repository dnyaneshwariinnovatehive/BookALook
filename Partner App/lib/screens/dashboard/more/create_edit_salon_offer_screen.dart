import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../services/salon_offers_api.dart';

class CreateEditSalonOfferScreen extends StatefulWidget {
  final String salonId;
  final String? offerId;

  const CreateEditSalonOfferScreen({
    super.key,
    required this.salonId,
    this.offerId,
  });

  bool get isEditing => offerId != null;

  @override
  State<CreateEditSalonOfferScreen> createState() => _CreateEditSalonOfferScreenState();
}

class _CreateEditSalonOfferScreenState extends State<CreateEditSalonOfferScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Options from server
  List<Map<String, dynamic>> _availableServices = [];
  Map<String, dynamic> _policy = {};

  // Form controllers & state
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _discountValController = TextEditingController(text: '20');
  final TextEditingController _capController = TextEditingController(text: '500');
  final TextEditingController _minServicePriceController = TextEditingController();
  final TextEditingController _minEligibleSubtotalController = TextEditingController();
  final TextEditingController _minTotalSubtotalController = TextEditingController();
  final TextEditingController _maxRedemptionsController = TextEditingController();

  String _scope = 'new_to_salon';
  String _discountType = 'percentage';
  bool _isActive = true;

  DateTime? _startsAt;
  TimeOfDay? _startsAtTime;
  DateTime? _endsAt;
  TimeOfDay? _endsAtTime;

  final Set<String> _selectedTemplateIds = {};

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _discountValController.dispose();
    _capController.dispose();
    _minServicePriceController.dispose();
    _minEligibleSubtotalController.dispose();
    _minTotalSubtotalController.dispose();
    _maxRedemptionsController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final options = await SalonOffersApi.fetchOptions(widget.salonId);
      final rawServices = options['services'] as List? ?? [];
      _availableServices = rawServices.map((e) => Map<String, dynamic>.from(e)).toList();
      _policy = Map<String, dynamic>.from(options['policy'] ?? {});

      if (!widget.isEditing) {
        // Defaults for creation
        _startsAt = DateTime.now();
        _startsAtTime = TimeOfDay.fromDateTime(_startsAt!);
        _capController.text = (_policy['default_percentage_cap'] ?? 500).toString();
        // Select all services by default
        for (var s in _availableServices) {
          final tplId = s['service_template_id']?.toString();
          if (tplId != null) _selectedTemplateIds.add(tplId);
        }
      } else {
        // Load existing offer for editing
        final offer = await SalonOffersApi.getOffer(widget.salonId, widget.offerId!);
        _nameController.text = offer['name'] ?? '';
        _descController.text = offer['description'] ?? '';
        _scope = offer['scope'] ?? 'new_to_salon';
        _discountType = offer['discount_type'] ?? 'percentage';
        _discountValController.text = (offer['discount_value'] ?? '').toString();
        _capController.text = (offer['max_discount_cap'] ?? '').toString();

        if (offer['min_service_price'] != null) {
          _minServicePriceController.text = offer['min_service_price'].toString();
        }
        if (offer['min_eligible_subtotal'] != null) {
          _minEligibleSubtotalController.text = offer['min_eligible_subtotal'].toString();
        }
        if (offer['min_total_booking_subtotal'] != null) {
          _minTotalSubtotalController.text = offer['min_total_booking_subtotal'].toString();
        }
        if (offer['max_redemptions'] != null) {
          _maxRedemptionsController.text = offer['max_redemptions'].toString();
        }

        _isActive = offer['is_active'] == true;

        if (offer['starts_at'] != null) {
          final dt = DateTime.tryParse(offer['starts_at'].toString())?.toLocal();
          if (dt != null) {
            _startsAt = dt;
            _startsAtTime = TimeOfDay.fromDateTime(dt);
          }
        }
        if (offer['ends_at'] != null) {
          final dt = DateTime.tryParse(offer['ends_at'].toString())?.toLocal();
          if (dt != null) {
            _endsAt = dt;
            _endsAtTime = TimeOfDay.fromDateTime(dt);
          }
        }

        final tpls = offer['service_templates'] as List? ?? [];
        for (var t in tpls) {
          final id = t['id']?.toString();
          if (id != null) _selectedTemplateIds.add(id);
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedTemplateIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select at least one eligible service', style: GoogleFonts.outfit()),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    final double discountVal = double.tryParse(_discountValController.text.trim()) ?? 0;
    final double minPercent = (_policy['min_percentage'] as num?)?.toDouble() ?? 5.0;
    final double maxPercent = (_policy['max_percentage'] as num?)?.toDouble() ?? 50.0;
    final double minFlat = (_policy['min_flat_amount'] as num?)?.toDouble() ?? 1.0;
    final double maxFlat = (_policy['max_flat_amount'] as num?)?.toDouble() ?? 1000.0;
    final double platformMaxCap = (_policy['platform_max_cap'] as num?)?.toDouble() ?? 5000.0;

    if (_discountType == 'percentage') {
      if (discountVal < minPercent || discountVal > maxPercent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Percentage discount must be between $minPercent% and $maxPercent%', style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
        return;
      }
    } else {
      if (discountVal < minFlat || discountVal > maxFlat) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Flat discount must be between ₹$minFlat and ₹$maxFlat', style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
        return;
      }
    }

    DateTime? fullStartsAt;
    if (_startsAt != null) {
      final t = _startsAtTime ?? const TimeOfDay(hour: 0, minute: 0);
      fullStartsAt = DateTime(_startsAt!.year, _startsAt!.month, _startsAt!.day, t.hour, t.minute);
    }

    DateTime? fullEndsAt;
    if (_endsAt != null) {
      final t = _endsAtTime ?? const TimeOfDay(hour: 23, minute: 59);
      fullEndsAt = DateTime(_endsAt!.year, _endsAt!.month, _endsAt!.day, t.hour, t.minute);
    }

    if (fullStartsAt != null && fullEndsAt != null && fullEndsAt.isBefore(fullStartsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('End date must be after start date', style: GoogleFonts.outfit()),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    final payload = <String, dynamic>{
      'name': _nameController.text.trim(),
      'description': _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      'scope': _scope,
      'discount_type': _discountType,
      'discount_value': discountVal,
      'is_active': _isActive,
      'service_template_ids': _selectedTemplateIds.toList(),
    };

    if (_capController.text.trim().isNotEmpty) {
      final cap = double.tryParse(_capController.text.trim());
      if (cap != null && cap <= platformMaxCap) {
        payload['max_discount_cap'] = cap;
      }
    }

    if (_minServicePriceController.text.trim().isNotEmpty) {
      payload['min_service_price'] = double.tryParse(_minServicePriceController.text.trim());
    }
    if (_minEligibleSubtotalController.text.trim().isNotEmpty) {
      payload['min_eligible_subtotal'] = double.tryParse(_minEligibleSubtotalController.text.trim());
    }
    if (_minTotalSubtotalController.text.trim().isNotEmpty) {
      payload['min_total_booking_subtotal'] = double.tryParse(_minTotalSubtotalController.text.trim());
    }
    if (_maxRedemptionsController.text.trim().isNotEmpty) {
      payload['max_redemptions'] = int.tryParse(_maxRedemptionsController.text.trim());
    }

    if (fullStartsAt != null) {
      payload['starts_at'] = fullStartsAt.toUtc().toIso8601String();
    }
    if (fullEndsAt != null) {
      payload['ends_at'] = fullEndsAt.toUtc().toIso8601String();
    }

    setState(() => _isSaving = true);

    try {
      if (widget.isEditing) {
        await SalonOffersApi.updateOffer(widget.salonId, widget.offerId!, payload);
      } else {
        await SalonOffersApi.createOffer(widget.salonId, payload);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing ? 'Offer updated successfully!' : 'Offer created successfully!',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''), style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Edit Offer' : 'Create Offer',
          style: GoogleFonts.outfit(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF9850F1)))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Color(0xFFDC2626)),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center, style: GoogleFonts.outfit()),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9850F1)),
                          onPressed: _loadData,
                          child: Text('Retry', style: GoogleFonts.outfit(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBasicInfoSection(),
                        const SizedBox(height: 16),
                        _buildScopeSection(),
                        const SizedBox(height: 16),
                        _buildDiscountSection(),
                        const SizedBox(height: 16),
                        _buildServicesSection(),
                        const SizedBox(height: 16),
                        _buildValidityAndLimitsSection(),
                        const SizedBox(height: 24),
                        _buildSaveButton(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildCard({required String title, String? subtitle, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return _buildCard(
      title: 'Offer Overview',
      subtitle: 'Give your campaign a title and short description for clients',
      children: [
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Offer Name *',
            hintText: 'e.g. Welcome 20% Off',
            labelStyle: GoogleFonts.outfit(color: Colors.grey.shade700),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          ),
          style: GoogleFonts.outfit(),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Offer name is required';
            if (v.trim().length > 150) return 'Name cannot exceed 150 characters';
            return null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _descController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Description (Optional)',
            hintText: 'e.g. Applicable on first salon appointment for haircut and facial',
            labelStyle: GoogleFonts.outfit(color: Colors.grey.shade700),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          ),
          style: GoogleFonts.outfit(),
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Active status', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(
            _isActive ? 'Offer is currently enabled for eligible clients' : 'Offer is paused and cannot be claimed',
            style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
          ),
          value: _isActive,
          activeThumbColor: const Color(0xFF16A34A),
          onChanged: (val) => setState(() => _isActive = val),
        ),
      ],
    );
  }

  Widget _buildScopeSection() {
    return _buildCard(
      title: 'Customer Eligibility Scope',
      subtitle: 'Specify who qualifies for this first-time promotion',
      children: [
        _buildScopeOption(
          scopeKey: 'new_to_salon',
          title: 'First booking at this salon',
          desc: 'Eligible only if the customer has no previous booking at your specific salon.',
          icon: Icons.storefront,
          badgeColor: const Color(0xFF0F766E),
          badgeBg: const Color(0xFFCCFBF1),
        ),
        const SizedBox(height: 10),
        _buildScopeOption(
          scopeKey: 'new_to_platform',
          title: 'First booking on BookALook',
          desc: 'Eligible only if the customer has no previous booking anywhere on the platform.',
          icon: Icons.public,
          badgeColor: const Color(0xFF7E22CE),
          badgeBg: const Color(0xFFF3E8FF),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Eligibility Note: Previous bookings count towards eligibility even if they were cancelled, preventing repeat discount misuse.',
                  style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF1E40AF)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScopeOption({
    required String scopeKey,
    required String title,
    required String desc,
    required IconData icon,
    required Color badgeColor,
    required Color badgeBg,
  }) {
    final isSelected = _scope == scopeKey;
    return InkWell(
      onTap: () => setState(() => _scope = scopeKey),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF5F3FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF9850F1) : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: badgeColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(desc, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFF9850F1) : Colors.grey.shade400,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountSection() {
    final isPercent = _discountType == 'percentage';
    final double minPercent = (_policy['min_percentage'] as num?)?.toDouble() ?? 5.0;
    final double maxPercent = (_policy['max_percentage'] as num?)?.toDouble() ?? 50.0;
    final double minFlat = (_policy['min_flat_amount'] as num?)?.toDouble() ?? 1.0;
    final double maxFlat = (_policy['max_flat_amount'] as num?)?.toDouble() ?? 1000.0;

    return _buildCard(
      title: 'Discount Rules & Limits',
      subtitle: 'Configure discount value and per-booking caps',
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _discountType = 'percentage';
                    _capController.text = (_policy['default_percentage_cap'] ?? 500).toString();
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isPercent ? const Color(0xFF9850F1) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Percentage (%)',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: isPercent ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _discountType = 'flat';
                    _capController.text = (_policy['default_flat_cap'] ?? 1000).toString();
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: !isPercent ? const Color(0xFF9850F1) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Flat Amount (₹)',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: !isPercent ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _discountValController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: isPercent ? 'Discount (%) *' : 'Discount (₹) *',
                  helperText: isPercent ? '$minPercent% – $maxPercent%' : '₹$minFlat – ₹$maxFlat',
                  helperStyle: GoogleFonts.outfit(fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                ),
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final val = double.tryParse(v.trim());
                  if (val == null) return 'Invalid number';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextFormField(
                controller: _capController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: isPercent ? 'Max Cap (₹)' : 'Booking Cap (₹)',
                  helperText: 'Max limit per appointment',
                  helperStyle: GoogleFonts.outfit(fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                ),
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Minimum Spend Thresholds (Optional)', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _minServicePriceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Min Service Price',
                  hintText: '₹0',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                ),
                style: GoogleFonts.outfit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _minTotalSubtotalController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Min Total Booking',
                  hintText: '₹0',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                ),
                style: GoogleFonts.outfit(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServicesSection() {
    return _buildCard(
      title: 'Eligible Services',
      subtitle: 'The discount applies only to explicitly selected services below',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_selectedTemplateIds.length} of ${_availableServices.length} selected',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      for (var s in _availableServices) {
                        final tplId = s['service_template_id']?.toString();
                        if (tplId != null) _selectedTemplateIds.add(tplId);
                      }
                    });
                  },
                  child: Text('Select All', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF9850F1))),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _selectedTemplateIds.clear());
                  },
                  child: Text('Clear', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_availableServices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No active services found in your salon catalogue. Please add services first.',
              style: GoogleFonts.outfit(color: Colors.grey),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: const BoxConstraints(maxHeight: 250),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _availableServices.length,
              separatorBuilder: (ctx, idx) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = _availableServices[index];
                final tplId = s['service_template_id']?.toString() ?? '';
                final name = s['name'] ?? 'Service';
                final category = s['category'] ?? '';
                final price = s['price'] ?? 0;
                final isChecked = _selectedTemplateIds.contains(tplId);

                return CheckboxListTile(
                  dense: true,
                  activeColor: const Color(0xFF9850F1),
                  title: Text(name, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('$category • ₹$price', style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey)),
                  value: isChecked,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedTemplateIds.add(tplId);
                      } else {
                        _selectedTemplateIds.remove(tplId);
                      }
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildValidityAndLimitsSection() {
    return _buildCard(
      title: 'Schedule & Campaign Limits',
      subtitle: 'Optional campaign start/end dates and total redemption caps',
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start Date', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startsAt ?? DateTime.now(),
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() => _startsAt = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _startsAt != null ? _dateFormat.format(_startsAt!) : 'Immediate',
                            style: GoogleFonts.outfit(fontSize: 13),
                          ),
                          const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('End Date (Optional)', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endsAt ?? (_startsAt ?? DateTime.now()).add(const Duration(days: 30)),
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() => _endsAt = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _endsAt != null ? _dateFormat.format(_endsAt!) : 'No Expiry',
                            style: GoogleFonts.outfit(fontSize: 13),
                          ),
                          if (_endsAt != null)
                            GestureDetector(
                              onTap: () => setState(() => _endsAt = null),
                              child: const Icon(Icons.close, size: 14, color: Colors.grey),
                            )
                          else
                            const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _maxRedemptionsController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Campaign Redemption Cap (Optional)',
            hintText: 'e.g. 50 (leaves blank for unlimited)',
            helperText: 'Offer auto-expires when this limit of completed bookings is reached',
            helperStyle: GoogleFonts.outfit(fontSize: 11),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
          ),
          style: GoogleFonts.outfit(),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF9850F1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
        onPressed: _isSaving ? null : _submit,
        child: _isSaving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Text(
                widget.isEditing ? 'Save Offer Changes' : 'Create & Publish Offer',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
