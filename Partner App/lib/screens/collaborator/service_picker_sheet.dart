import 'package:flutter/material.dart';

import '../../models/onboarding_draft.dart';
import '../../services/collaborator_api.dart';
import '../../theme/app_theme.dart';

/// Adding one line to the salon's menu.
///
/// Two ways in, and both end in a price. Most services are in the master
/// catalog and only need a number typed against them; the rest are whatever
/// this particular salon happens to do, and get described from scratch.
///
/// The catalog is fetched when the sheet opens, but it is not required — a
/// collaborator with no signal can still add custom services, which is the
/// whole reason the custom path is not hidden behind an empty list.
class ServicePickerSheet extends StatefulWidget {
  final Set<String> existingTemplateIds;
  final Set<String> existingCustomIdentities;
  final List<dynamic>? initialCategories;

  const ServicePickerSheet({
    super.key,
    this.existingTemplateIds = const {},
    this.existingCustomIdentities = const {},
    this.initialCategories,
  });

  static String normalizeCustomIdentity(String category, String name) {
    final cat = category.trim().toLowerCase();
    final n = name.trim().toLowerCase();
    return '$cat::$n';
  }

  @override
  State<ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<ServicePickerSheet> {
  List<dynamic> _categories = [];
  bool _loading = true;

  /// Null while browsing the catalog; set once a template is chosen and the
  /// only thing left is the price.
  Map<String, dynamic>? _chosenTemplate;
  String _chosenCategoryName = '';
  String? _selectedCategoryName;

  bool _custom = false;
  final _search = TextEditingController();
  final _price = TextEditingController();
  final _customName = TextEditingController();
  final _customCategory = TextEditingController();
  final _customDuration = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    if (widget.initialCategories != null) {
      _categories = widget.initialCategories!;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    List<dynamic> categories = [];
    try {
      categories = await CollaboratorApi.masterCatalog();
    } catch (_) {
      // Offline. The custom path still works, which is what matters on site.
    }

    if (mounted) {
      setState(() {
        _categories = categories;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _price.dispose();
    _customName.dispose();
    _customCategory.dispose();
    _customDuration.dispose();
    super.dispose();
  }

  /// All valid categories loaded from the catalog.
  List<Map<String, dynamic>> get _availableCategories {
    return _categories
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Total count of service templates across all categories.
  int get _totalServicesCount {
    var count = 0;
    for (final cat in _availableCategories) {
      final templates = cat['templates'] as List? ?? [];
      count += templates.length;
    }
    return count;
  }

  /// Matching categories and their templates, grouped by category and
  /// filtered by search keyword and the selected category dropdown.
  List<Map<String, dynamic>> get _groupedMatches {
    final term = _search.text.trim().toLowerCase();
    final results = <Map<String, dynamic>>[];

    for (final rawCategory in _categories) {
      if (rawCategory is! Map) continue;
      final category = Map<String, dynamic>.from(rawCategory);
      final categoryName = category['name']?.toString() ?? '';

      // If category dropdown has a selection, filter to only that category
      if (_selectedCategoryName != null &&
          _selectedCategoryName!.isNotEmpty &&
          _selectedCategoryName != categoryName) {
        continue;
      }

      final templates = (category['templates'] as List? ?? []);
      final matchingTemplates = <Map<String, dynamic>>[];

      for (final rawTemplate in templates) {
        if (rawTemplate is! Map) continue;
        final template = Map<String, dynamic>.from(rawTemplate);
        final name = template['name']?.toString() ?? '';

        if (term.isEmpty ||
            name.toLowerCase().contains(term) ||
            categoryName.toLowerCase().contains(term)) {
          matchingTemplates.add(template);
        }
      }

      if (matchingTemplates.isNotEmpty) {
        results.add({
          'id': category['id']?.toString() ?? categoryName,
          'name': categoryName,
          'templates': matchingTemplates,
        });
      }
    }

    return results;
  }


  void _submit() {
    final price = double.tryParse(_price.text.trim());

    if (price == null || price < 0) {
      _say('Enter a price.');
      return;
    }

    if (_custom) {
      final name = _customName.text.trim();
      final duration = int.tryParse(_customDuration.text.trim()) ?? 0;

      if (name.isEmpty) return _say('Give the service a name.');
      if (duration < 15) return _say('A service needs to take at least 15 minutes.');

      final category =
          _customCategory.text.trim().isEmpty ? 'Other' : _customCategory.text.trim();
      final customIdentity = ServicePickerSheet.normalizeCustomIdentity(category, name);

      if (widget.existingCustomIdentities.contains(customIdentity)) {
        return _say('This custom service has already been added in "$category".');
      }

      Navigator.pop(
        context,
        DraftService(
          name: name,
          categoryName: category,
          durationMinutes: duration,
          price: price,
        ),
      );
      return;
    }

    final template = _chosenTemplate!;
    Navigator.pop(
      context,
      DraftService(
        templateId: template['id'].toString(),
        name: template['name'].toString(),
        categoryName: _chosenCategoryName,
        durationMinutes: (template['estimated_duration_minutes'] as num?)?.toInt() ?? 30,
        price: price,
      ),
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2500), content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppTheme.lightBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHandle(),
          Expanded(
            child: _custom || _chosenTemplate != null ? _buildPriceStep() : _buildCatalogStep(),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppTheme.lightBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  // ------------------------------------------------------------- catalog

  Widget _buildCatalogStep() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Add a service',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _custom = true),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Custom', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.accentColor),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search the catalog',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.lightBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.lightBorder),
                ),
              ),
            ),
          ),
          if (!_loading && _availableCategories.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildCategoryDropdown(),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(child: _buildCatalogList()),
        ],
      );

  Widget _buildCategoryDropdown() {
    final categories = _availableCategories;
    final totalCount = _totalServicesCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedCategoryName,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.accentColor),
          hint: Row(
            children: [
              const Icon(Icons.category_outlined, size: 18, color: AppTheme.accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Category: All Categories ($totalCount)',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.lightTextHeading,
                  ),
                ),
              ),
            ],
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  const Icon(Icons.category_outlined, size: 18, color: AppTheme.accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All Categories ($totalCount services)',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...categories.map((c) {
              final name = c['name']?.toString() ?? '';
              final count = (c['templates'] as List? ?? []).length;
              return DropdownMenuItem<String?>(
                value: name,
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined, size: 18, color: AppTheme.lightTextBody),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$name ($count)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: (val) {
            setState(() {
              _selectedCategoryName = val;
            });
          },
        ),
      ),
    );
  }

  Widget _buildCatalogList() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final grouped = _groupedMatches;

    if (grouped.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined, size: 40, color: AppTheme.lightTextLight),
              const SizedBox(height: 14),
              Text(
                _categories.isEmpty
                    ? 'The catalog could not be loaded. You can still add services by hand.'
                    : 'Nothing in the catalog matches that.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.lightTextBody),
              ),
              if (_selectedCategoryName != null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => setState(() => _selectedCategoryName = null),
                  child: const Text('Show all categories',
                      style: TextStyle(color: AppTheme.accentColor, fontWeight: FontWeight.w600)),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => setState(() => _custom = true),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add a custom service'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: grouped.length,
      itemBuilder: (_, index) {
        final group = grouped[index];
        final categoryName = group['name'] as String;
        final templates = group['templates'] as List<Map<String, dynamic>>;

        // Count how many templates in this category have already been added to the draft
        final addedCount = templates.where((t) {
          final id = t['id']?.toString() ?? '';
          return widget.existingTemplateIds.contains(id);
        }).length;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: PageStorageKey('cat_${group['id']}_${_search.text}_$_selectedCategoryName'),
                initiallyExpanded: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        categoryName,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.lightTextHeading,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.lightAccentSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${templates.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentColor,
                        ),
                      ),
                    ),
                    if (addedCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$addedCount added',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                children: [
                  const Divider(height: 1, color: AppTheme.lightBorder),
                  for (var i = 0; i < templates.length; i++)
                    _buildTemplateItem(templates[i], categoryName, isLast: i == templates.length - 1),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTemplateItem(Map<String, dynamic> template, String categoryName, {bool isLast = false}) {
    final templateId = template['id']?.toString() ?? '';
    final isAdded = widget.existingTemplateIds.contains(templateId);

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            title: Text(
              template['name'].toString(),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: isAdded ? AppTheme.lightTextBody : AppTheme.lightTextHeading,
              ),
            ),
            subtitle: Text(
              '$categoryName · ${template['estimated_duration_minutes'] ?? 30} min',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.lightTextBody),
            ),
            trailing: isAdded
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.lightAccentSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Added',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentColor,
                      ),
                    ),
                  )
                : const Icon(Icons.chevron_right, color: AppTheme.lightTextLight, size: 20),
            onTap: isAdded
                ? () => _say('This service is already in the draft.')
                : () => setState(() {
                    _chosenTemplate = template;
                    _chosenCategoryName = categoryName;
                  }),
          ),
          if (!isLast) const Divider(height: 1, color: Color(0xFFF3F4F6)),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- price

  Widget _buildPriceStep() {
    final title = _custom ? 'Custom service' : _chosenTemplate!['name'].toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => setState(() {
                _custom = false;
                _chosenTemplate = null;
              }),
            ),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_custom) ...[
          _label('Service name *'),
          _input(_customName, 'e.g. Beard sculpt'),
          const SizedBox(height: 14),
          _label('Category'),
          _input(_customCategory, 'e.g. Grooming — leave blank for "Other"'),
          const SizedBox(height: 14),
          _label('How long it takes (minutes) *'),
          _input(_customDuration, '30', keyboard: TextInputType.number),
          const SizedBox(height: 14),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.lightAccentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$_chosenCategoryName · ${_chosenTemplate!['estimated_duration_minutes'] ?? 30} minutes',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.accentColor),
            ),
          ),
          const SizedBox(height: 16),
        ],

        _label('Price (₹) *'),
        _input(_price, '0', keyboard: TextInputType.number),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              backgroundColor: AppTheme.accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Add to the menu',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );

  Widget _input(TextEditingController controller, String hint, {TextInputType? keyboard}) =>
      TextField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.lightTextLight, fontSize: 13.5),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.accentColor),
          ),
        ),
      );
}
