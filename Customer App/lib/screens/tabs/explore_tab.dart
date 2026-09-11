import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/salon_service.dart';
import '../salon_detail_screen.dart';
import '../../services/cart_service.dart';
import '../../services/location_service.dart';
import '../../widgets/city_picker_sheet.dart';
import '../cart_screen.dart';

class ExploreTab extends StatefulWidget {
  @override
  _ExploreTabState createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  final SalonService _salonService = SalonService();
  List<dynamic> _salons = [];
  bool _isLoading = true;
  String _error = '';

  final CartService _cartService = CartService();
  Map<String, dynamic>? _globalCart;

  /// When this city has nothing in it, the directory hands back somewhere that
  /// does, rather than leaving the customer on an empty screen.
  List<dynamic> _suggested = [];
  Map<String, dynamic>? _suggestedCity;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    LocationService.instance.addListener(_onCityChanged);
  }

  @override
  void dispose() {
    LocationService.instance.removeListener(_onCityChanged);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await LocationService.instance.restore();
    await _loadSalons();
  }

  void _onCityChanged() {
    if (!mounted) return;
    setState(() => _isLoading = true);
    _loadSalons();
  }

  Future<void> _pickCity() async => showCityPicker(context);

  Future<void> _loadSalons() async {
    try {
      final response = await _salonService.fetchSalons();
      final salons = response['salons'] ?? [];
      final globalCart = await _cartService.getGlobalCart();
      if (!mounted) return;
      setState(() {
        _salons = salons;
        _suggested = response['suggested_salons'] ?? [];
        _suggestedCity = response['suggested_city'] as Map<String, dynamic>?;
        _globalCart = globalCart;
        _isLoading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.accentColor));
    }
    if (_error.isNotEmpty) {
      return Center(child: Text(_error, style: GoogleFonts.outfit(color: AppTheme.lightDanger)));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Explore Salons', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
                ),
                // Changing city is the single most useful control on an empty
                // list, so it is always within reach rather than only on Home.
                TextButton.icon(
                  onPressed: _pickCity,
                  icon: Icon(Icons.location_on, size: 16, color: AppTheme.accentColor),
                  label: Text(
                    LocationService.instance.label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppTheme.accentColor),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _salons.isEmpty
                ? _buildEmptyCity()
                : ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    itemCount: _salons.length,
                    separatorBuilder: (context, index) => SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final salon = _salons[index];
                      // A salon whose plan has lapsed stays findable — a
                      // returning customer should not think it has vanished —
                      // but it is plainly marked as not taking bookings.
                      final isServiceable = salon['is_serviceable'] != false;

                      return InkWell(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (context) => SalonDetailScreen(salonId: salon['id'].toString())
                          ));
                        },
                        child: Opacity(
                          opacity: isServiceable ? 1.0 : 0.6,
                          child: Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.lightSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.lightBorder),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 4))
                            ]
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: AppTheme.lightAccentSoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.storefront, color: AppTheme.accentColor, size: 40),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(salon['name'] ?? 'Unnamed Salon', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
                                    SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.location_on, size: 14, color: AppTheme.lightTextBody),
                                        SizedBox(width: 4),
                                        Expanded(child: Text(salon['address'] ?? 'No address provided', maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 13))),
                                      ],
                                    ),
                                    if (salon['distance_km'] != null) ...[
                                      SizedBox(height: 4),
                                      Text(
                                        // "about" when the salon sits on its
                                        // city centre rather than its own pin —
                                        // a guess should not read as a measurement.
                                        '${salon['distance_is_approximate'] == true ? 'about ' : ''}${salon['distance_km']} km away',
                                        style: GoogleFonts.outfit(
                                          color: AppTheme.accentColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    SizedBox(height: 8),
                                    if (!isServiceable)
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppTheme.lightWarningBg,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          salon['unavailable_reason'] ?? 'Not taking bookings right now',
                                          style: GoogleFonts.outfit(
                                              color: AppTheme.lightWarning,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      )
                                    else
                                      Row(
                                        children: [
                                          Icon(Icons.star, size: 14, color: AppTheme.starRating),
                                          SizedBox(width: 4),
                                          Text('4.5 (120 reviews)', style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 12, fontWeight: FontWeight.w600)),
                                        ],
                                      )
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      ),
      floatingActionButton: _globalCart != null && (_globalCart!['items'] as List).isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  // Pass the salonId from the global cart
                  builder: (context) => CartScreen()
                )).then((_) {
                  // Reload when returning from cart
                  _loadSalons();
                });
              },
              backgroundColor: AppTheme.accentColor,
              icon: Icon(Icons.shopping_cart, color: Colors.white),
              label: Text('View Cart (${_globalCart!['salon']?['name'] ?? 'Cart'})', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  /// What a customer sees when their city has nothing in it.
  ///
  /// An empty list with no explanation reads as a broken app. This says which
  /// city was searched, offers the nearest market that does have salons, and
  /// keeps the city control in reach — so there is always a way forward.
  Widget _buildEmptyCity() {
    final cityName = LocationService.instance.city?.name;
    final suggestedName = _suggestedCity?['name'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
      children: [
        Icon(Icons.storefront_outlined, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          cityName == null
              ? 'No salons found'
              : 'No salons in $cityName yet',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.lightTextHeading),
        ),
        const SizedBox(height: 6),
        Text(
          'We are adding salons all the time. Try another city in the meantime.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 13),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: _pickCity,
            icon: const Icon(Icons.location_on, size: 18),
            label: const Text('Change city'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentColor),
          ),
        ),

        if (_suggested.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(
            suggestedName == null
                ? 'You might like these'
                : 'Popular in $suggestedName',
            style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.lightTextHeading),
          ),
          const SizedBox(height: 12),
          ..._suggested.map((salon) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SalonDetailScreen(salonId: salon['id'].toString()),
                    ),
                  ),
                  tileColor: AppTheme.lightSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppTheme.lightBorder),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.lightAccentSoft,
                    child: Icon(Icons.storefront,
                        color: AppTheme.accentColor, size: 20),
                  ),
                  title: Text(salon['name'] ?? 'Unnamed Salon',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    salon['address'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontSize: 12),
                  ),
                ),
              )),
        ],
      ],
    );
  }
}
