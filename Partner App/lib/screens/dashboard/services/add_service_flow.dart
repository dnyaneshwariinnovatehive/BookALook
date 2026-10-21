import 'package:flutter/material.dart';
import 'package:partner_app/theme/app_theme.dart';
import '../../../../models/service_models.dart';
import '../../../../services/service_management_api.dart';
import '../../../../services/insights_api.dart';

class AddServiceFlow extends StatefulWidget {
  final String salonId;
  final List<ServiceCategory>? initialCategories;
  final List<SalonService>? initialSalonServices;

  const AddServiceFlow({
    super.key,
    required this.salonId,
    this.initialCategories,
    this.initialSalonServices,
  });

  @override
  State<AddServiceFlow> createState() => _AddServiceFlowState();
}

class _AddServiceFlowState extends State<AddServiceFlow> {
  bool _isLoading = true;
  List<ServiceCategory> _masterCategories = [];
  String? _error;

  // Selected state
  ServiceCategory? _selectedCategory;
  ServiceTemplate? _selectedTemplate;
  bool _isCustom = false;

  // Controllers for custom and pricing
  final _customCategoryController = TextEditingController();
  final _customTemplateController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController(); // For custom
  final _advanceController = TextEditingController(text: '20'); // Added advance controller

  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  List<SalonService> _allServices = [];
  final List<String> _linkedServiceIds = [];
  SalonInsights? _insights;

  // Track existing services in salon to prevent duplicates
  final Set<String> _existingTemplateIds = {};
  final Set<String> _existingNormalizedNames = {};
  final Set<String> _existingIdentities = {};

  static String _normalize(String str) => str.trim().toLowerCase();

  static String normalizeCustomIdentity(String category, String name) {
    final cat = _normalize(category);
    final n = _normalize(name);
    return '$cat::$n';
  }

  void _indexExistingServices(List<SalonService> flatServices) {
    _existingTemplateIds.clear();
    _existingNormalizedNames.clear();
    _existingIdentities.clear();

    for (final s in flatServices) {
      if (s.templateId.isNotEmpty) {
        _existingTemplateIds.add(s.templateId);
      }
      if (s.template != null) {
        final t = s.template!;
        if (t.id.isNotEmpty) {
          _existingTemplateIds.add(t.id);
        }
        final normName = _normalize(t.name);
        if (normName.isNotEmpty) {
          _existingNormalizedNames.add(normName);
          if (t.categoryId.isNotEmpty) {
            _existingIdentities.add('${t.categoryId}::$normName');
          }
          final catName = t.category?.name;
          if (catName != null && catName.isNotEmpty) {
            _existingIdentities.add(normalizeCustomIdentity(catName, normName));
          }
        }
      }
    }
  }

  bool _isTemplateAlreadyAdded(ServiceTemplate t, [ServiceCategory? category]) {
    if (_existingTemplateIds.contains(t.id)) return true;
    final normName = _normalize(t.name);
    if (normName.isNotEmpty) {
      if (_existingNormalizedNames.contains(normName)) return true;
      if (t.categoryId.isNotEmpty && _existingIdentities.contains('${t.categoryId}::$normName')) {
        return true;
      }
      final catName = category?.name ?? t.category?.name;
      if (catName != null && catName.isNotEmpty && _existingIdentities.contains(normalizeCustomIdentity(catName, normName))) {
        return true;
      }
    }
    return false;
  }

  List<ServiceTemplate> _getAvailableTemplates(ServiceCategory? category) {
    if (category == null || category.templates == null) return [];
    return category.templates!
        .where((t) => !_isTemplateAlreadyAdded(t, category))
        .toList();
  }

  bool _isCustomServiceDuplicate(String name, ServiceCategory? category) {
    final normName = _normalize(name);
    if (normName.isEmpty) return false;
    if (_existingNormalizedNames.contains(normName)) return true;
    final catId = category?.id ?? 'new_custom';
    if (_existingIdentities.contains('$catId::$normName')) return true;
    final catName = category?.name ?? _customCategoryController.text.trim();
    if (catName.isNotEmpty && _existingIdentities.contains(normalizeCustomIdentity(catName, normName))) {
      return true;
    }
    return false;
  }

  double get _currentAdvancePercentage {
    final text = _advanceController.text.trim();
    if (text.isEmpty) return 0;
    return double.tryParse(text) ?? 0;
  }

  bool get _canRefundAdvance => _currentAdvancePercentage > 0;

  void _onAdvanceChanged() {
    if (!_canRefundAdvance && _refundAdvance) {
      setState(() {
        _refundAdvance = false;
      });
    } else {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _advanceController.addListener(_onAdvanceChanged);
    _fetchMasterCatalog();
  }

  @override
  void dispose() {
    _advanceController.removeListener(_onAdvanceChanged);
    _customCategoryController.dispose();
    _customTemplateController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _advanceController.dispose();
    super.dispose();
  }

  Future<void> _fetchMasterCatalog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      List<ServiceCategory> categories;
      List<SalonService> flatServices;

      if (widget.initialCategories != null && widget.initialSalonServices != null) {
        categories = widget.initialCategories!;
        flatServices = widget.initialSalonServices!;
      } else {
        final futures = await Future.wait([
          widget.initialCategories != null
              ? Future.value(widget.initialCategories!)
              : ServiceManagementApi.getMasterCatalog(widget.salonId),
          widget.initialSalonServices != null
              ? Future.value(<Map<String, dynamic>>[])
              : ServiceManagementApi.getSalonServices(widget.salonId),
        ]);
        categories = widget.initialCategories ?? (futures[0] as List<ServiceCategory>);

        if (widget.initialSalonServices != null) {
          flatServices = widget.initialSalonServices!;
        } else {
          final groupedServices = futures[1] as List<Map<String, dynamic>>;
          flatServices = [];
          for (var group in groupedServices) {
            if (group['services'] != null) {
              for (var s in group['services']) {
                flatServices.add(SalonService.fromJson(s));
              }
            }
          }
        }
      }

      _indexExistingServices(flatServices);

      SalonInsights? insights;
      if (widget.initialCategories == null) {
        try {
          insights = await InsightsApi.fetch(widget.salonId);
        } catch (_) {}
      }

      setState(() {
        _masterCategories = categories;
        _allServices = flatServices;
        _insights = insights;

        if (_masterCategories.isNotEmpty) {
          final firstWithAvailable = _masterCategories.firstWhere(
            (c) => _getAvailableTemplates(c).isNotEmpty,
            orElse: () => _masterCategories.first,
          );
          _selectedCategory = firstWithAvailable;
          final available = _getAvailableTemplates(_selectedCategory);
          if (available.isNotEmpty) {
            _selectedTemplate = available.first;
            _isCustom = false;
          } else {
            _selectedTemplate = null;
            _isCustom = true;
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveService() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    if (!_isCustom) {
      if (_selectedTemplate == null) {
        _say('Please select a service or choose custom service.');
        return;
      }
      if (_isTemplateAlreadyAdded(_selectedTemplate!, _selectedCategory)) {
        _say('This service has already been added to your salon.');
        return;
      }
    } else {
      final customName = _customTemplateController.text.trim();
      if (customName.isEmpty) {
        _say('Give the service a name.');
        return;
      }
      if (_isCustomServiceDuplicate(customName, _selectedCategory)) {
        _say('A service named "$customName" already exists in this salon.');
        return;
      }
    }

    final advancePercentage = _currentAdvancePercentage;
    final willRefund = advancePercentage > 0 ? _refundAdvance : false;

    setState(() { _isSaving = true; });

    try {
      await ServiceManagementApi.addService(
        salonId: widget.salonId,
        isCustom: _isCustom,
        templateId: _selectedTemplate?.id,
        price: double.parse(_priceController.text),
        description: _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
        categoryId: _selectedCategory?.id ?? 'new_custom',
        customCategoryName: _isCustom && _customCategoryController.text.isNotEmpty ? _customCategoryController.text : null,
        customTemplateName: _isCustom && _customTemplateController.text.isNotEmpty ? _customTemplateController.text : null,
        estimatedDurationMinutes: _isCustom && _durationController.text.isNotEmpty ? int.parse(_durationController.text) : null,
        advancePercentage: advancePercentage,
        genderFocus: _genderFocus,
        willRefundAdvanceIfCancelled: willRefund,
        linkedServiceIds: _linkedServiceIds.isNotEmpty ? _linkedServiceIds : null,
      );

      if (mounted) {
        Navigator.pop(context, true); // true indicates success
      }
    } catch (e) {
      setState(() { _isSaving = false; });
      if (mounted) {
        _say('Error: $e');
      }
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(milliseconds: 2500), content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Add Service', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Text(_error!))
          : _buildForm(),
    );
  }

  int _duration = 30;
  String _genderFocus = 'Unisex';
  bool _refundAdvance = false;

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLabel('Category'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ServiceCategory>(
                isExpanded: true,
                value: _selectedCategory ?? (_masterCategories.isNotEmpty ? _masterCategories.first : null),
                items: _masterCategories.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCategory = val;
                    final available = _getAvailableTemplates(val);
                    if (available.isNotEmpty) {
                      _selectedTemplate = available.first;
                      _isCustom = false;
                    } else {
                      _selectedTemplate = null;
                      _isCustom = true;
                    }
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          _buildLabel('Template'),
          Builder(
            builder: (context) {
              final available = _getAvailableTemplates(_selectedCategory);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ServiceTemplate?>(
                    isExpanded: true,
                    value: _isCustom ? null : _selectedTemplate,
                    items: [
                      ...available.map((t) => DropdownMenuItem(value: t, child: Text(t.name))),
                      const DropdownMenuItem(value: null, child: Text('➕ Create Custom Service', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        if (val == null) {
                          _isCustom = true;
                          _selectedTemplate = null;
                        } else {
                          _isCustom = false;
                          _selectedTemplate = val;
                        }
                      });
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          if (_isCustom) ...[
            _buildLabel('Name'),
            _buildTextField(
              _customTemplateController,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (_isCustomServiceDuplicate(v.trim(), _selectedCategory)) {
                  return 'This service already exists in this salon';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],

          
          _buildLabel('Description'),
          _buildTextField(_descriptionController),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Price (₹)'),
                    _buildTextField(_priceController, isNumber: true),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Duration (min)'),
                    if (_isCustom)
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove, size: 18),
                              onPressed: () {
                                if (_duration > 30) setState(() => _duration -= 30);
                              },
                            ),
                            Text('$_duration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(
                              icon: Icon(Icons.add, size: 18),
                              onPressed: () {
                                setState(() => _duration += 30);
                              },
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 48,
                        width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${_selectedTemplate?.estimatedDurationMinutes ?? 30}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildLabel('Min Advance %'),
          _buildTextField(
            _advanceController,
            isNumber: true,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final n = double.tryParse(v.trim());
              if (n == null) return 'Enter a valid number';
              if (n < 0 || n > 100) return 'Must be between 0% and 100%';
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          // Category dropdown was moved up
          
          _buildLabel('Gender Focus'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _genderFocus,
                items: ['Unisex', 'Men Only', 'Women Only'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (val) {
                  setState(() => _genderFocus = val!);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          Builder(
            builder: (context) {
              final canRefund = _canRefundAdvance;
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;
              final textColor = canRefund
                  ? (theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface)
                  : (isDark ? Colors.white38 : Colors.black38);

              return Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: canRefund ? _refundAdvance : false,
                      onChanged: canRefund
                          ? (val) => setState(() => _refundAdvance = val ?? false)
                          : null,
                      activeColor: AppTheme.accentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: canRefund
                        ? () => setState(() => _refundAdvance = !_refundAdvance)
                        : null,
                    child: Text(
                      'Refund advance if cancelled',
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          
          _buildLinkedAddonsSection(),
          const SizedBox(height: 32),
          
          ElevatedButton(
            onPressed: _isSaving ? null : () {
              // Ensure we save properly using the single form data
              if (_isCustom) {
                _durationController.text = _duration.toString();
              }
              _saveService();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E1E2C), // Dark solid button
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _isSaving 
              ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Theme.of(context).colorScheme.surface, strokeWidth: 2)) 
              : Text('Add Service', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.surface, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Builder(
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).textTheme.bodyLarge?.color ?? Theme.of(context).colorScheme.onSurface.withOpacity(0.87))),
        );
      }
    );
  }

  Widget _buildTextField(
    TextEditingController controller, {
    bool isNumber = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.accentColor),
        ),
      ),
      validator: validator ?? ((v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
    );
  }

  Widget _buildLinkedAddonsSection() {
    final theme = Theme.of(context);
    final isAdvanced = _insights?.advanced == true;
    
    // Find smart suggestions
    final List<UpsellTip> smartTips = [];
    if (isAdvanced && _insights != null && _selectedTemplate != null) {
      smartTips.addAll(_insights!.upsell.where((u) => u.from.toLowerCase() == _selectedTemplate!.name.toLowerCase()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Linked Add-ons (Upsell)'),
        Text(
          'Recommend these services to customers when they book this one.',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6)),
        ),
        const SizedBox(height: 12),
        
        if (isAdvanced && smartTips.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 16),
                    const SizedBox(width: 8),
                    const Text('Smart Suggestions', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6D28D9), fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                ...smartTips.map((tip) {
                  // Find the service id if we have it in all services
                  final matchingService = _allServices.where((s) => (s.template?.name.toLowerCase() == tip.to.toLowerCase())).firstOrNull;
                  if (matchingService == null) return const SizedBox.shrink();
                  
                  final isSelected = _linkedServiceIds.contains(matchingService.id);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    title: Text(tip.to, style: const TextStyle(fontSize: 14)),
                    subtitle: Text('Usually boosts revenue by ${(tip.uplift * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    trailing: isSelected 
                      ? const Icon(Icons.check_circle, color: Color(0xFF8B5CF6))
                      : OutlinedButton(
                          onPressed: () => setState(() => _linkedServiceIds.add(matchingService.id)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF8B5CF6),
                            side: const BorderSide(color: Color(0xFF8B5CF6)),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Add'),
                        ),
                  );
                }),
              ],
            ),
          ),
          
        // Manual selection
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text('Select manual add-ons...'),
              value: null,
              items: _allServices.where((s) => !_linkedServiceIds.contains(s.id)).map((s) {
                return DropdownMenuItem(
                  value: s.id,
                  child: Text(s.template?.name ?? 'Custom Service'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _linkedServiceIds.add(val));
                }
              },
            ),
          ),
        ),
        
        if (_linkedServiceIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _linkedServiceIds.map((id) {
                final s = _allServices.firstWhere((s) => s.id == id, orElse: () => SalonService(id: id, salonId: '', templateId: '', price: 0));
                return Chip(
                  label: Text(s.template?.name ?? 'Unknown', style: const TextStyle(fontSize: 12)),
                  onDeleted: () => setState(() => _linkedServiceIds.remove(id)),
                  backgroundColor: theme.colorScheme.surface,
                  side: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.2)),
                );
              }).toList(),
            ),
          )
      ],
    );
  }
}
