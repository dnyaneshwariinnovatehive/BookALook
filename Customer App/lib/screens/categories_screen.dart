import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/category.dart';
import '../services/category_service.dart';
import '../utils/app_haptics.dart';
import '../widgets/category_grid.dart';
import 'category_salons_screen.dart';
import '../widgets/feedback_states.dart';
import '../widgets/skeleton.dart';

/// Every category the platform has, presented in a modern, elegant,
/// mobile-first two-column grid.
///
/// Reached when the customer taps "More" or "Browse all" in the Categories
/// section of the home page. Picking a category opens the list of salons
/// offering that category in [CategorySalonsScreen].
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final CategoryService _categoryService = CategoryService();
  final TextEditingController _searchController = TextEditingController();

  List<ServiceCategory> _categories = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Palette 4 Tokens
  static const Color _primaryPurple = Color(0xFF9850F1);
  static const Color _secondaryLavender = Color(0xFFEEE3FD);
  static const Color _backgroundColor = Color(0xFFFCFAFF);
  static const Color _textDark = Color(0xFF18151D);
  static const Color _textMuted = Color(0xFF7C758D);

  // Two-column responsive grid delegate
  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: 14,
    mainAxisSpacing: 14,
    childAspectRatio: 1.16,
  );

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    final categories = await _categoryService.fetchCategories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _isLoading = false;
    });
  }

  void _retry() {
    setState(() => _isLoading = true);
    _fetchCategories();
  }

  /// Open the list of salons that offer this category.
  void _openInExplore(ServiceCategory category) {
    AppHaptics.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CategorySalonsScreen(category: category)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Combo leads, matching home screen behavior: package that salons build.
    final comboCat = _categories
        .where((c) => c.name.toLowerCase().contains('combo'))
        .firstOrNull;
    final combo = ServiceCategory(
      id: CategoryGrid.comboSentinelId,
      name: 'Combo',
      iconUrl: comboCat?.iconUrl,
    );
    final items = <ServiceCategory>[
      combo,
      ..._categories.where((c) =>
          c.id != CategoryGrid.comboSentinelId && c.id != comboCat?.id),
    ];

    // Filter categories based on search input
    final query = _searchQuery.trim().toLowerCase();
    final filteredItems = query.isEmpty
        ? items
        : items.where((c) => c.name.toLowerCase().contains(query)).toList();

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Section: Minimal back button, Bold heading, Subtitle, Rounded search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Minimal back button
                    InkWell(
                      onTap: () {
                        AppHaptics.selectionClick();
                        Navigator.of(context).maybePop();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _secondaryLavender, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryPurple.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: _textDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Bold "Explore Categories" heading
                    Text(
                      'Explore Categories',
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subtitle "Find the perfect service for you"
                    Text(
                      'Find the perfect service for you',
                      style: GoogleFonts.outfit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                        color: _textMuted,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Rounded search bar with search icon and placeholder
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _secondaryLavender, width: 1.4),
                        boxShadow: [
                          BoxShadow(
                            color: _primaryPurple.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        style: GoogleFonts.outfit(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: _textDark,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search categories',
                          hintStyle: GoogleFonts.outfit(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w400,
                            color: _textDark.withValues(alpha: 0.4),
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _primaryPurple,
                            size: 22,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: _textMuted,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 13,
                            horizontal: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Warning status if category fetch failed
              if (!_isLoading && _categories.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: InlineStatus(
                    message: 'Could not load the categories. Only Combo is shown.',
                    kind: StatusKind.warning,
                    onRetry: _retry,
                  ),
                ),

              // Categories Grid, Skeleton, or Empty Search State
              Expanded(
                child: _isLoading
                    ? _buildSkeletonGrid()
                    : RefreshIndicator(
                        color: _primaryPurple,
                        onRefresh: _fetchCategories,
                        child: filteredItems.isEmpty
                            ? _buildEmptyState()
                            : GridView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                                gridDelegate: _gridDelegate,
                                itemCount: filteredItems.length,
                                itemBuilder: (context, index) {
                                  final category = filteredItems[index];
                                  final style = _getCategoryStyle(category.name, index);
                                  return _CategoryCard(
                                    category: category,
                                    style: style,
                                    onTap: () => _openInExplore(category),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return Skeleton(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        gridDelegate: _gridDelegate,
        itemCount: 6,
        itemBuilder: (_, _) => const _CategoryCardSkeleton(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: _secondaryLavender,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  size: 32,
                  color: _primaryPurple,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No categories found',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'We couldn\'t find any category matching "$_searchQuery". Try searching with a different term.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: _textMuted,
                ),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: _primaryPurple,
                  backgroundColor: _secondaryLavender,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  'Clear search',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _primaryPurple,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps category names to pastel card styles consistent with Colour Palette 4
  static _CategoryCardStyle _getCategoryStyle(String name, int index) {
    final n = name.toLowerCase();
    if (n.contains('combo')) {
      return const _CategoryCardStyle(
        background: Color(0xFFF5EDFD),
        badgeBg: Color(0xFFEEE3FD),
        border: Color(0xFFE8D7FC),
      );
    }
    if (n.contains('hair')) {
      return const _CategoryCardStyle(
        background: Color(0xFFFFF2EB),
        badgeBg: Color(0xFFFFE5D6),
        border: Color(0xFFFFDEC9),
      );
    }
    if (n.contains('skin') || n.contains('facial')) {
      return const _CategoryCardStyle(
        background: Color(0xFFEDF8F2),
        badgeBg: Color(0xFFDBF2E4),
        border: Color(0xFFCEECD8),
      );
    }
    if (n.contains('nail')) {
      return const _CategoryCardStyle(
        background: Color(0xFFFDEEF3),
        badgeBg: Color(0xFFFCDCE6),
        border: Color(0xFFFCD0DE),
      );
    }
    if (n.contains('spa') || n.contains('massage')) {
      return const _CategoryCardStyle(
        background: Color(0xFFEEF3FE),
        badgeBg: Color(0xFFDEE9FC),
        border: Color(0xFFD2E1FB),
      );
    }
    if (n.contains('groom') || n.contains('beard') || n.contains('shave')) {
      return const _CategoryCardStyle(
        background: Color(0xFFFEF7E8),
        badgeBg: Color(0xFFFDEEC7),
        border: Color(0xFFFDE5B0),
      );
    }

    // Harmonious pastel fallback cycle
    const fallbackStyles = [
      _CategoryCardStyle(
        background: Color(0xFFF5EDFD),
        badgeBg: Color(0xFFEEE3FD),
        border: Color(0xFFE8D7FC),
      ),
      _CategoryCardStyle(
        background: Color(0xFFFFF2EB),
        badgeBg: Color(0xFFFFE5D6),
        border: Color(0xFFFFDEC9),
      ),
      _CategoryCardStyle(
        background: Color(0xFFEDF8F2),
        badgeBg: Color(0xFFDBF2E4),
        border: Color(0xFFCEECD8),
      ),
      _CategoryCardStyle(
        background: Color(0xFFFDEEF3),
        badgeBg: Color(0xFFFCDCE6),
        border: Color(0xFFFCD0DE),
      ),
      _CategoryCardStyle(
        background: Color(0xFFEEF3FE),
        badgeBg: Color(0xFFDEE9FC),
        border: Color(0xFFD2E1FB),
      ),
      _CategoryCardStyle(
        background: Color(0xFFFEF7E8),
        badgeBg: Color(0xFFFDEEC7),
        border: Color(0xFFFDE5B0),
      ),
    ];
    return fallbackStyles[index % fallbackStyles.length];
  }
}

class _CategoryCardStyle {
  final Color background;
  final Color badgeBg;
  final Color border;

  const _CategoryCardStyle({
    required this.background,
    required this.badgeBg,
    required this.border,
  });
}

class _CategoryCard extends StatelessWidget {
  final ServiceCategory category;
  final _CategoryCardStyle style;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: style.border,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9850F1).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: const Color(0xFF9850F1).withValues(alpha: 0.1),
          highlightColor: const Color(0xFF9850F1).withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon Container displaying dynamically fetched Superadmin logo
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFEEE3FD),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF9850F1).withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(9),
                      child: Center(
                        child: _buildCategoryIcon(category),
                      ),
                    ),
                    // Subtle arrow indicator
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF9850F1).withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: Color(0xFF9850F1),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Bold category name
                Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF18151D),
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryIcon(ServiceCategory category) {
    final hasIcon = category.iconUrl != null && category.iconUrl!.isNotEmpty;
    final isCombo = category.name.toLowerCase().contains('combo');

    // Combo default asset fallback if no remote icon provided
    if (isCombo && !hasIcon) {
      return Image.asset(
        'assets/images/combo_icon.jpg',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.card_giftcard_rounded,
          color: Color(0xFF9850F1),
          size: 24,
        ),
      );
    }

    // Dynamic logo from backend (Superadmin)
    if (hasIcon) {
      return Image.network(
        category.iconUrl!,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        errorBuilder: (context, error, stack) => Icon(
          CategoryGrid.fallbackIcon(category.name),
          color: const Color(0xFF9850F1),
          size: 24,
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Icon(
            CategoryGrid.fallbackIcon(category.name),
            color: const Color(0xFF9850F1).withValues(alpha: 0.35),
            size: 24,
          );
        },
      );
    }

    // Safe fallback icon
    return Icon(
      CategoryGrid.fallbackIcon(category.name),
      color: const Color(0xFF9850F1),
      size: 24,
    );
  }
}

class _CategoryCardSkeleton extends StatelessWidget {
  const _CategoryCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFEEE3FD),
          width: 1.2,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonBox(width: 48, height: 48, radius: 14),
              SkeletonBox(width: 28, height: 28, radius: 14),
            ],
          ),
          SizedBox(height: 12),
          SkeletonLine(widthFactor: 0.65, height: 16),
        ],
      ),
    );
  }
}
