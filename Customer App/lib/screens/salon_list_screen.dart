import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/location_service.dart';
import '../widgets/city_picker_sheet.dart';
import '../services/salon_service.dart';
import 'salon_detail_screen.dart';

class SalonListScreen extends StatefulWidget {
  final String? initialSearch;
  final String? initialGender;
  final String? initialCategoryId;
  final String title;

  const SalonListScreen({
    Key? key,
    this.initialSearch,
    this.initialGender,
    this.initialCategoryId,
    required this.title,
  }) : super(key: key);

  @override
  _SalonListScreenState createState() => _SalonListScreenState();
}

class _SalonListScreenState extends State<SalonListScreen> {
  final SalonService _salonService = SalonService();
  List<dynamic> _salons = [];
  List<dynamic> _suggestedSalons = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadSalons();
  }

  Future<void> _loadSalons() async {
    try {
      final response = await _salonService.fetchSalons(
        search: widget.initialSearch,
        gender: widget.initialGender,
        categoryId: widget.initialCategoryId,
      );
      setState(() {
        _salons = response['salons'] ?? [];
        _suggestedSalons = response['suggested_salons'] ?? [];
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: AppTheme.lightTheme.appBarTheme.titleTextStyle),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accentColor))
          : _error.isNotEmpty
              ? Center(child: Text(_error, style: GoogleFonts.outfit(color: AppTheme.lightDanger)))
              : _salons.isEmpty
                  ? _buildEmptyOrSuggestions()
                  : ListView.separated(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      itemCount: _salons.length,
                      separatorBuilder: (context, index) => SizedBox(height: 16),
                      itemBuilder: (context, index) => _buildSalonItem(_salons[index]),
                    ),
    );
  }

  Widget _buildEmptyOrSuggestions() {
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty && _suggestedSalons.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 8),
            child: Text(
              LocationService.instance.hasCity
                  ? 'No match in ${LocationService.instance.city!.name}.'
                  : 'No exact match found.',
              style: GoogleFonts.outfit(color: AppTheme.lightDanger, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Here are some nearby salons you might like:',
              style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 14),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              itemCount: _suggestedSalons.length,
              separatorBuilder: (context, index) => SizedBox(height: 16),
              itemBuilder: (context, index) => _buildSalonItem(_suggestedSalons[index]),
            ),
          ),
        ],
      );
    }

    // Naming the city matters here: searching is city-scoped, so "nothing
    // found" without it reads as "this salon does not exist" rather than
    // "not in the city you are looking at".
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              LocationService.instance.hasCity
                  ? 'No salons found in ${LocationService.instance.city!.name}.'
                  : 'No salons found.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: AppTheme.lightTextHeading, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different search, or change your city.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: AppTheme.lightTextBody, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () async {
                final changed = await showCityPicker(context);
                if (changed && mounted) {
                  setState(() => _isLoading = true);
                  _loadSalons();
                }
              },
              icon: const Icon(Icons.location_on, size: 18),
              label: const Text('Change city'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalonItem(dynamic salon) {
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
  }
}
