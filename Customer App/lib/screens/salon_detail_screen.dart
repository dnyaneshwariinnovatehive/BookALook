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
  Map<String, dynamic>? _salon;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSalonDetails();
  }

  Future<void> _loadSalonDetails() async {
    try {
      final data = await _salonService.fetchSalonDetails(widget.salonId);
      setState(() {
        _salon = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading salon details')));
    }
  }

  Future<void> _addToCart(String serviceId) async {
    try {
      await _cartService.addItem(widget.salonId, serviceId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to cart!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.accentColor)));
    }
    if (_salon == null) {
      return Scaffold(body: Center(child: Text('Salon not found')));
    }

    final services = _salon!['services'] as List? ?? [];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250.0,
            floating: false,
            pinned: true,
            backgroundColor: AppTheme.accentColor,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_salon!['name'], style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppTheme.accentGradientLightEnd, AppTheme.accentColor],
                  )
                ),
                child: Center(child: Icon(Icons.storefront, size: 100, color: Colors.white.withOpacity(0.5))),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.shopping_bag_outlined),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (context) => CartScreen(salonId: widget.salonId)
                  ));
                },
              )
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: AppTheme.lightTextBody),
                      SizedBox(width: 8),
                      Expanded(child: Text(_salon!['address'] ?? '', style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 16))),
                    ],
                  ),
                  SizedBox(height: 32),
                  Text('Services Offered', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
                  SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final service = services[index];
                final template = service['template'] ?? {};
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.lightSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.lightBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(template['name'] ?? 'Service', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
                              SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 14, color: AppTheme.lightTextBody),
                                  SizedBox(width: 4),
                                  Text('${template['estimated_duration_minutes'] ?? 0} min', style: GoogleFonts.outfit(color: AppTheme.lightTextBody)),
                                ],
                              )
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('\$${service['price']}', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                            SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () => _addToCart(service['id'].toString()),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.lightAccentSoft,
                                foregroundColor: AppTheme.accentColor,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text('Add', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
              childCount: services.length,
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 40)) // Bottom padding
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => CartScreen(salonId: widget.salonId)
          ));
        },
        backgroundColor: AppTheme.accentColor,
        icon: Icon(Icons.shopping_cart),
        label: Text('View Cart'),
      ),
    );
  }
}
