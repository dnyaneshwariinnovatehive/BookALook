import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/banner.dart';
import '../../services/banner_service.dart';
import '../../widgets/banner_carousel.dart';
import '../../models/category.dart';
import '../../services/category_service.dart';
import '../../services/appointment_service.dart';
import '../../services/notification_service.dart';
import '../notifications_screen.dart';
import '../reschedule_screen.dart';

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
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _fetchBanners();
    _fetchCategories();
    _fetchAlerts();
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

  Future<void> _fetchBanners() async {
    final bannerService = BannerService();
    // Assuming we want to fetch banners for the user's current city if known.
    // For now, we fetch platform-wide banners (and city banners if city is passed).
    final banners = await bannerService.fetchBanners();
    setState(() {
      _banners = banners;
      _isLoadingBanners = false;
    });
  }

  Future<void> _fetchCategories() async {
    final categoryService = CategoryService();
    final categories = await categoryService.fetchCategories();
    setState(() {
      _categories = categories;
      _isLoadingCategories = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isGuest ? 'Hi Guest 👋' : 'Welcome back 👋',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            'Select Location',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down, size: 20, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildNotificationBell(context),
              ],
            ),
            SizedBox(height: 24),

            // Anything the salon has forced on the customer comes first.
            ..._buildRescheduleAlerts(context),

            // Search Bar
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                        SizedBox(width: 8),
                        Text(
                          'Search salons, services...',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Icon(Icons.filter_list, color: Theme.of(context).colorScheme.onSurface),
                ),
              ],
            ),
            SizedBox(height: 24),

            // Banners Carousel
            if (_isLoadingBanners)
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              BannerCarousel(banners: _banners),
              
            SizedBox(height: 32),

            // Categories Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Categories',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                ),
                Text(
                  'See All',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (_isLoadingCategories)
              Container(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_categories.isEmpty)
              Container(
                padding: EdgeInsets.all(24),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).shadowColor,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'No categories available yet.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ),
              )
            else
              SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    return Container(
                      margin: EdgeInsets.only(right: 12),
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Theme.of(context).dividerColor),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).shadowColor,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (category.iconUrl != null && category.iconUrl!.isNotEmpty)
                            Image.network(category.iconUrl!, width: 20, height: 20, errorBuilder: (c,e,s) => Icon(Icons.category, size: 20, color: Theme.of(context).colorScheme.primary))
                          else
                            Icon(Icons.category, color: Theme.of(context).colorScheme.primary, size: 20),
                          SizedBox(width: 8),
                          Text(
                            category.name,
                            style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            SizedBox(height: 32),

            // Next Appointment Placeholder
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1).withOpacity(0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      'YOUR NEXT APPOINTMENT',
                      style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Text(
                        widget.isGuest ? 'Sign in to see your appointments' : 'No upcoming appointments',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),

            // Book Again Placeholder
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Book Again',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                ),
                Text(
                  'See All',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(24),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).shadowColor,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.isGuest ? 'Sign in to view your past bookings' : 'You have no previous bookings to show here.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            SizedBox(height: 40), // Bottom padding
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    return InkWell(
      onTap: widget.isGuest ? null : _openNotifications,
      customBorder: const CircleBorder(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Icon(
              _unreadNotifications > 0 ? Icons.notifications : Icons.notifications_none,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (_unreadNotifications > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: AppTheme.lightDanger,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
                ),
                child: Text(
                  _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One card per booking the salon released. Deliberately loud and at the very
  /// top: the customer has money tied up in it and only they can resolve it.
  List<Widget> _buildRescheduleAlerts(BuildContext context) {
    if (_needsReschedule.isEmpty) return const [];

    return [
      ..._needsReschedule.map((raw) {
        final booking = raw as Map<String, dynamic>;
        final salonName = booking['salon']?['name'] ?? 'The salon';
        final advance = double.tryParse('${booking['advance_paid'] ?? 0}') ?? 0;
        final reason = booking['closure_reason'];
        final originalDate = DateTime.tryParse('${booking['appointment_date']}');

        return Container(
          margin: EdgeInsets.only(bottom: 16),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.lightWarningBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.lightWarning.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_busy, size: 18, color: AppTheme.lightWarning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Action needed: pick a new time',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.lightWarning,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                '$salonName is closed'
                '${originalDate != null ? ' on ${DateFormat('EEE, d MMM').format(originalDate)}' : ''}'
                '${reason != null ? ' ($reason)' : ''}. '
                'Rebook free of charge — your ₹${advance.toStringAsFixed(0)} advance carries over.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _openReschedule(booking),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Reschedule free',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      }),
    ];
  }
}
