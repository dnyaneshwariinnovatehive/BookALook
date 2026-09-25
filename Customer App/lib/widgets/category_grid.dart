import 'dart:async';
import 'package:flutter/material.dart';

import '../models/category.dart';
import '../theme/app_theme.dart';

/// The category picker on the home screen.
///
/// A horizontally scrolling carousel of categories, showing 4 items at a time.
/// It automatically scrolls every 5 seconds and guarantees that the 'Combo'
/// category appears first.
class CategoryGrid extends StatefulWidget {
  final List<ServiceCategory> categories;
  final void Function(ServiceCategory category) onTap;

  const CategoryGrid({super.key, required this.categories, required this.onTap});

  /// A sensible picture when a category has no icon yet.
  static IconData fallbackIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('combo')) return Icons.card_giftcard_rounded;
    if (n.contains('hair')) return Icons.content_cut_rounded;
    if (n.contains('skin') || n.contains('facial')) return Icons.face_retouching_natural;
    if (n.contains('nail')) return Icons.back_hand_outlined;
    if (n.contains('spa') || n.contains('massage')) return Icons.spa_rounded;
    if (n.contains('groom') || n.contains('beard') || n.contains('shave')) {
      return Icons.face_rounded;
    }
    if (n.contains('makeup') || n.contains('bridal')) return Icons.brush_rounded;
    if (n.contains('wax') || n.contains('thread')) return Icons.auto_fix_high_rounded;
    return Icons.category_rounded;
  }

  @override
  State<CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends State<CategoryGrid> {
  PageController? _pageController;
  Timer? _timer;
  int? _currentPage;
  double? _lastWidth;

  /// Soft backgrounds behind the icons.
  static const List<(Color, Color)> _tints = [
    (Color(0xFFF3EBFE), Color(0xFF9C54F2)), // lavender
    (Color(0xFFFFF1E6), Color(0xFFEF6C00)), // peach
    (Color(0xFFE6F6EF), Color(0xFF2E7D32)), // mint
    (Color(0xFFFDE8EF), Color(0xFFD81B60)), // rose
    (Color(0xFFE7F0FD), Color(0xFF1565C0)), // sky
    (Color(0xFFFFF6DA), Color(0xFFF59E0B)), // honey
  ];

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || widget.categories.isEmpty || _pageController == null) return;
      if (!_pageController!.hasClients) return;
      
      _pageController!.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  List<ServiceCategory> _getProcessedCategories() {
    List<ServiceCategory> cats = List.from(widget.categories);
    int comboIndex = cats.indexWhere((c) => c.name.toLowerCase() == 'combo');
    if (comboIndex != -1) {
      final combo = cats.removeAt(comboIndex);
      cats.insert(0, combo);
    } else {
      // Create a synthesized 'Combo' category if not present
      cats.insert(0, ServiceCategory(id: 'combo', name: 'Combo'));
    }
    return cats;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allCats = _getProcessedCategories();

    if (allCats.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          const gap = 12.0;
          
          if (_pageController == null || _lastWidth != availableWidth) {
            _lastWidth = availableWidth;
            final stride = (availableWidth + gap) / 4;
            final fraction = stride / availableWidth;
            final len = allCats.isNotEmpty ? allCats.length : 1;
            final base = 10000;
            final defaultPage = base - (base % len);
            
            final initial = _currentPage ?? defaultPage;
            
            final old = _pageController;
            _pageController = PageController(
              initialPage: initial,
              viewportFraction: fraction,
            );
            if (old != null) {
              Future.microtask(() => old.dispose());
            }
          }

          final stride = (availableWidth + gap) / 4;
          final actualTileWidth = stride - gap;
          final itemHeight = actualTileWidth + 7 + 32;

          return SizedBox(
            height: itemHeight,
            child: PageView.builder(
              controller: _pageController,
              padEnds: false,
              onPageChanged: (index) {
                _currentPage = index;
              },
              itemBuilder: (context, index) {
                final realIndex = index % allCats.length;
                final category = allCats[realIndex];

                return Padding(
                  padding: const EdgeInsets.only(right: gap),
                  child: _CategoryTile(
                    category: category,
                    tint: _tints[realIndex % _tints.length],
                    isDark: isDark,
                    onTap: () => widget.onTap(category),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ServiceCategory category;
  final (Color, Color) tint;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryTile({
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
            // Square, so every tile lines up however wide the screen is.
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? foreground.withOpacity(0.16) : background,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.all(14),
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
              color: isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading,
            ),
          ),
        ],
      ),
    );
  }
}
