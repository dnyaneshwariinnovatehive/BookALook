import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/walk_in_api.dart';
import '../theme/app_theme.dart';
import 'collect_payment_sheet.dart';

/// Screen displaying the history of all walk-in customers with metrics,
/// instant search, date and status filters, and rich itemized receipt breakdowns.
class WalkInHistoryScreen extends StatefulWidget {
  final String salonId;
  final String? salonName;

  const WalkInHistoryScreen({
    super.key,
    required this.salonId,
    this.salonName,
  });

  @override
  State<WalkInHistoryScreen> createState() => _WalkInHistoryScreenState();
}

class _WalkInHistoryScreenState extends State<WalkInHistoryScreen> {
  final _searchController = TextEditingController();

  WalkInHistoryResponse? _historyData;
  bool _isLoading = true;
  String? _errorMessage;

  // Filters
  String _selectedDateFilter = 'all'; // 'all', 'today', 'yesterday', 'this_week', 'this_month', or 'YYYY-MM-DD'
  String _selectedStatusFilter = 'all'; // 'all', 'in_progress', 'completed', 'scheduled', 'cancelled'
  String _selectedScope = 'all'; // 'all' or 'my'
  DateTime? _customSelectedDate;

  final DateFormat _dateFormat = DateFormat('EEE, d MMM yyyy');
  final DateFormat _timeFormat = DateFormat('h:mm a');

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await WalkInApi.history(
        widget.salonId,
        search: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
        date: _selectedDateFilter,
        status: _selectedStatusFilter,
        scope: _selectedScope,
      );

      if (!mounted) return;
      setState(() {
        _historyData = res;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _onDateFilterSelected(String filterKey) {
    if (filterKey == 'custom') {
      _pickCustomDate();
      return;
    }

    setState(() {
      _selectedDateFilter = filterKey;
      _customSelectedDate = null;
    });
    _loadHistory();
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customSelectedDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.accentColor,
              onPrimary: Colors.white,
              onSurface: Color(0xFF1F2937),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {
        _customSelectedDate = picked;
        _selectedDateFilter = formatted;
      });
      _loadHistory();
    }
  }

  void _onStatusFilterSelected(String statusKey) {
    setState(() {
      _selectedStatusFilter = statusKey;
    });
    _loadHistory();
  }

  void _onScopeChanged(String scope) {
    setState(() {
      _selectedScope = scope;
    });
    _loadHistory();
  }

  Future<void> _callCustomer(String phone) async {
    if (phone.isEmpty) return;
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open dialer.')),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleCollectPayment(WalkInHistoryItem item) async {
    final collected = await CollectPaymentSheet.show(
      context,
      salonId: widget.salonId,
      appointmentId: item.id,
    );

    if (collected == true) {
      _loadHistory();
    }
  }

  String _formatTimeString(String rawTime) {
    try {
      final parts = rawTime.split(':');
      if (parts.length >= 2) {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
        return _timeFormat.format(dt);
      }
    } catch (_) {}
    return rawTime;
  }

  String _formatDateString(String rawDate) {
    try {
      final parsed = DateTime.parse(rawDate);
      final now = DateTime.now();
      if (parsed.year == now.year && parsed.month == now.month && parsed.day == now.day) {
        return 'Today';
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (parsed.year == yesterday.year && parsed.month == yesterday.month && parsed.day == yesterday.day) {
        return 'Yesterday';
      }
      return _dateFormat.format(parsed);
    } catch (_) {
      return rawDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = _historyData?.viewerRole == 'service_provider';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1F2937), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Walk-in History',
              style: GoogleFonts.outfit(
                color: const Color(0xFF1F2937),
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.salonName != null)
              Text(
                widget.salonName!,
                style: GoogleFonts.outfit(
                  color: const Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentColor),
            tooltip: 'Refresh list',
            onPressed: _loadHistory,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        color: AppTheme.accentColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // Top Summary Cards
            _buildSummaryMetrics(),
            const SizedBox(height: 14),

            // Provider scope toggle (if viewer is service_provider)
            if (isProvider) ...[
              _buildProviderScopeFilter(),
              const SizedBox(height: 12),
            ],

            // Search Bar
            _buildSearchBar(),
            const SizedBox(height: 12),

            // Date Filters
            _buildDateFilterChips(),
            const SizedBox(height: 8),

            // Status Filters
            _buildStatusFilterChips(),
            const SizedBox(height: 16),

            // Content Area
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.accentColor),
                ),
              )
            else if (_errorMessage != null)
              _buildErrorView()
            else if (_historyData == null || _historyData!.walkIns.isEmpty)
              _buildEmptyView()
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_historyData!.walkIns.length} Records Found',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  Text(
                    'Pull down to refresh',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final item in _historyData!.walkIns) ...[
                _buildWalkInCard(item),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- Summary Cards
  Widget _buildSummaryMetrics() {
    final summary = _historyData?.summary;
    final total = summary?.totalWalkIns ?? 0;
    final today = summary?.todayWalkIns ?? 0;
    final inProgress = summary?.inProgress ?? 0;
    final revenue = summary?.totalRevenue ?? 0.0;

    return Row(
      children: [
        Expanded(
          child: _metricCard(
            title: 'Total Walk-ins',
            value: total.toString(),
            icon: Icons.groups_rounded,
            color: AppTheme.accentColor,
            bgColor: const Color(0xFFF3E8FF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            title: 'Today',
            value: today.toString(),
            icon: Icons.today_rounded,
            color: const Color(0xFF2563EB),
            bgColor: const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            title: 'In Progress',
            value: inProgress.toString(),
            icon: Icons.bolt_rounded,
            color: const Color(0xFFD97706),
            bgColor: const Color(0xFFFEF3C7),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            title: 'Revenue',
            value: '₹${NumberFormat.compact().format(revenue)}',
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFF059669),
            bgColor: const Color(0xFFD1FAE5),
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Scope Toggle
  Widget _buildProviderScopeFilter() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _onScopeChanged('all'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedScope == 'all' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _selectedScope == 'all'
                      ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'All Salon Walk-ins',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: _selectedScope == 'all' ? FontWeight.w700 : FontWeight.w500,
                    color: _selectedScope == 'all' ? AppTheme.accentColor : const Color(0xFF4B5563),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _onScopeChanged('my'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedScope == 'my' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _selectedScope == 'my'
                      ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'My Served Walk-ins',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: _selectedScope == 'my' ? FontWeight.w700 : FontWeight.w500,
                    color: _selectedScope == 'my' ? AppTheme.accentColor : const Color(0xFF4B5563),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Search
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF1F2937)),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _loadHistory(),
        decoration: InputDecoration(
          hintText: 'Search by customer name or phone...',
          hintStyle: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF9CA3AF)),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6B7280), size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF9CA3AF)),
                  onPressed: () {
                    _searchController.clear();
                    _loadHistory();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- Date Filters
  Widget _buildDateFilterChips() {
    final chips = [
      {'key': 'all', 'label': 'All Time'},
      {'key': 'today', 'label': 'Today'},
      {'key': 'yesterday', 'label': 'Yesterday'},
      {'key': 'this_week', 'label': 'This Week'},
      {'key': 'this_month', 'label': 'This Month'},
      {
        'key': 'custom',
        'label': _customSelectedDate != null
            ? DateFormat('d MMM').format(_customSelectedDate!)
            : 'Pick Date 📅',
      },
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = chips[index];
          final isSelected = item['key'] == 'custom'
              ? _customSelectedDate != null
              : _selectedDateFilter == item['key'];

          return GestureDetector(
            onTap: () => _onDateFilterSelected(item['key']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.accentColor : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.accentColor : const Color(0xFFD1D5DB),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                item['label']!,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF374151),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- Status Filters
  Widget _buildStatusFilterChips() {
    final statuses = [
      {'key': 'all', 'label': 'All Statuses'},
      {'key': 'in_progress', 'label': 'In Progress'},
      {'key': 'completed', 'label': 'Completed'},
      {'key': 'scheduled', 'label': 'Scheduled'},
      {'key': 'cancelled', 'label': 'Cancelled'},
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: statuses.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = statuses[index];
          final isSelected = _selectedStatusFilter == item['key'];

          return GestureDetector(
            onTap: () => _onStatusFilterSelected(item['key']!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                item['label']!,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF4B5563),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- Walk-in Card
  Widget _buildWalkInCard(WalkInHistoryItem item) {
    final statusColor = _statusColor(item.status);
    final statusBgColor = _statusBgColor(item.status);
    final statusLabel = _statusLabel(item.status);

    return InkWell(
      onTap: () => _showWalkInDetailsSheet(context, item),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: item.isInProgress
                ? const Color(0xFFF59E0B).withOpacity(0.5)
                : const Color(0xFFE5E7EB),
            width: item.isInProgress ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: item.isInProgress
                  ? const Color(0xFFF59E0B).withOpacity(0.06)
                  : Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Avatar + Name & Phone + Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Initials Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.accentColor.withOpacity(0.12),
                  child: Text(
                    _initials(item.customerName),
                    style: GoogleFonts.outfit(
                      color: AppTheme.accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Customer Name & Phone
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.customerName,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.customerGender != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.customerGender!,
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      if (item.customerPhone.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 13, color: Color(0xFF6B7280)),
                            const SizedBox(width: 4),
                            Text(
                              item.customerPhone,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF4B5563),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _callCustomer(item.customerPhone),
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(Icons.call_outlined, size: 14, color: AppTheme.accentColor),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'No phone recorded',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            const SizedBox(height: 12),

            // Date & Time + Staff Row
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF6B7280)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '${_formatDateString(item.appointmentDate)} • ${_formatTimeString(item.startTime)}',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF374151),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.person_pin_circle_outlined, size: 14, color: Color(0xFF6B7280)),
                    const SizedBox(width: 4),
                    Text(
                      item.servingProviderName ?? item.appointedProviderName ?? 'Staff',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Services list chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in item.services)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      '${s.name} • ₹${s.price.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ),
                // Mid-appointment additions
                for (final extra in item.serviceAdditions)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Text(
                      '+ ${extra.name} • ₹${extra.price.toStringAsFixed(0)} (Extra)',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF92400E),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            const SizedBox(height: 10),

            // Bottom row: Total & Payment status + Action Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Billed',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '₹${item.displayAmount.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (item.isCompleted && item.paymentMode != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Paid (${item.paymentMode!.toUpperCase()})',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF059669),
                              ),
                            ),
                          )
                        else if (item.isInProgress)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '₹${item.balanceAmount.toStringAsFixed(0)} due',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFD97706),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (item.isInProgress)
                      ElevatedButton.icon(
                        onPressed: () => _handleCollectPayment(item),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.point_of_sale_rounded, size: 16),
                        label: Text(
                          'Collect Bill',
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      )
                    else
                      OutlinedButton(
                        onPressed: () => _showWalkInDetailsSheet(context, item),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF374151),
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'View Details',
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- Details Bottom Sheet
  void _showWalkInDetailsSheet(BuildContext context, WalkInHistoryItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 12,
            left: 20,
            right: 20,
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Walk-in Summary',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      Text(
                        'ID: ${item.id.substring(0, 8).toUpperCase()}',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusBgColor(item.status),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusLabel(item.status),
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(item.status),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Expanded(
                child: ListView(
                  children: [
                    // Customer Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.customerName,
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              if (item.customerGender != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Text(
                                    item.customerGender!,
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF4B5563),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (item.customerPhone.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF6B7280)),
                                const SizedBox(width: 6),
                                Text(
                                  item.customerPhone,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF374151),
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () => _callCustomer(item.customerPhone),
                                  icon: const Icon(Icons.call, size: 14),
                                  label: const Text('Call'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.accentColor,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                TextButton.icon(
                                  onPressed: () => _copyToClipboard(item.customerPhone, 'Phone number'),
                                  icon: const Icon(Icons.copy_rounded, size: 14),
                                  label: const Text('Copy'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF6B7280),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Staff and Timings Block
                    _detailRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Date & Time',
                      value: '${_formatDateString(item.appointmentDate)} at ${_formatTimeString(item.startTime)} - ${_formatTimeString(item.endTime)}',
                    ),
                    const SizedBox(height: 8),
                    _detailRow(
                      icon: Icons.person_outline_rounded,
                      label: 'Serving Staff',
                      value: item.servingProviderName ?? item.appointedProviderName ?? 'Staff',
                    ),
                    if (item.startedAt != null) ...[
                      const SizedBox(height: 8),
                      _detailRow(
                        icon: Icons.play_arrow_rounded,
                        label: 'Started At',
                        value: _formatTimestamp(item.startedAt!),
                      ),
                    ],
                    if (item.completedAt != null) ...[
                      const SizedBox(height: 8),
                      _detailRow(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Completed At',
                        value: _formatTimestamp(item.completedAt!),
                      ),
                    ],
                    if (item.manualCheckInReason != null) ...[
                      const SizedBox(height: 8),
                      _detailRow(
                        icon: Icons.info_outline_rounded,
                        label: 'Verification Note',
                        value: item.manualCheckInReason!,
                      ),
                    ],
                    const SizedBox(height: 18),

                    // Services Breakdown
                    Text(
                      'Services Provided',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final s in item.services)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1F2937),
                                    ),
                                  ),
                                  Text(
                                    '${s.category} • ${s.durationMinutes} mins',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '₹${s.price.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111827),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Additional Services Mid-appointment
                    if (item.serviceAdditions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Mid-Appointment Additions',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final extra in item.serviceAdditions)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7).withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      extra.name,
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF92400E),
                                      ),
                                    ),
                                    Text(
                                      'Added by ${extra.addedByName ?? 'staff'} • ${extra.durationMinutes} mins',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        color: const Color(0xFFB45309),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '₹${extra.price.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],

                    const SizedBox(height: 16),

                    // Bill Summary Breakdown
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FE),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          _billSummaryLine('Total Amount', '₹${item.totalAmount.toStringAsFixed(0)}'),
                          if (item.advanceAmount > 0)
                            _billSummaryLine('Advance Paid', '-₹${item.advanceAmount.toStringAsFixed(0)}'),
                          if (item.finalBilledAmount != null && item.finalBilledAmount != item.totalAmount)
                            _billSummaryLine('Final Billed', '₹${item.finalBilledAmount!.toStringAsFixed(0)}'),
                          const Divider(height: 16, color: Color(0xFFE5E7EB)),
                          _billSummaryLine(
                            'Balance Due',
                            '₹${item.balanceAmount.toStringAsFixed(0)}',
                            isBold: true,
                            valueColor: item.balanceAmount > 0 ? const Color(0xFFD97706) : const Color(0xFF059669),
                          ),
                          if (item.paymentMode != null) ...[
                            const SizedBox(height: 8),
                            _billSummaryLine(
                              'Payment Mode',
                              item.paymentMode!.toUpperCase(),
                              valueColor: const Color(0xFF059669),
                            ),
                          ],
                          if (item.paymentCollectedByName != null) ...[
                            const SizedBox(height: 4),
                            _billSummaryLine('Collected By', item.paymentCollectedByName!),
                          ],
                          if (item.invoiceNumber != null) ...[
                            const SizedBox(height: 4),
                            _billSummaryLine('Invoice No.', item.invoiceNumber!),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // Bottom Action Button
              if (item.isInProgress)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleCollectPayment(item);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Collect Payment & Complete Visit',
                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4B5563),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF6B7280),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1F2937),
            ),
          ),
        ),
      ],
    );
  }

  Widget _billSummaryLine(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? const Color(0xFF111827) : const Color(0xFF6B7280),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: isBold ? 16 : 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? (isBold ? const Color(0xFF111827) : const Color(0xFF374151)),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Helper Views
  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: Color(0xFFF3E8FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline_rounded, size: 42, color: AppTheme.accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              'No Walk-in Records Found',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try adjusting your search query, date range, or status filters.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _selectedDateFilter = 'all';
                  _selectedStatusFilter = 'all';
                  _customSelectedDate = null;
                });
                _loadHistory();
              },
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('Reset All Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 14),
            Text(
              'Unable to Load Walk-in History',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'An unexpected error occurred.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadHistory,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- Helpers
  Color _statusColor(String status) {
    switch (status) {
      case 'in_progress':
        return const Color(0xFFD97706);
      case 'completed':
        return const Color(0xFF059669);
      case 'scheduled':
        return const Color(0xFF2563EB);
      case 'cancelled':
      case 'no_show':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF4B5563);
    }
  }

  Color _statusBgColor(String status) {
    switch (status) {
      case 'in_progress':
        return const Color(0xFFFEF3C7);
      case 'completed':
        return const Color(0xFFD1FAE5);
      case 'scheduled':
        return const Color(0xFFEFF6FF);
      case 'cancelled':
      case 'no_show':
        return const Color(0xFFFEE2E2);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'scheduled':
        return 'Scheduled';
      case 'cancelled':
        return 'Cancelled';
      case 'no_show':
        return 'No Show';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'W';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _formatTimestamp(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('d MMM, h:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }
}
