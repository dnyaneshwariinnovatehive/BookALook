import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/category.dart';
import '../services/category_service.dart';
import '../theme/app_theme.dart';
import '../widgets/category_grid.dart';
import 'category_salons_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/feedback_states.dart';
import '../widgets/skeleton.dart';

/// Every category the platform has, as a grid.
///
/// Reached from the fourth card on the home screen and from the "Browse all"
/// link above it. Picking a category does not filter anything here — it opens
/// the list of salons offering that category, so there is only ever one place
/// that knows how a category turns into a list of salons.
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
  static const int _columns = 4;
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

  /// Open the list of salons that offer this category in the customer's city.
  ///
  /// This page stays on the stack underneath: the customer picked a category
  /// from a grid, and backing out of the salons should return them to that grid
  /// rather than dropping them on the home screen.
  void _openInExplore(ServiceCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CategorySalonsScreen(category: category)),
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
            ? Skeleton(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  gridDelegate: _gridDelegate,
                  itemCount: 12,
                  itemBuilder: (_, _) => const CategoryTileSkeleton(),
                ),
              )
            : Column(
                children: [
                  // The service returns an empty list on failure, so an empty
                  // catalogue is the only sign a load went wrong. Without this
                  // the screen showed Combo alone and said nothing.
                  if (_categories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: InlineStatus(
                        message: 'Could not load the categories. Only Combo is shown.',
                        kind: StatusKind.warning,
                        onRetry: _retry,
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      color: AppTheme.accentColor,
                      onRefresh: _fetchCategories,
                      child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                gridDelegate: _gridDelegate,
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
                  ),
                ],
              ),
      ),
    );
  }

  /// Square icon box plus one line of label underneath; shared by the grid
  /// and its skeleton so the placeholder lands where the tiles will.
  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: _columns,
    crossAxisSpacing: _gap,
    mainAxisSpacing: _gap,
    childAspectRatio: 1 / 1.32,
  );

  void _retry() {
    setState(() => _isLoading = true);
    _fetchCategories();
  }

  static const (Color, Color) _comboTint = (Color(0xFFEEE3FD), Color(0xFF9850F1));

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: isDark ? foreground.withValues(alpha: 0.16) : background,
                borderRadius: BorderRadius.circular(18),
              ),
              child: category.name.toLowerCase().contains('combo')
                  ? Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Image.asset(
                        'assets/images/combo_icon.jpg',
                        fit: BoxFit.contain,
                      ),
                    )
                  : (hasIcon
                      ? Image.network(
                          category.iconUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Icon(
                            CategoryGrid.fallbackIcon(category.name),
                            color: foreground,
                            size: 26,
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Icon(
                              CategoryGrid.fallbackIcon(category.name),
                              color: foreground.withValues(alpha: 0.35),
                              size: 26,
                            );
                          },
                        )
                      : Icon(
                          CategoryGrid.fallbackIcon(category.name),
                          color: foreground,
                          size: 26,
                        )),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            category.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
