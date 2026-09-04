import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../models/service_models.dart';
import '../../../services/service_management_api.dart';
import '../services/add_service_flow.dart';
import '../services/edit_service_sheet.dart';
import '../services/add_combo_screen.dart';

class ServicesTab extends StatefulWidget {
  final String salonId;
  const ServicesTab({super.key, required this.salonId});

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _groupedServices = [];
  String? _error;
  
  List<dynamic> _combos = [];
  bool _isLoadingCombos = true;
  String? _combosError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchServices();
    _fetchCombos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchServices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final grouped = await ServiceManagementApi.getSalonServices(widget.salonId);
      setState(() {
        _groupedServices = grouped;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchCombos() async {
    setState(() {
      _isLoadingCombos = true;
      _combosError = null;
    });
    try {
      final combos = await ServiceManagementApi.getCombos(widget.salonId);
      setState(() {
        _combos = combos;
        _isLoadingCombos = false;
      });
    } catch (e) {
      setState(() {
        _combosError = e.toString();
        _isLoadingCombos = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Services', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                final isCombo = _tabController.index == 1;
                if (isCombo) {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AddComboScreen(salonId: widget.salonId)),
                  );
                  if (result == true) _fetchCombos();
                } else {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AddServiceFlow(salonId: widget.salonId)),
                  );
                  if (result == true) _fetchServices();
                }
              },
              icon: Icon(Icons.add, size: 18),
              label: Text('Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Segmented Tab Bar
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(30),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(color: theme.colorScheme.onSurface.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 4, offset: Offset(0, 2))
                ]
              ),
              labelColor: theme.textTheme.bodyLarge?.color,
              unselectedLabelColor: AppTheme.accentColor,
              labelStyle: TextStyle(fontWeight: FontWeight.bold),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Services'),
                Tab(text: 'Combos'),
              ],
            ),
          ),
          
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildServicesTab(),
                _buildCombosTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesTab() {
    return _buildBody();
  }

  Widget _buildCombosTab() {
    return _buildCombosList();
  }

  Widget _buildCombosList() {
    if (_isLoadingCombos) return const Center(child: CircularProgressIndicator());
    if (_combosError != null) return Center(child: Text('Error: $_combosError'));
    if (_combos.isEmpty) return const Center(child: Text('No combos found.\nTap "Add" to create one.', textAlign: TextAlign.center));

    return RefreshIndicator(
      onRefresh: _fetchCombos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _combos.length,
        itemBuilder: (context, index) {
          final combo = _combos[index];
          final services = combo['services'] as List;
          double totalPrice = 0;
          double originalPrice = 0;
          List<String> serviceNames = [];
          for (var s in services) {
            totalPrice += double.parse(s['pivot']['combo_special_price']?.toString() ?? '0');
            originalPrice += double.parse(s['price']?.toString() ?? '0');
            serviceNames.add(s['template']['name']);
          }
          final savings = originalPrice - totalPrice;

          return GestureDetector(
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddComboScreen(salonId: widget.salonId, existingCombo: combo),
                ),
              );
              if (result == true) {
                _fetchCombos();
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).dividerColor : Theme.of(context).dividerColor),
                boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.02), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(combo['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                        child: Text('Active', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess), fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(serviceNames.join(', '), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('\u20B9${totalPrice.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.accentColor)),
                      const SizedBox(width: 12),
                      if (savings > 0)
                        Text('Save \u20B9${savings.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess))),
                      const SizedBox(width: 12),
                      Text('Adv: ${combo['advance_percentage'] ?? 0}%', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));

    if (_groupedServices.isEmpty) {
      return const Center(child: Text('No services added yet.\nTap "Add" to get started.', textAlign: TextAlign.center));
    }

    // Flatten grouped services to a single list
    List<Map<String, dynamic>> flatServices = [];
    for (var group in _groupedServices) {
      final category = ServiceCategory.fromJson(group['category']);
      final servicesList = group['services'] as List;
      for (var s in servicesList) {
        flatServices.add({
          'category': category,
          'service': SalonService.fromJson(s),
        });
      }
    }

    return RefreshIndicator(
      onRefresh: _fetchServices,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: flatServices.length,
        itemBuilder: (context, index) {
          final category = flatServices[index]['category'] as ServiceCategory;
          final service = flatServices[index]['service'] as SalonService;

          return GestureDetector(
            onTap: () async {
              final result = await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => EditServiceSheet(
                  salonId: widget.salonId,
                  service: service,
                ),
              );
              if (result == true) {
                _fetchServices();
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).dividerColor : Theme.of(context).dividerColor),
                boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.02), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(service.template?.name ?? 'Unknown Service', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                        child: Text('Active', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSuccess : AppTheme.lightSuccess), fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(8)),
                        child: Text(category.name, style: TextStyle(color: AppTheme.accentColor, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Text('\u20B9${service.price.toStringAsFixed(0)}', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                      const SizedBox(width: 12),
                      Text('${service.template?.estimatedDurationMinutes ?? 0} min', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                      const SizedBox(width: 12),
                      Text('Adv: 20%', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Providers: All Staff', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
