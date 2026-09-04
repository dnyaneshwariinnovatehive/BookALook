import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/salon_service.dart';
import '../salon_detail_screen.dart';

class ExploreTab extends StatefulWidget {
  @override
  _ExploreTabState createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  final SalonService _salonService = SalonService();
  List<dynamic> _salons = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadSalons();
  }

  Future<void> _loadSalons() async {
    try {
      final salons = await _salonService.fetchSalons();
      setState(() {
        _salons = salons;
        _isLoading = false;
      });
    } catch (e) {
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

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(20),
            child: Text('Explore Salons', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
          ),
          Expanded(
            child: _salons.isEmpty
                ? Center(child: Text('No salons found.', style: GoogleFonts.outfit(color: AppTheme.lightTextBody)))
                : ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    itemCount: _salons.length,
                    separatorBuilder: (context, index) => SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final salon = _salons[index];
                      return InkWell(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (context) => SalonDetailScreen(salonId: salon['id'].toString())
                          ));
                        },
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
                                    SizedBox(height: 8),
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
