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

class _ServicesTabState extends State<ServicesTab> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _groupedServices = [];
  String? _error;
  
  List<dynamic> _combos = [];
  bool _isLoadingCombos = true;
  String? _combosError;

  @override
  void initState() {
    super.initState();
    _fetchServices();
    _fetchCombos();
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Menu & Pricing'),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
          bottom: const TabBar(
            labelColor: AppTheme.accentColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppTheme.accentColor,
            tabs: [
              Tab(text: 'Services'),
              Tab(text: 'Combos'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildServicesTab(),
            _buildCombosTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesTab() {
    return Scaffold(
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addServiceBtn',
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddServiceFlow(salonId: widget.salonId)),
          );
          if (result == true) {
            _fetchServices();
          }
        },
        label: const Text('Add Service'),
        icon: const Icon(Icons.add),
        backgroundColor: AppTheme.accentColor,
      ),
    );
  }

  Widget _buildCombosTab() {
    return Scaffold(
      body: _buildCombosList(),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addComboBtn',
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddComboScreen(salonId: widget.salonId)),
          );
          if (result == true) {
            _fetchCombos();
          }
        },
        label: const Text('Add Combo'),
        icon: const Icon(Icons.add),
        backgroundColor: AppTheme.accentColor,
      ),
    );
  }

  Widget _buildCombosList() {
    if (_isLoadingCombos) return const Center(child: CircularProgressIndicator());
    if (_combosError != null) return Center(child: Text('Error: $_combosError'));
    if (_combos.isEmpty) return const Center(child: Text('No combos found.\nTap "Add Combo" to create one.', textAlign: TextAlign.center));

    return RefreshIndicator(
      onRefresh: _fetchCombos,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80, top: 16),
        itemCount: _combos.length,
        itemBuilder: (context, index) {
          final combo = _combos[index];
          final services = combo['services'] as List;
          double totalPrice = 0;
          for (var s in services) {
            totalPrice += double.parse(s['pivot']['combo_special_price'] ?? '0');
          }

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ExpansionTile(
              title: Text(combo['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${services.length} services included \u2022 \u20B9${totalPrice.toStringAsFixed(0)}'),
              children: services.map((s) {
                return ListTile(
                  title: Text(s['template']['name']),
                  trailing: Text('\u20B9${double.parse(s['pivot']['combo_special_price'] ?? '0').toStringAsFixed(0)}'),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchServices,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_groupedServices.isEmpty) {
      return const Center(
        child: Text('No services added yet.\nTap "Add Service" to get started.', textAlign: TextAlign.center),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchServices,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _groupedServices.length,
        itemBuilder: (context, index) {
          final group = _groupedServices[index];
          final category = ServiceCategory.fromJson(group['category']);
          final servicesList = group['services'] as List;
          final services = servicesList.map((s) => SalonService.fromJson(s)).toList();

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                title: Text(
                  category.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                children: services.map((service) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    title: Text(service.template?.name ?? 'Unknown Service'),
                    subtitle: service.description != null ? Text(service.description!, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
                    trailing: Text(
                      '₹${service.price.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.accentColor),
                    ),
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
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}
