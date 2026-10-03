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

  String _selectedGender = 'All';
  final TextEditingController _searchController = TextEditingController();

  ScrollController? _bookAgainScrollController;
  Timer? _bookAgainTimer;

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
      if (!mounted || _past.isEmpty || _bookAgainScrollController == null) return;
      if (!_bookAgainScrollController!.hasClients) return;
      
      final currentOffset = _bookAgainScrollController!.offset;
      final stride = 250.0 + 14.0; // card width + gap
      final targetOffset = ((currentOffset / stride).floor() + 1) * stride;

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
  }

  void _onCityChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Let the customer change market, and reload what that changes.
  Future<void> _pickCity() async {
    final changed = await showCityPicker(context);

    if (changed && mounted) {
      setState(() => _isLoadingBanners = true);
      _fetchBanners();
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
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
                  SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: context.colors.accentSoft.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
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
      ]);

  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return SafeArea(
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

            const SizedBox(height: 15),

            // 6. Next appointment
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _buildNextAppointmentSection()),

            if (!widget.isGuest) ...[
              const SizedBox(height: 15),
              // 7. Book again
              _buildBookAgainSection(),
            ],

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
                  child: TextField(
                    controller: _searchController,
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
                : Border.all(color: Colors.transparent, width: 1.5),
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
        const SizedBox(height: 12),
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
    // isDark picks the hero card's own decorative palette (gradient stops,
    // accent tints, the muted label). Those are a one-off illustration, not
    // theme roles; the shared shadow and glow come from the theme tokens.
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_upcoming.isNotEmpty && !widget.isGuest) {
      return _buildNextAppointmentCard(_upcoming.first);
    }

    // Empty state
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
                const Color(0xFFEDE4FF),
                const Color(0xFFE9DDFD),
                const Color(0xFFE3D3FB),
              ],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : AppTheme.accentColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
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
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      Icon(Icons.calendar_month_rounded, size: 12, color: AppTheme.accentColor),
                      const SizedBox(width: 6),
                      const Text(
                        'YOUR NEXT APPOINTMENT',
                        style: TextStyle(
                            color: AppTheme.accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 40,
                            color: isDark ? AppTheme.accentColor.withValues(alpha: 0.4) : AppTheme.accentColor.withValues(alpha: 0.25)),
                        const SizedBox(height: 12),
                        Text(
                          widget.isGuest
                              ? 'Sign in to see your appointments'
                              : 'No upcoming appointments ? Book Now',
                          style: TextStyle(
                              color: isDark ? Colors.white70 : const Color(0xFF756A8F),
                              fontWeight: FontWeight.w600,
                              fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextAppointmentCard(Map<String, dynamic> booking) {
    final date = DateTime.tryParse(booking['appointment_date'] ?? '');
    final salonName = booking['salon']?['name'] ?? 'Salon';
    final address = booking['salon']?['address'] ?? '';
    final services = (booking['services'] as List?)
            ?.map((s) => s['name'])
            .join(', ') ??
        'Services';

    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFEBE1FA),
            Color(0xFFE8DBFA),
            Color(0xFFE1CEF8),
          ],
          stops: [0.0, 0.5, 1.0],
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
                      Icon(Icons.calendar_month_rounded, size: 12, color: AppTheme.accentColor),
                      const SizedBox(width: 6),
                      const Text(
                        'YOUR NEXT APPOINTMENT',
                        style: TextStyle(
                            color: AppTheme.accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Salon name
                Text(
                  salonName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: headingColor,
                  ),
                ),

                // Address
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: bodyColor.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          style: TextStyle(
                            fontSize: 13,
                            color: bodyColor.withValues(alpha: 0.75),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                // Services
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(Icons.content_cut,
                        size: 14,
                        color: AppTheme.accentColor.withValues(alpha: 0.75)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        services,
                        style: TextStyle(
                          fontSize: 13,
                          color: bodyColor.withValues(alpha: 0.8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Divider
                const SizedBox(height: 14),
                _DashedDivider(),
                const SizedBox(height: 14),

                // Date & time
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 15, color: AppTheme.accentColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        date != null
                            ? DateFormat('EEE, MMM d, yyyy').format(date)
                            : '',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: headingColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.access_time,
                        size: 15, color: AppTheme.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      '${booking['start_time']} – ${booking['end_time']}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: headingColor,
                      ),
                    ),
                  ],
                ),

                // CTA: dark charcoal pill. The check-in QR once its window is
                // open; until then the booking's details, with a note of when
                // the QR becomes available.
                if (booking['id'] != null) ...[
                  if (CheckInWindow.notYetOpenLabel(booking) case final label?) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: bodyColor),
                        const SizedBox(width: 6),
                        Text(label,
                            style: TextStyle(fontSize: 12, color: bodyColor)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: () => CheckInWindow.canShowQr(booking)
                        ? _openCheckInQr(booking)
                        : _openBookingDetails(booking),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.darkButtonBg,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            CheckInWindow.canShowQr(booking)
                                ? 'Show Check-in QR'
                                : 'View Details & Get Directions',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
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

        // Book again content
        if (_past.isNotEmpty && !widget.isGuest)
          SizedBox(
            height: 200,
            child: ListView.builder(
              controller: _bookAgainScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 5, 20, 15),
              // Omit itemCount for infinite loop
              itemBuilder: (context, index) {
                final realIndex = index % _past.length;
                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: _buildBookAgainCard(_past[realIndex]),
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
            ?.map((s) => s['name'])
            .join(', ') ??
        'Services';
    final salonId = booking['salon_id'];

    final headingColor =
        context.colors.textPrimary;
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.border;
    final bodyColor = context.colors.textSecondary;

    return GestureDetector(
      onTap: () {
        if (salonId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SalonDetailScreen(
                salonId: salonId.toString(),
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
                    booking['salon']?['cover_image'] ??
                        booking['salon']?['cover_photo_url'] ??
                        'https://via.placeholder.com/250x110',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: context.colors.accentSoft,
                      child: Icon(Icons.image,
                          color: AppTheme.accentColor.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
                // Distance Badge Placeholder
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xB32A2320), // rgba(42, 35, 32, 0.7)
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '2.5 km',
                      style: TextStyle(
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
                  services,
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
}

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFBDBDBD)),
              ),
            );
          }),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
        );
      },
    );
  }
}