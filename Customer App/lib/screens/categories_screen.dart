import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/category.dart';
import '../services/category_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_grid.dart';
import 'discovery_screen.dart';

/// Every category the platform has, as a grid.
///
/// Reached from the fourth card on the home screen and from the "Browse all"
/// link above it. Picking a category does not filter anything here — it hands
/// the request to the Explore tab and lets that screen do the filtering, so
/// there is only ever one place that knows how salons are listed.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final CategoryService _categoryService = CategoryService();

  List<ServiceCategory> _categories = [];
  bool _isLoading = true;

  /// Columns of the grid. Narrow phones get three so the icon and its label
  /// both stay legible.
  static const int _columns = 3;
  static const double _gap = 12;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    final categories = await _categoryService.fetchCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _isLoading = false;
    });
  }

  /// Leave this page first so the shell is visible, then push the discovery
  /// page for whichever catalogue item was picked.
  void _openInExplore(ServiceCategory category) {
    Navigator.of(context).pop();
    if (category.id == CategoryGrid.comboSentinelId) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ComboDiscoveryScreen()),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CategoryDiscoveryScreen(category: category)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Combo leads, exactly as it does on the home screen: it is the one
    // category the customer reaches for that the catalogue does not list.
    final combo = ServiceCategory(
      id: CategoryGrid.comboSentinelId,
      name: 'Combo',
    );
    final items = <ServiceCategory>[
      combo,
      ..._categories.where((c) => c.id != CategoryGrid.comboSentinelId),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('All Categories', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: AppTheme.accentColor),
              )
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  crossAxisSpacing: _gap,
                  mainAxisSpacing: _gap,
                  // Square icon box plus one line of label underneath.
                  childAspectRatio: 1 / 1.32,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final category = items[index];
                  final isCombo = index == 0;
                  return _CategoryCard(
                    category: category,
                    tint: isCombo ? _comboTint : _tints[(index - 1) % _tints.length],
                    isDark: isDark,
                    onTap: () => _openInExplore(category),
                  );
                },
              ),
      ),
    );
  }

  static const (Color, Color) _comboTint = (Color(0xFFF3EBFE), Color(0xFF9C54F2));

  static const List<(Color, Color)> _tints = [
    (Color(0xFFFFF1E6), Color(0xFFEF6C00)),
    (Color(0xFFE6F6EF), Color(0xFF2E7D32)),
    (Color(0xFFFDE8EF), Color(0xFFD81B60)),
    (Color(0xFFE7F0FD), Color(0xFF1565C0)),
    (Color(0xFFFFF6DA), Color(0xFFF59E0B)),
  ];
}

class _CategoryCard extends StatelessWidget {
  final ServiceCategory category;
  final (Color, Color) tint;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.tint,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = tint;
    final hasIcon = category.iconUrl != null && category.iconUrl!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? foreground.withOpacity(0.16) : background,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(12),
                child: hasIcon
                    ? Image.network(
                        category.iconUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) => Icon(
                          CategoryGrid.fallbackIcon(category.name),
                          color: foreground,
                          size: 26,
                        ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Icon(
                            CategoryGrid.fallbackIcon(category.name),
                            color: foreground.withOpacity(0.35),
                            size: 26,
                          );
                        },
                      )
                    : Icon(
                        CategoryGrid.fallbackIcon(category.name),
                        color: foreground,
                        size: 26,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              category.name,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
