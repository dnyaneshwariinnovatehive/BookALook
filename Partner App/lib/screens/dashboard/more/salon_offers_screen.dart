import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/salon_offers_api.dart';
import 'create_edit_salon_offer_screen.dart';

class SalonOffersScreen extends StatefulWidget {
  final String salonId;

  const SalonOffersScreen({super.key, required this.salonId});

  @override
  State<SalonOffersScreen> createState() => _SalonOffersScreenState();
}

class _SalonOffersScreenState extends State<SalonOffersScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _offers = [];
  String _selectedFilter = 'All';

  final List<String> _filterTabs = ['All', 'Active', 'Inactive', 'Scheduled', 'Expired'];

  @override
  void initState() {
    super.initState();
    _loadOffers();
  }

  Future<void> _loadOffers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final offers = await SalonOffersApi.listOffers(
        widget.salonId,
        status: _selectedFilter == 'All' ? null : _selectedFilter,
      );
      if (mounted) {
        setState(() {
          _offers = offers;
          _isLoading = false;
        });
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

  Future<void> _toggleActive(Map<String, dynamic> offer, bool targetActive) async {
    final offerId = offer['id']?.toString() ?? '';
    try {
      await SalonOffersApi.toggleActive(widget.salonId, offerId, isActive: targetActive);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            targetActive ? 'Offer activated' : 'Offer deactivated',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: targetActive ? const Color(0xFF16A34A) : Colors.black87,
          duration: const Duration(seconds: 2),
        ),
      );
      _loadOffers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''), style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _deleteOffer(Map<String, dynamic> offer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Offer', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "${offer['name']}"? Historical bookings that applied this offer will remain unaffected.',
          style: GoogleFonts.outfit(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await SalonOffersApi.deleteOffer(widget.salonId, offer['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Offer deleted successfully', style: GoogleFonts.outfit()),
          duration: const Duration(seconds: 2),
        ),
      );
      _loadOffers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''), style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  void _openCreateScreen() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditSalonOfferScreen(salonId: widget.salonId),
      ),
    );
    if (result == true) {
      _loadOffers();
    }
  }

  void _openEditScreen(Map<String, dynamic> offer) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditSalonOfferScreen(
          salonId: widget.salonId,
          offerId: offer['id']?.toString(),
        ),
      ),
    );
    if (result == true) {
      _loadOffers();
    }
  }

  List<Map<String, dynamic>> get _filteredOffers {
    if (_selectedFilter == 'All') return _offers;
    return _offers.where((o) {
      final status = (o['status_label'] ?? '').toString().toLowerCase();
      return status == _selectedFilter.toLowerCase();
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text(
          'Offers & Discounts',
          style: GoogleFonts.outfit(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadOffers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF9850F1),
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text('Create Offer', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
        onPressed: _openCreateScreen,
      ),
      body: Column(
        children: [
          // Filter Tabs
          _buildFilterTabs(),

          // Main Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9850F1)))
                : _errorMessage != null
                    ? _buildErrorState()
                    : _filteredOffers.isEmpty
                        ? _buildEmptyState()
                        : _buildOffersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _filterTabs.map((tab) {
            final isSelected = _selectedFilter == tab;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(
                  tab,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
                selected: isSelected,
                selectedColor: const Color(0xFF9850F1),
                backgroundColor: const Color(0xFFF1F5F9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF9850F1) : Colors.transparent,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedFilter = tab);
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildOffersList() {
    return RefreshIndicator(
      color: const Color(0xFF9850F1),
      onRefresh: _loadOffers,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _filteredOffers.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final offer = _filteredOffers[index];
          return _buildOfferCard(offer);
        },
      ),
    );
  }

  Widget _buildOfferCard(Map<String, dynamic> offer) {
    final name = offer['name'] ?? 'Unnamed Offer';
    final desc = offer['description'];
    final scope = offer['scope'] ?? 'new_to_salon';
    final discountType = offer['discount_type'] ?? 'percentage';
    final discountVal = offer['discount_value'] ?? 0;
    final maxCap = offer['max_discount_cap'];
    final isActive = offer['is_active'] == true;
    final status = (offer['status_label'] ?? (isActive ? 'Active' : 'Inactive')).toString();
    final startsAt = offer['starts_at'];
    final endsAt = offer['ends_at'];
    final redemptions = offer['redemptions_count'] ?? offer['current_redemptions'] ?? 0;
    final maxRedemptions = offer['max_redemptions'];

    // Services
    final services = offer['service_templates'] as List? ?? [];
    final serviceCount = services.length;

    // Minimum rules
    final minSpend = offer['min_total_booking_subtotal'] ?? offer['min_eligible_subtotal'];

    // Status colors
    Color statusBgColor;
    Color statusTextColor;
    switch (status.toLowerCase()) {
      case 'active':
        statusBgColor = const Color(0xFFDCFCE7);
        statusTextColor = const Color(0xFF15803D);
        break;
      case 'scheduled':
        statusBgColor = const Color(0xFFE0E7FF);
        statusTextColor = const Color(0xFF4338CA);
        break;
      case 'expired':
        statusBgColor = const Color(0xFFFEE2E2);
        statusTextColor = const Color(0xFFB91C1C);
        break;
      case 'draft':
        statusBgColor = const Color(0xFFFEF3C7);
        statusTextColor = const Color(0xFFB45309);
        break;
      default:
        statusBgColor = const Color(0xFFF1F5F9);
        statusTextColor = const Color(0xFF64748B);
    }

    final isPercentage = discountType == 'percentage';
    final discountText = isPercentage ? '$discountVal% OFF' : '₹$discountVal OFF';

    return InkWell(
      onTap: () => _openEditScreen(offer),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Scope badge + Status badge
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scope == 'new_to_platform'
                          ? const Color(0xFFF3E8FF)
                          : const Color(0xFFCCFBF1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          scope == 'new_to_platform' ? Icons.public : Icons.storefront,
                          size: 13,
                          color: scope == 'new_to_platform'
                              ? const Color(0xFF7E22CE)
                              : const Color(0xFF0F766E),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          scope == 'new_to_platform' ? 'New to BookALook' : 'New to Salon',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: scope == 'new_to_platform'
                                ? const Color(0xFF7E22CE)
                                : const Color(0xFF0F766E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Offer Name & Discount banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        if (desc != null && desc.toString().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            desc.toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9850F1), Color(0xFF7C3AED)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          discountText,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (maxCap != null)
                          Text(
                            'Cap: ₹$maxCap',
                            style: GoogleFonts.outfit(fontSize: 10, color: Colors.white.withValues(alpha: 0.9)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

            // Details info: services, schedule, redemptions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.spa_outlined, size: 15, color: Color(0xFF9850F1)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          serviceCount == 0
                              ? 'No specific services selected'
                              : '$serviceCount eligible ${serviceCount == 1 ? 'service' : 'services'}',
                          style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black87),
                        ),
                      ),
                      if (minSpend != null && num.tryParse('$minSpend') != null && num.parse('$minSpend') > 0) ...[
                        const Icon(Icons.shopping_bag_outlined, size: 15, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          'Min ₹$minSpend',
                          style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 15, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatValidity(startsAt, endsAt),
                          style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                      Icon(Icons.confirmation_number_outlined, size: 15, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        maxRedemptions != null ? '$redemptions / $maxRedemptions' : '$redemptions used',
                        style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Action row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Active switch
                  Row(
                    children: [
                      Switch(
                        value: isActive,
                        activeThumbColor: const Color(0xFF16A34A),
                        onChanged: (val) => _toggleActive(offer, val),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'Active' : 'Inactive',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isActive ? const Color(0xFF16A34A) : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text('Edit', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF9850F1)),
                        onPressed: () => _openEditScreen(offer),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 18),
                        tooltip: 'Delete',
                        onPressed: () => _deleteOffer(offer),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatValidity(dynamic start, dynamic end) {
    if (start == null && end == null) return 'Valid anytime (no expiry)';
    String s = start != null ? start.toString().split('T').first : 'Now';
    String e = end != null ? end.toString().split('T').first : 'No expiry';
    return '$s → $e';
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_offer_outlined, color: Color(0xFF9850F1), size: 44),
            ),
            const SizedBox(height: 20),
            Text(
              _selectedFilter == 'All' ? 'No offers created yet' : 'No $_selectedFilter offers found',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedFilter == 'All'
                  ? 'Attract more first-time clients by launching a welcome discount on your popular salon services.'
                  : 'Try selecting a different filter above or create a new campaign.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13.5, color: Colors.grey.shade600),
            ),
            if (_selectedFilter == 'All') ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9850F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text('Create First Offer', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                onPressed: _openCreateScreen,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 48),
            const SizedBox(height: 12),
            Text('Failed to load offers', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(_errorMessage ?? '', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9850F1)),
              onPressed: _loadOffers,
              child: Text('Try Again', style: GoogleFonts.outfit(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
