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
  const ServicePickerSheet({super.key});

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

  bool _custom = false;
  final _search = TextEditingController();
  final _price = TextEditingController();
  final _customName = TextEditingController();
  final _customCategory = TextEditingController();
  final _customDuration = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    _load();
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

  /// Every template across every category, flattened, with its category name
  /// carried along so the result can be labelled without a second lookup.
  List<Map<String, dynamic>> get _matches {
    final term = _search.text.trim().toLowerCase();
    final results = <Map<String, dynamic>>[];

    for (final category in _categories) {
      for (final template in (category['templates'] as List? ?? [])) {
        final name = template['name']?.toString() ?? '';
        if (term.isEmpty || name.toLowerCase().contains(term)) {
          results.add({'template': template, 'category': category['name']?.toString() ?? ''});
        }
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

      Navigator.pop(
        context,
        DraftService(
          name: name,
          categoryName:
              _customCategory.text.trim().isEmpty ? 'Other' : _customCategory.text.trim(),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
          const SizedBox(height: 12),
          Expanded(child: _buildCatalogList()),
        ],
      );

  Widget _buildCatalogList() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final matches = _matches;

    if (matches.isEmpty) {
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
      itemCount: matches.length,
      itemBuilder: (_, index) {
        final template = matches[index]['template'] as Map<String, dynamic>;
        final categoryName = matches[index]['category'] as String;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: ListTile(
            title: Text(template['name'].toString(),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '$categoryName · ${template['estimated_duration_minutes'] ?? 30} min',
              style: const TextStyle(fontSize: 11.5, color: AppTheme.lightTextBody),
            ),
            trailing: const Icon(Icons.chevron_right, color: AppTheme.lightTextLight),
            onTap: () => setState(() {
              _chosenTemplate = template;
              _chosenCategoryName = categoryName;
            }),
          ),
        );
      },
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
