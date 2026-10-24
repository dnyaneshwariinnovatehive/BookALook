import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/location_service.dart';
import '../../widgets/city_picker_sheet.dart';
import '../../models/banner.dart';
import '../../services/banner_service.dart';
import '../../widgets/banner_carousel.dart';
import '../../models/category.dart';
import '../../services/category_service.dart';
import '../../services/appointment_service.dart';
import '../../services/notification_service.dart';
import '../notifications_screen.dart';
import '../reschedule_screen.dart';
import '../../services/salon_service.dart';
import '../salon_list_screen.dart';
import '../salon_detail_screen.dart';
import '../my_bookings_screen.dart';
import '../qr_code_screen.dart';
import '../appointment_details_screen.dart';
import '../../utils/check_in_window.dart';
import '../../widgets/category_grid.dart';
import '../categories_screen.dart';
import '../../utils/app_haptics.dart';
import '../search_screen.dart';
import '../category_salons_screen.dart';
import '../../theme/app_colors.dart';
import '../../widgets/skeleton.dart';
import '../../utils/bottom_clearance.dart';
import '../../widgets/animated_search_field.dart';
import '../../utils/feature_flags.dart';

class HomeTab extends StatefulWidget {
  final bool isGuest;

  const HomeTab({Key? key, required this.isGuest}) : super(key: key);

  @override
  _HomeTabState createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<PromoBanner> _banners = [];
  bool _isLoadingBanners = true;
  List<ServiceCategory> _categories = [];
  bool _isLoadingCategories = true;

  /// Bookings the salon released by closing their day. These are the first
  /// thing the customer should see — their money is sitting in one.
  List<dynamic> _needsReschedule = [];
  List<dynamic> _upcoming = [];
  List<dynamic> _past = [];
  int _unreadNotifications = 0;

  List<dynamic> _recommendedSalons = [];
  bool _isLoadingRecommended = true;

  String _selectedGender = 'All';
  final TextEditingController _searchController = TextEditingController();

  ScrollController? _bookAgainScrollController;
  Timer? _bookAgainTimer;

  /// Deduplicated recent salon visits for the Book Again section.
  /// Preserves recent booking order (most recently booked salon first)
  /// and ensures each salon appears only once based on its stable unique salon ID.
  List<Map<String, dynamic>> get _deduplicatedBookAgainList {
    if (_past.isEmpty || widget.isGuest) return [];

    final List<Map<String, dynamic>> deduplicated = [];
    final Set<String> seenSalonIds = {};

    for (final item in _past) {
      if (item is! Map<String, dynamic>) continue;
      final salonId = (item['salon_id'] ?? item['salon']?['id'])?.toString();
      if (salonId == null || salonId.isEmpty) continue;

      if (!seenSalonIds.contains(salonId)) {
        seenSalonIds.add(salonId);
        deduplicated.add(item);
      }
    }

    return deduplicated;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _fetchCategories();
    _fetchAlerts();
    // Another screen can change the city; the header has to follow it.
    LocationService.instance.addListener(_onCityChanged);

    _bookAgainScrollController = ScrollController();
    _startBookAgainTimer();
  }

  @override
  void dispose() {
    LocationService.instance.removeListener(_onCityChanged);
    _searchController.dispose();
    _bookAgainTimer?.cancel();
    _bookAgainScrollController?.dispose();
    super.dispose();
  }

  void _startBookAgainTimer() {
    _bookAgainTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted || _bookAgainScrollController == null) return;
      if (!_bookAgainScrollController!.hasClients) return;
      final list = _deduplicatedBookAgainList;
      if (list.length <= 1) return;

      final maxScroll = _bookAgainScrollController!.position.maxScrollExtent;
      final currentOffset = _bookAgainScrollController!.offset;
      final stride = 250.0 + 14.0; // card width + gap
      double targetOffset = currentOffset + stride;

      if (targetOffset > maxScroll + 10) {
        targetOffset = 0.0;
      }

      _bookAgainScrollController!.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  /// The stored city has to be read before anything city-scoped is fetched,
  /// otherwise the first load asks for the wrong market and corrects itself a
  /// moment later in front of the customer.
  Future<void> _bootstrap() async {
    await LocationService.instance.restore();
    if (!mounted) return;
    setState(() {});
    _fetchBanners();
    _fetchRecommendedSalons();
  }

  void _onCityChanged() {
    if (!mounted) return;
    setState(() {
      _isLoadingBanners = true;
      _isLoadingRecommended = true;
    });
    _fetchBanners();
    _fetchRecommendedSalons();
  }

  /// Let the customer change market, and reload what that changes.
  Future<void> _pickCity() async {
    final changed = await showCityPicker(context);

    if (changed && mounted) {
      setState(() {
        _isLoadingBanners = true;
        _isLoadingRecommended = true;
      });
      _fetchBanners();
      _fetchRecommendedSalons();
    }
  }

  /// Fetch recommended salons prioritizing nearby and top-rated salons.
  /// Reuses SalonService().fetchSalons() which respects location coordinates
  /// and selected city, deduplicating results by salon ID.
  Future<void> _fetchRecommendedSalons() async {
    try {
      final response = await SalonService().fetchSalons();
      if (!mounted) return;
      final rawSalons = (response['salons'] as List?) ?? [];
      final suggested = (response['suggested_salons'] as List?) ?? [];

      final allSalons = rawSalons.isNotEmpty ? rawSalons : suggested;

      // Deduplicate by salon ID
      final Map<String, dynamic> uniqueSalons = {};
      for (var s in allSalons) {
        if (s is Map<String, dynamic>) {
          final id = s['id']?.toString();
          if (id != null && id.isNotEmpty && !uniqueSalons.containsKey(id)) {
            uniqueSalons[id] = s;
          }
        }
      }

      var list = uniqueSalons.values.toList();
      // Only keep serviceable salons
      list = list.where((s) => s['is_serviceable'] != false).toList();

      // Recommendation ranking:
      // Prioritize well-rated nearby salons, then nearby salons, or top-rated if distance is absent
      list.sort((a, b) {
        final distA = (a['distance_km'] as num?)?.toDouble();
        final distB = (b['distance_km'] as num?)?.toDouble();
        final ratingA = (a['avg_rating'] as num?)?.toDouble() ?? 0.0;
        final ratingB = (b['avg_rating'] as num?)?.toDouble() ?? 0.0;

        if (distA != null && distB != null) {
          // If both have distance, well-rated salons (>= 4.0) within reasonable distance get top priority
          final isTopA = ratingA >= 4.0;
          final isTopB = ratingB >= 4.0;
          if (isTopA && !isTopB && distA <= distB * 1.5) return -1;
          if (!isTopA && isTopB && distB <= distA * 1.5) return 1;

          final distComp = distA.compareTo(distB);
          if (distComp != 0) return distComp;
          return ratingB.compareTo(ratingA);
        } else if (distA != null) {
          return -1;
        } else if (distB != null) {
          return 1;
        } else {
          return ratingB.compareTo(ratingA);
        }
      });

      setState(() {
        _recommendedSalons = list.take(10).toList();
        _isLoadingRecommended = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingRecommended = false;
      });
    }
  }

  /// Guests have no bookings or inbox, so this is a no-op for them.
  Future<void> _fetchAlerts() async {
    if (widget.isGuest) return;

    try {
      final bookings = await AppointmentService().getMyBookings();
      final notifications = await NotificationService().fetch();
      if (!mounted) return;
      setState(() {
        _needsReschedule = bookings['action_required'] ?? [];
        _upcoming = bookings['upcoming'] ?? [];
        _past = bookings['past'] ?? [];
        _unreadNotifications = notifications['unread_count'] ?? 0;
      });
    } catch (_) {
      // The home screen must still render if these fail.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificationsScreen()),
    );
    _fetchAlerts();
  }

  Future<void> _openReschedule(Map<String, dynamic> booking) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RescheduleScreen(
          appointmentId: booking['id'].toString(),
          freeReschedule: booking['free_reschedule'] == true,
        ),
      ),
    );
    _fetchAlerts();
  }

  Future<void> _openBookingDetails(Map<String, dynamic> booking) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AppointmentDetailsScreen(
          booking: booking,
          isUpcoming: true,
        ),
      ),
    );
    _fetchAlerts();
  }

  Future<void> _openCheckInQr(Map<String, dynamic> booking) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QrCodeScreen(
          appointmentId: booking['id'].toString(),
        ),
      ),
    );
    _fetchAlerts();
  }

  Future<void> _fetchBanners() async {
    // Scoped to the chosen city by BannerService, so a campaign aimed at one
    // city reaches it and nobody else.
    final banners = await BannerService().fetchBanners();
    if (!mounted) return;
    setState(() {
      _banners = banners;
      _isLoadingBanners = false;
    });
  }

  Future<void> _fetchCategories() async {
    final categoryService = CategoryService();
    final categories = await categoryService.fetchCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _isLoadingCategories = false;
    });
  }

  void _showFilterDialog() {
    String tempGender = _selectedGender;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: context.colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: context.colors.border, width: 1),
              ),
              title: Text('Filter Salons',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gender',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: context.colors.textSecondary)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: context.colors.accentSoft.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.colors.border, width: 1),
                    ),
                    padding: EdgeInsets.all(4),
                    child: Row(
                      children: ['All', 'Men', 'Women'].map((gender) {
                        final isSelected = tempGender == gender;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setStateDialog(() {
                                tempGender = gender;
                              });
                            },
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: 200),
                              padding: EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.accentColor
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  gender,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : context.colors.textSecondary,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setStateDialog(() {
                      tempGender = 'All';
                    });
                  },
                  child: Text('Reset',
                      style: TextStyle(color: context.colors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedGender = tempGender;
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding:
                        EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateToSearch({String? categoryId}) {
    // Picking a category, or browsing everything, still goes to the salon list
    // — those are filters over salons, not questions.
    if (categoryId != null || _searchController.text.trim().isEmpty) {
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SalonListScreen(
              initialSearch: _searchController.text,
              initialGender: _selectedGender,
              initialCategoryId: categoryId,
              title: categoryId != null ? 'Category Salons' : 'All Salons',
            ),
          ));
      return;
    }

    // A typed query is a question about services as much as salons, and the
    // salon list can only answer half of it.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(initialQuery: _searchController.text),
      ),
    );
  }

  /// Every category on its own page, reached from the View More card.
  void _openCategoriesPage() {
    AppHaptics.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoriesScreen()),
    );
  }

  /// Open the list of salons that offer this category in the customer's city.
  /// Combo needs no special case here — it carries the combo sentinel id and
  /// the directory resolves that to "salons with an active combo".
  void _openCategoryInExplore(ServiceCategory category) {
    AppHaptics.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CategorySalonsScreen(category: category)),
    );
  }

  // ---------------------------------------------------------------------------
  /// Everything the home tab shows, fetched again together.
  Future<void> _refreshAll() => Future.wait([
        _fetchBanners(),
        _fetchCategories(),
        _fetchAlerts(),
        _fetchRecommendedSalons(),
      ]);

  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      // Pull to refresh the whole page: offers, categories and the next
      // appointment all change while the app sits open.
      child: RefreshIndicator(
        color: AppTheme.accentColor,
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 15),

            // 1. Header
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _buildHeader()),

            // 2. Reschedule alerts
            ..._buildRescheduleAlerts().map((w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: w)),

            const SizedBox(height: 15),

            // 3. Search bar
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _buildSearchBar()),

            const SizedBox(height: 15),

            // 4. Banner carousel
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _buildBannerSection()),

            const SizedBox(height: 15),

            // 5. Categories
            _buildCategoriesSection(),

            // 6. Next appointment (only shown if there is an upcoming appointment)
            if (!widget.isGuest && _upcoming.isNotEmpty) ...[
              const SizedBox(height: 15),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _buildNextAppointmentSection()),
            ],

            if (!widget.isGuest && _deduplicatedBookAgainList.isNotEmpty) ...[
              const SizedBox(height: 15),
              // 7. Book again
              _buildBookAgainSection(),
            ],

            const SizedBox(height: 15),

            // 8. Recommended for You
            _buildRecommendedSection(),

            SizedBox(height: bottomClearance(context)), // clears the nav pill
          ],
        ),
      ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    final headingColor =
        context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          // Avatar: 50px round, purple border
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.accentColor,
                width: 1.5,
              ),
            ),
            child: CircleAvatar(
              radius: 23,
              backgroundColor: context.colors.accentSoft,
              child: Icon(Icons.person, color: AppTheme.accentColor, size: 28),
            ),
          ),
          const SizedBox(width: 10),
          // Greeting + Location
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isGuest ? 'Hi Guest 👋' : 'Welcome back 👋',
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: _pickCity,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 168),
                        child: Text(
                          LocationService.instance.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: headingColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down,
                          size: 14, color: AppTheme.accentColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Notification bell
          _buildNotificationBell(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATION BELL
  // ---------------------------------------------------------------------------
  Widget _buildNotificationBell() {
    final headingColor =
        context.colors.textPrimary;
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.border;

    return InkWell(
      onTap: widget.isGuest ? null : _openNotifications,
      customBorder: const CircleBorder(),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: surfaceColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentColor.withValues(alpha: 0.01),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(
                _unreadNotifications > 0
                    ? Icons.notifications
                    : Icons.notifications_none,
                color: headingColor.withValues(alpha: 0.75),
                size: 20,
              ),
            ),
            if (_unreadNotifications > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: context.colors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: surfaceColor, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RESCHEDULE ALERTS
  // ---------------------------------------------------------------------------
  List<Widget> _buildRescheduleAlerts() {
    if (_needsReschedule.isEmpty) return const [];

    return [
      const SizedBox(height: 10),
      ..._needsReschedule.map((raw) {
        final booking = raw as Map<String, dynamic>;
        final salonName = booking['salon']?['name'] ?? 'The salon';
        final advance =
            double.tryParse('${booking['advance_paid'] ?? 0}') ?? 0;
        final reason = booking['closure_reason'];
        final originalDate =
            DateTime.tryParse('${booking['appointment_date']}');

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.warningBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: context.colors.warning.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: context.colors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.event_busy,
                        size: 16, color: context.colors.warning),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Action needed: pick a new time',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.colors.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$salonName is closed'
                '${originalDate != null ? ' on ${DateFormat('EEE, d MMM').format(originalDate)}' : ''}'
                '${reason != null ? ' ($reason)' : ''}. '
                'Rebook free of charge — your ₹${advance.toStringAsFixed(0)} advance carries over.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _openReschedule(booking),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Reschedule free',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ],
          ),
        );
      }),
    ];
  }

  // ---------------------------------------------------------------------------
  // SEARCH BAR
  // ---------------------------------------------------------------------------
  Widget _buildSearchBar() {
    final surfaceColor = context.colors.surface;
    final bodyColor = context.colors.textSecondary;
    final headingColor =
        context.colors.textPrimary;

    return Row(
      children: [
        // Search field
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.only(left: 16, right: 16),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: context.colors.border, width: 1),
              boxShadow: [
                BoxShadow(
                  color: context.colors.dropShadow,
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded,
                    color: bodyColor.withValues(alpha: 0.7), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedSearchField(
                    controller: _searchController,
                    suggestions: const [
                      "haircut",
                      "hair spa",
                      "facial",
                      "manicure",
                      "pedicure",
                      "cleanup",
                      "bridal makeup",
                      "hair colour",
                      "waxing",
                      "combo"
                    ],
                    style: TextStyle(
                      color: headingColor,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search salons, services...',
                      hintStyle: TextStyle(
                        color: bodyColor.withValues(alpha: 0.5),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _navigateToSearch(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Gender filter button
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: _selectedGender != 'All'
                ? AppTheme.accentColor.withValues(alpha: 0.1)
                : surfaceColor,
            borderRadius: BorderRadius.circular(26),
            border: _selectedGender != 'All'
                ? Border.all(color: AppTheme.accentColor, width: 1.5)
                : Border.all(color: context.colors.border, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: context.colors.dropShadow,
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showFilterDialog,
              borderRadius: BorderRadius.circular(26),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      color: _selectedGender != 'All'
                          ? AppTheme.accentColor
                          : bodyColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _selectedGender != 'All' ? _selectedGender : 'Filter',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _selectedGender != 'All'
                            ? AppTheme.accentColor
                            : bodyColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BANNER SECTION
  // ---------------------------------------------------------------------------
  Widget _buildBannerSection() {
    if (_isLoadingBanners) {
      // The carousel's own footprint, so nothing below jumps when it lands.
      return const Skeleton(
        semanticLabel: 'Loading offers',
        child: SkeletonBox(height: 185, radius: 22),
      );
    }
    return BannerCarousel(banners: _banners);
  }

  // ---------------------------------------------------------------------------
  // CATEGORIES SECTION
  // ---------------------------------------------------------------------------
  Widget _buildCategoriesSection() {
    final headingColor =
        context.colors.textPrimary;
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.border;
    final bodyColor = context.colors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Categories',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: headingColor,
                ),
              ),
              // It opens the full category list, not the salon directory —
              // "browse all" of a list of categories means the categories.
              GestureDetector(
                onTap: _openCategoriesPage,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text(
                      'Browse all',
                      style: TextStyle(
                        color: AppTheme.accentColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: AppTheme.accentColor),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Category chips
        if (_isLoadingCategories)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Skeleton(
              semanticLabel: 'Loading categories',
              child: Row(
                children: [
                  Expanded(child: SkeletonBox(height: 58, radius: 16)),
                  SizedBox(width: 10),
                  Expanded(child: SkeletonBox(height: 58, radius: 16)),
                  SizedBox(width: 10),
                  Expanded(child: SkeletonBox(height: 58, radius: 16)),
                  SizedBox(width: 10),
                  Expanded(child: SkeletonBox(height: 58, radius: 16)),
                ],
              ),
            ),
          )
        else if (_categories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Text(
                  'No categories available yet.',
                  style: TextStyle(color: bodyColor.withValues(alpha: 0.7)),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CategoryGrid(
              categories: _categories,
              onTap: _openCategoryInExplore,
              onViewMore: _openCategoriesPage,
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // NEXT APPOINTMENT SECTION
  // ---------------------------------------------------------------------------
  Widget _buildNextAppointmentSection() {
    if (_upcoming.isEmpty || widget.isGuest) {
      return const SizedBox.shrink();
    }

    return _buildNextAppointmentCard(_upcoming.first);
  }

  Widget _buildNextAppointmentCard(Map<String, dynamic> booking) {
    final date = DateTime.tryParse(booking['appointment_date'] ?? '');
    final salonName = booking['salon']?['name'] ?? 'Salon';
    final address = booking['salon']?['address'] ?? '';
    final services = (booking['services'] as List?)
            ?.map((s) => s['name'])
            .join(', ') ??
        'Services';

    String statusLabel = 'YOUR NEXT APPOINTMENT';
    if (booking['status'] == 'in_progress') {
      statusLabel = 'IN PROGRESS';
    } else if (booking['status'] == 'completed') {
      statusLabel = 'DONE WITH TODAY\'S APPOINTMENT';
    }

    final bodyColor = context.colors.textSecondary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isDark
              ? [
                  const Color(0xFF3B2A56),
                  const Color(0xFF382650),
                  const Color(0xFF332047),
                ]
              : [
                  const Color(0xFFEBE1FA),
                  const Color(0xFFE8DBFA),
                  const Color(0xFFE1CEF8),
                ],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: context.colors.cardBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withValues(alpha: 0.02),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative glow in upper-right corner
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    context.colors.cardGlow,
                    context.colors.cardGlow.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          // Decorative background icons
          Positioned(
            right: -20,
            bottom: 30,
            child: Transform.rotate(
              angle: -0.5,
              child: Icon(
                Icons.content_cut,
                size: 160,
                color: AppTheme.accentColor.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            right: 80,
            bottom: 140,
            child: Icon(
              Icons.star_rounded,
              size: 40,
              color: AppTheme.accentColor.withValues(alpha: 0.08),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.accentColor.withValues(alpha: 0.15) : AppTheme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: isDark ? AppTheme.accentColor.withValues(alpha: 0.3) : AppTheme.accentColor.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month_rounded, size: 14, color: AppTheme.accentColor),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: const TextStyle(
                            color: AppTheme.accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Salon name and Time
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        salonName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF140D20),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.accentColor.withValues(alpha: 0.15) : AppTheme.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time, size: 14, color: AppTheme.accentColor),
                          const SizedBox(width: 6),
                          Text(
                            '${booking['start_time']} – ${booking['end_time']}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF140D20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Address
                if (address.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 14, color: bodyColor.withValues(alpha: 0.6)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          address,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: bodyColor.withValues(alpha: 0.8),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Services
                Row(
                  children: [
                    Icon(Icons.content_cut,
                        size: 14,
                        color: AppTheme.accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        services,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: bodyColor.withValues(alpha: 0.8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Divider
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: AppTheme.accentColor.withValues(alpha: 0.15),
                ),
                const SizedBox(height: 16),

                // Date
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.accentColor.withValues(alpha: 0.2) : AppTheme.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.accentColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        date != null
                            ? DateFormat('EEE, MMM d, yyyy').format(date)
                            : '',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF140D20),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // CTA: dark charcoal pill
                if (booking['id'] != null) ...[
                  if (CheckInWindow.notYetOpenLabel(booking) case final label?) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: bodyColor),
                        const SizedBox(width: 6),
                        Text(label,
                            style: TextStyle(fontSize: 12, color: bodyColor)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => CheckInWindow.canShowQr(booking)
                        ? _openCheckInQr(booking)
                        : _openBookingDetails(booking),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF3B2A56) : const Color(0xFF261D32),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CheckInWindow.canShowQr(booking)
                              ? Icons.qr_code
                              : Icons.map_outlined,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          CheckInWindow.canShowQr(booking)
                              ? 'Show Check-in QR'
                              : 'View details & Get direction',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right, size: 16),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOOK AGAIN SECTION
  // ---------------------------------------------------------------------------
  Widget _buildBookAgainSection() {
    final headingColor = context.colors.textPrimary;
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.border;
    final bodyColor = context.colors.textSecondary;
    final deduplicated = _deduplicatedBookAgainList;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Book Again',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: headingColor,
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => MyBookingsScreen()));
                },
                borderRadius: BorderRadius.circular(8),
                child: Text(
                  'See All',
                  style: TextStyle(
                    color: AppTheme.accentColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Book again content (deduplicated: each salon appears only once)
        if (deduplicated.isNotEmpty && !widget.isGuest)
          SizedBox(
            height: 200,
            child: ListView.builder(
              controller: _bookAgainScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 5, 20, 15),
              itemCount: deduplicated.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: _buildBookAgainCard(deduplicated[index]),
                );
              },
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Icon(Icons.history,
                    size: 32, color: bodyColor.withValues(alpha: 0.3)),
                const SizedBox(height: 10),
                Text(
                  widget.isGuest
                      ? 'Sign in to view your past bookings'
                      : 'You have no previous bookings to show here.',
                  style: TextStyle(
                      color: bodyColor.withValues(alpha: 0.6), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBookAgainCard(Map<String, dynamic> booking) {
    final salonName = booking['salon']?['name'] ?? 'Salon';
    final services = (booking['services'] as List?)
            ?.map((s) => s['name']?.toString())
            .where((name) => name != null && name.isNotEmpty)
            .join(', ') ??
        'Services';
    final salonId = (booking['salon_id'] ?? booking['salon']?['id'])?.toString();
    final distanceKm = booking['salon']?['distance_km'];
    final isApprox = booking['salon']?['distance_is_approximate'] == true;

    final headingColor = context.colors.textPrimary;
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.border;
    final bodyColor = context.colors.textSecondary;

    return GestureDetector(
      onTap: () {
        if (salonId != null && salonId.isNotEmpty) {
          AppHaptics.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SalonDetailScreen(
                salonId: salonId,
              ),
            ),
          );
        }
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: 250,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentColor.withValues(alpha: 0.02),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Wrapper
              SizedBox(
                height: 110,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(22),
                          topRight: Radius.circular(22)),
                      child: Image.network(
                        booking['salon']?['cover_photo_url'] ??
                            booking['salon']?['cover_image'] ??
                            booking['salon']?['logo_image'] ??
                            '',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: context.colors.accentSoft,
                          child: Icon(Icons.storefront_rounded,
                              color: AppTheme.accentColor.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                    // Real Distance Badge (rendered only when distance data is available)
                    if (FeatureFlags.showCalculatedDistance && distanceKm != null)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xB32A2320),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${isApprox ? '~' : ''}$distanceKm km',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Info Section
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            salonName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: headingColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Rebook',
                            style: TextStyle(
                              color: AppTheme.accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      services.isNotEmpty ? services : 'Services',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: bodyColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RECOMMENDED FOR YOU SECTION
  // ---------------------------------------------------------------------------
  Widget _buildRecommendedSection() {
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final currentCity = LocationService.instance.city?.name ?? 'your area';

    if (!_isLoadingRecommended && _recommendedSalons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommended for You',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: headingColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Top-rated & nearby salons in $currentCity',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: bodyColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  AppHaptics.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SalonListScreen(
                        title: 'Recommended for You',
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text(
                    'See All',
                    style: GoogleFonts.outfit(
                      color: AppTheme.accentColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Carousel / Horizontal list of recommended salons
        if (_isLoadingRecommended)
          SizedBox(
            height: 225,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: 3,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) => _buildRecommendedSkeletonCard(),
            ),
          )
        else
          SizedBox(
            height: 225,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _recommendedSalons.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final salon = _recommendedSalons[index] as Map<String, dynamic>;
                return _buildRecommendedCard(salon);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildRecommendedCard(Map<String, dynamic> salon) {
    final salonId = salon['id']?.toString() ?? '';
    final salonName = salon['name']?.toString() ?? 'Salon';
    final address = salon['address']?.toString() ?? '';
    final imageUrl = salon['cover_photo_url'] ??
        salon['cover_image'] ??
        salon['logo_image'] ??
        '';
    final avgRating = (salon['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = (salon['review_count'] as num?)?.toInt() ??
        (salon['rating_count'] as num?)?.toInt() ??
        0;
    final distanceKm = (salon['distance_km'] as num?)?.toDouble();
    final isApprox = salon['distance_is_approximate'] == true;
    final isTopRated = avgRating >= 4.5;

    final headingColor = context.colors.textPrimary;
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.border;
    final bodyColor = context.colors.textSecondary;

    return GestureDetector(
      onTap: () {
        if (salonId.isNotEmpty) {
          AppHaptics.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SalonDetailScreen(
                salonId: salonId,
              ),
            ),
          );
        }
      },
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentColor.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Stack
            SizedBox(
              height: 118,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: context.colors.accentSoft.withValues(alpha: 0.4),
                      child: Center(
                        child: Icon(
                          Icons.storefront_rounded,
                          color: AppTheme.accentColor.withValues(alpha: 0.5),
                          size: 34,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.25),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Top-rated pill badge
                  if (isTopRated)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome, size: 10, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              'TOP RATED',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Distance badge (only if real distance available)
                  if (FeatureFlags.showCalculatedDistance && distanceKm != null)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xCC18151D),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.near_me_rounded, size: 10, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              '${isApprox ? '~' : ''}${distanceKm.toStringAsFixed(1)} km',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info Content
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Salon name
                  Text(
                    salonName,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: headingColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  // Rating & Review count row
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB800)),
                      const SizedBox(width: 3),
                      Text(
                        avgRating > 0 ? avgRating.toStringAsFixed(1) : 'New',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: headingColor,
                        ),
                      ),
                      if (reviewCount > 0) ...[
                        const SizedBox(width: 3),
                        Text(
                          '($reviewCount)',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: bodyColor,
                          ),
                        ),
                      ],
                      const Spacer(),
                      // "Explore" link with accent arrow
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Explore',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentColor,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 10,
                            color: AppTheme.accentColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // Address row
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 13, color: bodyColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address.isNotEmpty ? address : 'Local Salon',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: bodyColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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

  Widget _buildRecommendedSkeletonCard() {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 118,
            width: double.infinity,
            color: context.colors.accentSoft.withValues(alpha: 0.3),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 140,
                  decoration: BoxDecoration(
                    color: context.colors.accentSoft.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 90,
                  decoration: BoxDecoration(
                    color: context.colors.accentSoft.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 160,
                  decoration: BoxDecoration(
                    color: context.colors.accentSoft.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}