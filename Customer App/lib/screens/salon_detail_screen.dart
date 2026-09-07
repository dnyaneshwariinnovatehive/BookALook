import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/salon_service.dart';
import '../services/cart_service.dart';
import 'cart_screen.dart';

class SalonDetailScreen extends StatefulWidget {
  final String salonId;
  const SalonDetailScreen({Key? key, required this.salonId}) : super(key: key);

  @override
  State<SalonDetailScreen> createState() => _SalonDetailScreenState();
}

class _SalonDetailScreenState extends State<SalonDetailScreen> {
  final SalonService _salonService = SalonService();
  final CartService _cartService = CartService();
  final PageController _galleryController = PageController();

  Map<String, dynamic>? _salon;
  Map<String, dynamic>? _cart;
  bool _isLoading = true;
  String _error = '';

  /// null = the "All Services" tab.
  String? _selectedCategoryId;
  int _galleryPage = 0;
  bool _hoursExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadSalonDetails();
    _loadCart();
  }

  @override
  void dispose() {
    _galleryController.dispose();
    super.dispose();
  }

  Future<void> _loadSalonDetails() async {
    setState(() => _error = '');
    try {
      final data = await _salonService.fetchSalonDetails(widget.salonId);
      if (!mounted) return;
      setState(() {
        _salon = data;
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

  /// Keeps the sticky bottom bar's running total in sync.
  Future<void> _loadCart() async {
    try {
      final cart = await _cartService.getGlobalCart();
      if (!mounted) return;
      setState(() => _cart = cart);
    } catch (_) {
      // A failed cart read should never block the salon page.
    }
  }

  Future<void> _addToCart({String? serviceId, String? comboId, required String label}) async {
    try {
      if (serviceId != null) {
        await _cartService.addItem(widget.salonId, serviceId);
      } else {
        await _cartService.addCombo(widget.salonId, comboId!);
      }
      _showMessage('$label added to cart');
      _loadCart();
    } on CartConflictException catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Replace cart items?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: Text(
            'Your cart contains items from ${e.otherSalonName}. Do you want to discard that selection and add items from this salon?',
            style: GoogleFonts.outfit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.outfit(color: AppTheme.lightTextBody)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _cartService.clearGlobalCart();
                _addToCart(serviceId: serviceId, comboId: comboId, label: label);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
              child: Text('Replace', style: GoogleFonts.outfit(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openCart() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => CartScreen()));
    _loadCart();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: Duration(seconds: 2)),
    );
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  bool get _isBookable => _salon?['is_bookable'] == true;

  List<dynamic> get _visibleServices {
    final services = (_salon?['services'] as List?) ?? [];
    if (_selectedCategoryId == null) return services;
    return services.where((s) => s['category_id'] == _selectedCategoryId).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.accentColor)));
    }

    if (_error.isNotEmpty || _salon == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_outlined, size: 64, color: AppTheme.lightTextLight),
                SizedBox(height: 12),
                Text(_error.isNotEmpty ? _error : 'Salon not found',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(fontSize: 16, color: AppTheme.lightTextBody)),
                SizedBox(height: 16),
                ElevatedButton(onPressed: _loadSalonDetails, child: Text('Try again')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBg,
      body: RefreshIndicator(
        color: AppTheme.accentColor,
        onRefresh: () async {
          await _loadSalonDetails();
          await _loadCart();
        },
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(child: _buildHeaderCard()),
            SliverToBoxAdapter(child: _buildNotices()),
            SliverToBoxAdapter(child: _buildHoursPanel()),
            SliverToBoxAdapter(child: _buildCombos()),
            SliverToBoxAdapter(child: _buildCategoryTabs()),
            _buildServiceSliver(),
            SliverToBoxAdapter(child: _buildTeam()),
            SliverToBoxAdapter(child: _buildReviews()),
            SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
      bottomNavigationBar: _buildStickyBar(),
    );
  }

  // ---------------------------------------------------------------- app bar

  Widget _buildAppBar() {
    final gallery = (_salon!['gallery'] as List?) ?? [];

    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      backgroundColor: AppTheme.accentColor,
      foregroundColor: Colors.white,
      title: Text(_salon!['name'] ?? 'Salon',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
      actions: [
        IconButton(icon: Icon(Icons.shopping_bag_outlined), onPressed: _openCart),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (gallery.isEmpty)
              _galleryPlaceholder()
            else
              PageView.builder(
                controller: _galleryController,
                itemCount: gallery.length,
                onPageChanged: (i) => setState(() => _galleryPage = i),
                itemBuilder: (context, index) => Image.network(
                  gallery[index]['url'] ?? '',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _galleryPlaceholder(),
                ),
              ),

            // Scrim so the chips and the pinned title stay readable.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.45),
                    Colors.transparent,
                    Colors.black.withOpacity(0.55),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),

            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _glassChip(_salon!['gender_focus'] ?? 'Unisex'),
                  _buildRatingPill(),
                ],
              ),
            ),

            if (gallery.length > 1)
              Positioned(
                bottom: 6,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    gallery.length,
                    (i) => AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      margin: EdgeInsets.symmetric(horizontal: 3),
                      width: _galleryPage == i ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(_galleryPage == i ? 1 : 0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _galleryPlaceholder() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.accentGradientLightEnd, AppTheme.accentGradientEnd],
          ),
        ),
        child: Center(child: Icon(Icons.storefront, size: 90, color: Colors.white.withOpacity(0.45))),
      );

  Widget _glassChip(String text) => Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _buildRatingPill() {
    final rating = _salon!['rating'] ?? {};
    final count = (rating['count'] ?? 0) as int;
    final average = _toDouble(rating['average']);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: count > 0 ? AppTheme.lightSuccess : Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: Colors.white, size: 15),
          SizedBox(width: 4),
          Text(
            count > 0 ? '${average.toStringAsFixed(1)} ($count)' : 'New',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- header

  Widget _buildHeaderCard() {
    final isOpen = _salon!['is_open_now'] == true;
    final address = [_salon!['address'], _salon!['city'], _salon!['pincode']]
        .where((part) => part != null && '$part'.isNotEmpty)
        .join(', ');

    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_salon!['name'] ?? 'Salon',
              style: GoogleFonts.outfit(
                  fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
          SizedBox(height: 10),

          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOpen ? AppTheme.lightSuccess : AppTheme.lightDanger,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  _salon!['open_status_label'] ?? '',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isOpen ? AppTheme.lightSuccess : AppTheme.lightDanger,
                  ),
                ),
              ),
            ],
          ),

          if (address.isNotEmpty) ...[
            SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined, size: 18, color: AppTheme.lightTextBody),
                SizedBox(width: 8),
                Expanded(
                  child: Text(address,
                      style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
                ),
              ],
            ),
          ],

          if (_salon!['phone'] != null) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 18, color: AppTheme.lightTextBody),
                SizedBox(width: 8),
                Text(_salon!['phone'],
                    style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
              ],
            ),
          ],

          if ((_salon!['description'] ?? '').toString().isNotEmpty) ...[
            SizedBox(height: 14),
            Text(_salon!['description'],
                style: GoogleFonts.outfit(fontSize: 14, height: 1.5, color: AppTheme.lightTextBody)),
          ],

          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _statTile(
                Icons.spa_outlined,
                '${(_salon!['services'] as List?)?.length ?? 0}',
                'Services',
              )),
              Expanded(child: _statTile(
                Icons.people_outline,
                '${(_salon!['team'] as List?)?.length ?? 0}',
                'Staff',
              )),
              Expanded(child: _statTile(
                Icons.percent,
                '${_toDouble(_salon!['advance_percentage_default']).toStringAsFixed(0)}%',
                'Advance',
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label) => Column(
        children: [
          Icon(icon, size: 20, color: AppTheme.accentColor),
          SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.outfit(
                  fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
          Text(label, style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextLight)),
        ],
      );

  // ---------------------------------------------------------------- notices

  Widget _buildNotices() {
    final closures = (_salon!['upcoming_closures'] as List?) ?? [];

    return Column(
      children: [
        if (!_isBookable)
          _noticeBox(
            icon: Icons.event_busy,
            color: AppTheme.lightDanger,
            background: AppTheme.lightDangerBg,
            title: 'Temporarily unavailable',
            body: _salon!['unavailable_reason'] ??
                'This salon is not accepting online bookings right now.',
          ),
        if (closures.isNotEmpty)
          _noticeBox(
            icon: Icons.info_outline,
            color: AppTheme.lightWarning,
            background: AppTheme.lightWarningBg,
            title: 'Closed on ${closures.map((c) => c['label']).join(', ')}',
            body: 'Pick another date for these days when you book.',
          ),
      ],
    );
  }

  Widget _noticeBox({
    required IconData icon,
    required Color color,
    required Color background,
    required String title,
    required String body,
  }) =>
      Container(
        width: double.infinity,
        margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.outfit(
                          fontSize: 14, fontWeight: FontWeight.bold, color: color)),
                  SizedBox(height: 2),
                  Text(body, style: GoogleFonts.outfit(fontSize: 13, color: color)),
                ],
              ),
            ),
          ],
        ),
      );

  // ------------------------------------------------------------------ hours

  Widget _buildHoursPanel() {
    final week = (_salon!['working_hours'] as List?) ?? [];
    if (week.isEmpty) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: _cardDecoration(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _hoursExpanded,
          onExpansionChanged: (v) => setState(() => _hoursExpanded = v),
          tilePadding: EdgeInsets.symmetric(horizontal: 20),
          childrenPadding: EdgeInsets.fromLTRB(20, 0, 20, 16),
          leading: Icon(Icons.schedule, color: AppTheme.accentColor),
          title: Text('Opening hours',
              style: GoogleFonts.outfit(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.lightTextHeading)),
          children: week.map<Widget>((day) {
            final isToday = day['is_today'] == true;
            final closed = day['is_closed'] == true;

            return Padding(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(day['day_name'],
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday ? AppTheme.accentColor : AppTheme.lightTextBody,
                      )),
                  Text(
                    closed ? 'Closed' : '${day['open_time']} – ${day['close_time']}',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: closed
                          ? AppTheme.lightTextLight
                          : (isToday ? AppTheme.accentColor : AppTheme.lightTextHeading),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- combos

  Widget _buildCombos() {
    final combos = (_salon!['combos'] as List?) ?? [];
    if (combos.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Value packages', 'Bundled services at a lower price'),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: combos.length,
            separatorBuilder: (_, __) => SizedBox(width: 12),
            itemBuilder: (context, index) => _comboCard(combos[index]),
          ),
        ),
      ],
    );
  }

  Widget _comboCard(Map<String, dynamic> combo) {
    final savings = _toDouble(combo['savings']);
    final lines = (combo['services'] as List?) ?? [];

    return Container(
      width: 270,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.lightAccentSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.lightAccentSoftHover),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(combo['name'] ?? 'Package',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
              ),
              if (savings > 0)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.lightSuccess,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('SAVE ₹${savings.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
            ],
          ),
          SizedBox(height: 6),
          Text('${combo['duration_minutes']} mins · ${lines.length} services',
              style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
          SizedBox(height: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines
                  .take(3)
                  .map<Widget>((line) => Padding(
                        padding: EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, size: 13, color: AppTheme.accentColor),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(line['name'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                      fontSize: 12, color: AppTheme.lightTextBody)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (savings > 0)
                    Text('₹${_toDouble(combo['original_price']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppTheme.lightTextLight,
                          decoration: TextDecoration.lineThrough,
                        )),
                  Text('₹${_toDouble(combo['price']).toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                ],
              ),
              _addButton(
                enabled: _isBookable,
                onTap: () => _addToCart(comboId: combo['id'].toString(), label: combo['name'] ?? 'Package'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- categories

  Widget _buildCategoryTabs() {
    final categories = (_salon!['categories'] as List?) ?? [];
    final allCount = (_salon!['services'] as List?)?.length ?? 0;

    if (allCount == 0) return _sectionHeader('Services', 'Nothing published yet');

    final tabs = <Map<String, dynamic>>[
      {'id': null, 'name': 'All Services', 'service_count': allCount},
      ...categories.cast<Map<String, dynamic>>(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Services', 'Tap add to build your booking'),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: tabs.length,
            separatorBuilder: (_, __) => SizedBox(width: 8),
            itemBuilder: (context, index) {
              final tab = tabs[index];
              final isSelected = _selectedCategoryId == tab['id'];

              return GestureDetector(
                onTap: () => setState(() => _selectedCategoryId = tab['id'] as String?),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text(
                        '${tab['name']} (${tab['service_count']})',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? AppTheme.accentColor : AppTheme.lightTextBody,
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: Duration(milliseconds: 180),
                      height: 3,
                      width: isSelected ? 28 : 0,
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(height: 8),
      ],
    );
  }

  // ---------------------------------------------------------------- services

  Widget _buildServiceSliver() {
    final services = _visibleServices;

    if (services.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: Text('No services in this category.',
                style: GoogleFonts.outfit(color: AppTheme.lightTextLight)),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _serviceCard(services[index]),
        ),
        childCount: services.length,
      ),
    );
  }

  Widget _serviceCard(Map<String, dynamic> service) {
    // No trained staff means checkout would dead-end, so the card says so.
    final hasStaff = (service['provider_count'] ?? 0) > 0;
    final canAdd = _isBookable && hasStaff;
    final description = (service['description'] ?? '').toString();

    return Opacity(
      opacity: canAdd ? 1.0 : 0.6,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.lightAccentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.spa_outlined, color: AppTheme.accentColor),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service['name'] ?? 'Service',
                          style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.lightTextHeading)),
                      SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _metaChip(Icons.access_time, '${service['duration_minutes']} mins'),
                          if (service['gender_focus'] != null &&
                              service['gender_focus'] != 'Unisex')
                            _metaChip(Icons.person_outline, service['gender_focus']),
                          if (service['refundable_advance'] == true)
                            _metaChip(Icons.replay, 'Refundable advance'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (description.isNotEmpty) ...[
              SizedBox(height: 12),
              Text(description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      fontSize: 13, height: 1.4, color: AppTheme.lightTextBody)),
            ],

            if (!hasStaff) ...[
              SizedBox(height: 10),
              Text('No staff available for this service right now',
                  style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightDanger)),
            ],

            SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹${_toDouble(service['price']).toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                        fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                _addButton(
                  enabled: canAdd,
                  onTap: () => _addToCart(
                    serviceId: service['id'].toString(),
                    label: service['name'] ?? 'Service',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.lightBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.lightTextBody),
            SizedBox(width: 4),
            Text(text, style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.lightTextBody)),
          ],
        ),
      );

  Widget _addButton({required bool enabled, required VoidCallback onTap}) => ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(Icons.add, size: 16),
        label: Text('ADD', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.lightBorder,
          disabledForegroundColor: AppTheme.lightTextLight,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  // -------------------------------------------------------------------- team

  Widget _buildTeam() {
    final team = (_salon!['team'] as List?) ?? [];
    if (team.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Meet the team', 'Choose your stylist at checkout'),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: team.length,
            separatorBuilder: (_, __) => SizedBox(width: 12),
            itemBuilder: (context, index) {
              final member = team[index];
              final name = (member['name'] ?? 'Staff').toString();

              return Container(
                width: 108,
                padding: EdgeInsets.all(12),
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppTheme.lightAccentSoft,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: GoogleFonts.outfit(
                            fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.lightTextHeading)),
                    SizedBox(height: 2),
                    Text(
                      member['specialization'] ?? '${member['service_count']} services',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(fontSize: 11, color: AppTheme.lightTextLight),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- reviews

  Widget _buildReviews() {
    final rating = _salon!['rating'] ?? {};
    final count = (rating['count'] ?? 0) as int;
    final average = _toDouble(rating['average']);
    final recent = (rating['recent'] as List?) ?? [];
    final breakdown = (rating['breakdown'] as Map?) ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Ratings & reviews', count > 0 ? '$count customer ratings' : null),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 16),
          padding: EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: count == 0
              ? Row(
                  children: [
                    Icon(Icons.rate_review_outlined, color: AppTheme.lightTextLight),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('No reviews yet — be the first to rate this salon.',
                          style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Text(average.toStringAsFixed(1),
                                style: GoogleFonts.outfit(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.lightTextHeading)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                5,
                                (i) => Icon(
                                  i < average.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                                  size: 14,
                                  color: AppTheme.lightWarning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            children: [5, 4, 3, 2, 1].map<Widget>((star) {
                              final starCount = (breakdown['$star'] ?? breakdown[star] ?? 0) as int;
                              return Padding(
                                padding: EdgeInsets.symmetric(vertical: 1.5),
                                child: Row(
                                  children: [
                                    Text('$star',
                                        style: GoogleFonts.outfit(
                                            fontSize: 11, color: AppTheme.lightTextLight)),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: LinearProgressIndicator(
                                          value: count > 0 ? starCount / count : 0,
                                          minHeight: 5,
                                          backgroundColor: AppTheme.lightBorder,
                                          valueColor:
                                              AlwaysStoppedAnimation(AppTheme.lightWarning),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    if (recent.isNotEmpty) ...[
                      SizedBox(height: 16),
                      Divider(color: AppTheme.lightBorder, height: 1),
                      SizedBox(height: 12),
                      ...recent.map<Widget>((review) => Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(review['customer_name'] ?? 'Customer',
                                        style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.lightTextHeading)),
                                    SizedBox(width: 8),
                                    Icon(Icons.star_rounded, size: 13, color: AppTheme.lightWarning),
                                    Text('${review['rating']}',
                                        style: GoogleFonts.outfit(
                                            fontSize: 12, color: AppTheme.lightTextBody)),
                                  ],
                                ),
                                SizedBox(height: 2),
                                Text(review['comment'] ?? '',
                                    style: GoogleFonts.outfit(
                                        fontSize: 13, color: AppTheme.lightTextBody)),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- sticky bar

  /// Price of one cart line. A combo is priced from its own special prices,
  /// not from the member services' list prices.
  double _lineTotal(dynamic item) {
    final quantity = (item['quantity'] ?? 1) as int;

    if (item['combo'] != null) {
      double comboPrice = 0;
      for (final service in (item['combo']['services'] as List? ?? [])) {
        comboPrice += _toDouble(service['pivot']?['combo_special_price'] ?? service['price']);
      }
      return comboPrice * quantity;
    }

    if (item['service'] != null) {
      return _toDouble(item['service']['price']) * quantity;
    }

    return 0;
  }

  /// Running total for the doc's sticky "View Cart" bar. Only counts a cart
  /// that belongs to this salon.
  Widget? _buildStickyBar() {
    final items = (_cart?['items'] as List?) ?? [];
    if (_cart == null || items.isEmpty) return null;
    if (_cart!['salon_id'].toString() != widget.salonId) return null;

    // The server sends the figures the booking will actually charge; only fall
    // back to a local sum if an older API build leaves them out.
    final summary = _cart!['summary'] as Map<String, dynamic>?;

    double total = 0;
    int count = 0;
    for (final item in items) {
      count += (item['quantity'] ?? 1) as int;
      total += _lineTotal(item);
    }

    if (summary != null) {
      total = _toDouble(summary['total_amount']);
      count = (summary['item_count'] ?? count) as int;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: AppTheme.lightSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), offset: Offset(0, -4), blurRadius: 16),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count ${count == 1 ? 'item' : 'items'}',
                    style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.lightTextBody)),
                Text('₹${total.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.lightTextHeading)),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _openCart,
              icon: Icon(Icons.shopping_cart, size: 18),
              label: Text('View Cart',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ shared

  Widget _sectionHeader(String title, String? subtitle) => Padding(
        padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.outfit(
                    fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
            if (subtitle != null) ...[
              SizedBox(height: 2),
              Text(subtitle,
                  style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.lightTextLight)),
            ],
          ],
        ),
      );

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.lightBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: Offset(0, 4)),
        ],
      );
}
