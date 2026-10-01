import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/salon_service.dart';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../services/review_service.dart';
import 'phone_screen.dart';
import 'cart_screen.dart';
import 'salon_reviews_screen.dart';
import '../widgets/cart_offers.dart';
import '../widgets/initials_avatar.dart';
import '../widgets/rating_bars.dart';
import '../utils/app_haptics.dart';
import '../theme/app_colors.dart';
import '../utils/error_text.dart';
import '../widgets/feedback_states.dart';
import '../widgets/skeleton.dart';

/// Which reviews the inline Ratings & reviews preview is showing.
enum _ReviewFilter { topRated, five, fourPlus, threePlus }

class SalonDetailScreen extends StatefulWidget {
  final String salonId;

  /// Optional discovery context. When a customer lands here from a category
  /// (e.g. Nails → a salon), the page opens on that category's services so the
  /// salon never immediately shows unrelated categories. [serviceId] is the
  /// catalogue service template that was picked, used to highlight and reveal
  /// the exact service card (when the salon offers it); a template name match
  /// is never used — only the real template_id carried by each service row.
  final String? categoryId;
  final String? categoryName;
  final String? serviceId;

  const SalonDetailScreen({
    Key? key,
    required this.salonId,
    this.categoryId,
    this.categoryName,
    this.serviceId,
  }) : super(key: key);

  @override
  State<SalonDetailScreen> createState() => _SalonDetailScreenState();
}

class _SalonDetailScreenState extends State<SalonDetailScreen> {
  final SalonService _salonService = SalonService();
  final CartService _cartService = CartService();
  final PageController _galleryController = PageController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _reviewsKey = GlobalKey();

  Map<String, dynamic>? _salon;
  Map<String, dynamic>? _cart;
  bool _isLoading = true;
  String _error = '';
  bool _isFavourited = false;
  bool _isTogglingFavourite = false;

  /// null = the "All Services" tab.
  String? _selectedCategoryId;
  int _galleryPage = 0;
  bool _hoursExpanded = false;

  /// The exact template a discovery sub-service pick points at, so its card (if
  /// this salon offers it) can be visibly highlighted. Matched against the
  /// real `template_id` on each service row — never by name.
  String? _highlightServiceId;
  final GlobalKey _highlightServiceKey = GlobalKey();

  /// The real review list for the inline filters, loaded through the same
  /// existing /salons/{id}/reviews pipeline the full review page uses. The
  /// salon detail payload only carries a 3-review preview.
  final List<dynamic> _allReviews = [];
  _ReviewFilter _reviewFilter = _ReviewFilter.topRated;

  static const int _maxInlineReviews = 5;

  @override
  void initState() {
    super.initState();
    _loadSalonDetails();
    _loadCart();
    _loadAllReviews();
  }

  @override
  void dispose() {
    _galleryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Pages through the existing review endpoint until every real review is
  /// in hand, so the star capsules filter the complete dataset, not a preview.
  Future<void> _loadAllReviews() async {
    final collected = <dynamic>[];
    try {
      var page = 1;
      while (page <= 50) {
        final body = await ReviewService.forSalon(widget.salonId, page: page);
        if (body == null) break;
        collected.addAll(body['reviews'] as List? ?? const []);
        final meta = body['meta'] as Map?;
        if (meta?['has_more'] != true) break;
        page++;
      }
    } catch (_) {
      // The preview still renders below if this cannot load.
    }
    if (!mounted) return;
    setState(() {
      _allReviews
        ..clear()
        ..addAll(collected);
    });
  }

  /// The reviews the active capsule selects, from the real data only.
  List<dynamic> get _filteredReviews {
    final all = _allReviews;
    switch (_reviewFilter) {
      case _ReviewFilter.five:
        return all.where((r) => (r['rating'] as num?)?.toInt() == 5).toList();
      case _ReviewFilter.fourPlus:
        return all.where((r) => ((r['rating'] as num?)?.toInt() ?? 0) >= 4).toList();
      case _ReviewFilter.threePlus:
        return all.where((r) => ((r['rating'] as num?)?.toInt() ?? 0) >= 3).toList();
      case _ReviewFilter.topRated:
        final rated = all.where((r) => (r['rating'] as num?) != null).toList();
        rated.sort((a, b) => (b['rating'] as num).compareTo(a['rating'] as num));
        return rated;
    }
  }

  /// Smoothly brings the Ratings & reviews section into view, past the pinned
  /// app bar. The reviews sliver is lazy, so if it is not built yet we first
  /// take the scroll to the bottom to force its layout before aligning.
  Future<void> _scrollToReviews() async {
    if (!_scrollController.hasClients) return;
    try {
      if (_reviewsKey.currentContext == null) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        await WidgetsBinding.instance.endOfFrame;
      }
      final ctx = _reviewsKey.currentContext;
      if (ctx == null) return;
      final viewport = _scrollController.position.viewportDimension;
      final toolbar = MediaQuery.of(context).padding.top + kToolbarHeight;
      final alignment = (toolbar / viewport).clamp(0.0, 0.5).toDouble();
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        alignment: alignment,
      );
    } catch (_) {}
  }

  Future<void> _revealHighlightedService() async {
    if (!_scrollController.hasClients || _highlightServiceId == null) return;
    try {
      // The service list is a lazy sliver, so the highlighted card may not be
      // built yet. Nudge forward a screen until its key materialises, then
      // bring it into view just below the pinned app bar (best effort).
      for (var attempt = 0; attempt < 6; attempt++) {
        final ctx = _highlightServiceKey.currentContext;
        if (ctx != null) {
          final viewport = _scrollController.position.viewportDimension;
          final toolbar = MediaQuery.of(context).padding.top + kToolbarHeight;
          final alignment = (toolbar / viewport).clamp(0.0, 0.5).toDouble();
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            alignment: alignment,
          );
          return;
        }
        _scrollController.jumpTo(
          (_scrollController.offset + 600)
              .clamp(0.0, _scrollController.position.maxScrollExtent),
        );
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (_) {}
  }

  Future<void> _loadSalonDetails() async {
    setState(() => _error = '');
    try {
      final data = await _salonService.fetchSalonDetails(widget.salonId);
      if (!mounted) return;
      setState(() {
        _salon = data;
        _isFavourited = data['is_favourited'] == true;
        // Land on the category the customer came in through, so unrelated
        // categories stay out of the way until they switch tabs themselves.
        _selectedCategoryId = widget.categoryId;
        _highlightServiceId = widget.serviceId;
        _isLoading = false;
      });
      if (widget.serviceId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _revealHighlightedService());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e, fallback: 'We could not load this salon.');
        _isLoading = false;
      });
    }
  }

  /// Keeps the sticky bottom bar's running total in sync.
  Future<void> _loadCart() async {
    try {
      final cart = await _cartService.getGlobalCart();
      if (!mounted) return;
      setState(() => _cart = cart);
    } catch (_) {
      // A failed cart read should never block the salon page.
    }
  }

  Future<void> _toggleFavourite() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => const PhoneScreen(isModal: true)),
      );
      if (loggedIn != true) return;
    }

    if (_isTogglingFavourite) return;
    setState(() => _isTogglingFavourite = true);
    
    try {
      final isFavourited = await _salonService.toggleFavourite(widget.salonId);
      if (!mounted) return;
      AppHaptics.lightImpact();
      setState(() {
        _isFavourited = isFavourited;
        _actionError = null;
      });
      _toast(isFavourited ? 'Salon added to favourites' : 'Salon removed from favourites');
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _showError(describeError(e, fallback: 'Could not update your favourites.'));
    } finally {
      if (mounted) {
        setState(() => _isTogglingFavourite = false);
      }
    }
  }

  Future<void> _addToCart({String? serviceId, String? comboId, required String label}) async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => const PhoneScreen(isModal: true)),
      );
      if (loggedIn != true) return;
    }

    try {
      final cart = serviceId != null
          ? await _cartService.addItem(widget.salonId, serviceId)
          : await _cartService.addCombo(widget.salonId, comboId!);

      if (!mounted) return;

      AppHaptics.lightImpact();
      setState(() {
        _cart = cart;
        _actionError = null;
      });

      // The moment after adding is when a package nudge is worth anything, so
      // it is shown here rather than waiting for the cart screen.
      if (!_showOffersFor(cart, label)) {
        _toast('$label added to cart');
      }
    } on CartConflictException catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Replace cart items?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: Text(
            'Your cart contains items from ${e.otherSalonName}. Do you want to discard that selection and add items from this salon?',
            style: GoogleFonts.outfit(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                AppHaptics.lightImpact();
                Navigator.pop(ctx);
              },
              child: Text('Cancel', style: GoogleFonts.outfit(color: context.colors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                AppHaptics.lightImpact();
                Navigator.pop(ctx);
                await _cartService.clearGlobalCart();
                _addToCart(serviceId: serviceId, comboId: comboId, label: label);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
              child: Text('Replace', style: GoogleFonts.outfit(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _showError(describeError(e, fallback: 'Could not add that to your cart.'));
    }
  }

  Future<void> _openCart() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => CartScreen()));
    _loadCart();
  }

  /// Surfaces what the add unlocked. Returns true when something was shown, so
  /// the caller does not also fire a plain confirmation.
  bool _showOffersFor(Map<String, dynamic>? cart, String label) {
    if (cart == null) return false;

    final applied = (cart['applied_combos'] as List?) ?? const [];
    final offers = (cart['combo_offers'] as List?) ?? const [];
    final saving = _toDouble((cart['summary'] as Map<String, dynamic>?)?['saving']);

    // Completing a package is the better news, so it wins.
    if (applied.isNotEmpty && saving > 0) {
      final names = applied
          .map((c) => (c as Map<String, dynamic>)['name'] ?? 'Package')
          .join(', ');

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: context.colors.success,
        duration: const Duration(seconds: 4),
        content: Text(
          'That completes "$names" — you save ₹${saving.toStringAsFixed(0)}',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
      ));
      return true;
    }

    if (offers.isNotEmpty) {
      _showComboOfferSheet(offers.first as Map<String, dynamic>, label);
      return true;
    }

    return false;
  }

  /// A near-miss package, shown as a sheet so the missing services can be added
  /// without leaving the salon page.
  void _showComboOfferSheet(Map<String, dynamic> offer, String label) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: context.colors.surfaceMuted,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: EdgeInsets.only(bottom: 14),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('$label added',
                  style: GoogleFonts.outfit(
                      fontSize: 15, color: context.colors.textSecondary)),
              SizedBox(height: 14),
              ComboOfferCard(
                offer: offer,
                onAddService: (serviceId) async {
                  Navigator.pop(sheetContext);
                  await _addToCart(serviceId: serviceId, label: 'Service');
                },
                onCompletePackage: (serviceIds) async {
                  Navigator.pop(sheetContext);
                  await _addMany(serviceIds);
                },
              ),
              SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text('No thanks',
                    style: GoogleFonts.outfit(color: context.colors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Adds every remaining service of a package in one go.
  Future<void> _addMany(List<String> serviceIds) async {
    Map<String, dynamic>? cart;

    try {
      for (final id in serviceIds) {
        cart = await _cartService.addItem(widget.salonId, id);
      }
    } catch (e) {
      AppHaptics.error();
      _showError(describeError(e, fallback: 'Could not add the whole package to your cart.'));
      await _loadCart();
      return;
    }

    if (!mounted) return;
    setState(() {
      _cart = cart;
      _actionError = null;
    });
    _showOffersFor(cart, 'Package');
  }

  /// Confirmations only ("added to cart", favourites): passing news.
  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: Duration(seconds: 2)),
    );
  }

  /// A failed favourite or add-to-cart, docked above the cart bar until
  /// dismissed or the next success. Part of the layout rather than a
  /// SnackBar, so it neither vanishes unread nor covers the cart bar.
  String? _actionError;

  void _showError(String text) {
    if (!mounted) return;
    setState(() => _actionError = text);
  }

  /// The docked area: the action error, if any, above the cart bar.
  Widget? _buildBottomArea() {
    final bar = _buildStickyBar();
    final error = _actionError;
    if (error == null) return bar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          top: false,
          bottom: bar == null,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bar == null ? 12 : 8),
            child: InlineStatus(
              message: error,
              onDismiss: () => setState(() => _actionError = null),
            ),
          ),
        ),
        if (bar != null) bar,
      ],
    );
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  bool get _isBookable => _salon?['is_bookable'] == true;

  List<dynamic> get _visibleServices {
    final services = (_salon?['services'] as List?) ?? [];
    if (_selectedCategoryId == null) return services;
    return services.where((s) => s['category_id'] == _selectedCategoryId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = context.colors.surfaceMuted;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const SalonDetailSkeleton(),
      );
    }

    if (_error.isNotEmpty || _salon == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(backgroundColor: bgColor, elevation: 0),
        body: _error.isNotEmpty
            ? ErrorState(
                title: 'Could not load this salon',
                message: _error,
                onRetry: () {
                  setState(() => _isLoading = true);
                  _loadSalonDetails();
                },
              )
            : EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Salon not found',
                message: 'It may have closed or stopped taking bookings.',
                actionLabel: 'Go back',
                onAction: () => Navigator.maybePop(context),
              ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: RefreshIndicator(
        color: AppTheme.accentColor,
        onRefresh: () async {
          await _loadSalonDetails();
          await _loadCart();
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(child: _buildHeaderCard()),
            SliverToBoxAdapter(child: _buildNotices()),
            SliverToBoxAdapter(child: _buildHoursPanel()),
            SliverToBoxAdapter(child: _buildCombos()),
            SliverToBoxAdapter(child: _buildCategoryTabs()),
            _buildServiceSliver(),
            SliverToBoxAdapter(child: _buildTeam()),
            SliverToBoxAdapter(key: _reviewsKey, child: _buildReviews()),
            SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomArea(),
    );
  }

  // ---------------------------------------------------------------- app bar

  Widget _buildAppBar() {
    final gallery = (_salon!['gallery'] as List?) ?? [];

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: context.colors.surface,
      foregroundColor: context.colors.textPrimary,
      elevation: 0,
      title: Text(_salon!['name'] ?? 'Salon',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
      leading: Padding(
        padding: const EdgeInsets.only(left: 12.0, top: 6.0, bottom: 6.0),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Container(
            width: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: _isFavourited ? 'Remove from favourites' : 'Add to favourites',
              icon: Icon(_isFavourited ? Icons.favorite : Icons.favorite_border, size: 20),
              color: _isFavourited ? Colors.redAccent : Colors.white,
              onPressed: _toggleFavourite,
            ),
          ),
        ),
        SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Container(
            width: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: 'Open cart',
              icon: Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 20),
              onPressed: _openCart,
            ),
          ),
        ),
        SizedBox(width: 16),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (gallery.isEmpty)
              _galleryPlaceholder()
            else
              PageView.builder(
                controller: _galleryController,
                itemCount: gallery.length,
                onPageChanged: (i) => setState(() => _galleryPage = i),
                itemBuilder: (context, index) => Image.network(
                  gallery[index]['url'] ?? '',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _galleryPlaceholder(),
                ),
              ),

            // Scrim so the chips and the pinned title stay readable.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),

            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _glassChip(_salon!['gender_focus'] ?? 'Unisex'),
                  _buildRatingPill(),
                ],
              ),
            ),

            if (gallery.length > 1)
              Positioned(
                bottom: 6,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    gallery.length,
                    (i) => AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      margin: EdgeInsets.symmetric(horizontal: 3),
                      width: _galleryPage == i ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: _galleryPage == i ? 1 : 0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _galleryPlaceholder() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.accentGradientLightEnd, AppTheme.accentGradientEnd],
          ),
        ),
        child: Center(child: Icon(Icons.storefront, size: 90, color: Colors.white.withValues(alpha: 0.45))),
      );

  Widget _glassChip(String text) => Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _buildRatingPill() {
    final rating = _salon!['rating'] ?? {};
    final count = (rating['count'] ?? 0) as int;
    final average = _toDouble(rating['average']);

    return GestureDetector(
      onTap: count > 0 ? _scrollToReviews : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: count > 0 ? context.colors.success : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, color: Colors.white, size: 15),
            SizedBox(width: 4),
            Text(
              count > 0 ? '${average.toStringAsFixed(1)} ($count)' : 'New',
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            if (count > 0) ...[
              SizedBox(width: 3),
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 15),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- header

  Widget _buildHeaderCard() {
    final isOpen = _salon!['is_open_now'] == true;
    final address = [_salon!['address'], _salon!['city'], _salon!['pincode']]
        .where((part) => part != null && '$part'.isNotEmpty)
        .join(', ');

    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_salon!['name'] ?? 'Salon',
              style: GoogleFonts.outfit(
                  fontSize: 22, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
          SizedBox(height: 10),

          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOpen ? context.colors.success : context.colors.danger,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  _salon!['open_status_label'] ?? '',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isOpen ? context.colors.success : context.colors.danger,
                  ),
                ),
              ),
            ],
          ),

          if (address.isNotEmpty) ...[
            SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined, size: 18, color: context.colors.textSecondary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(address,
                      style: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary)),
                ),
              ],
            ),
          ],

          // The salon's phone is the owner's personal number — never surfaced
          // to customers. The description takes its place here.
          if ((_salon!['description'] ?? '').toString().isNotEmpty) ...[
            SizedBox(height: 14),
            Text(_salon!['description'],
                style: GoogleFonts.outfit(fontSize: 14, height: 1.5, color: context.colors.textSecondary)),
          ],

          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _statTile(
                Icons.spa_outlined,
                '${(_salon!['services'] as List?)?.length ?? 0}',
                'Services',
              )),
              Expanded(child: _statTile(
                Icons.people_outline,
                '${(_salon!['team'] as List?)?.length ?? 0}',
                'Staff',
              )),
              Expanded(child: _statTile(
                Icons.percent,
                '${_toDouble(_salon!['advance_percentage_default']).toStringAsFixed(0)}%',
                'Advance',
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.accentColor),
        SizedBox(height: 6),
        Text(value,
            style: GoogleFonts.outfit(
                fontSize: 16, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
        Text(label, style: GoogleFonts.outfit(fontSize: 12, color: context.colors.textTertiary)),
      ],
    );
  }

  // ---------------------------------------------------------------- notices

  Widget _buildNotices() {
    final closures = (_salon!['upcoming_closures'] as List?) ?? [];

    return Column(
      children: [
        if (!_isBookable)
          _noticeBox(
            icon: Icons.event_busy,
            color: context.colors.danger,
            background: context.colors.dangerBg,
            title: 'Temporarily unavailable',
            body: _salon!['unavailable_reason'] ??
                'This salon is not accepting online bookings right now.',
          ),
        if (closures.isNotEmpty)
          _noticeBox(
            icon: Icons.info_outline,
            color: context.colors.warning,
            background: context.colors.warningBg,
            title: 'Closed on ${closures.map((c) => c['label']).join(', ')}',
            body: 'Pick another date for these days when you book.',
          ),
      ],
    );
  }

  Widget _noticeBox({
    required IconData icon,
    required Color color,
    required Color background,
    required String title,
    required String body,
  }) =>
      Container(
        width: double.infinity,
        margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.outfit(
                          fontSize: 14, fontWeight: FontWeight.bold, color: color)),
                  SizedBox(height: 2),
                  Text(body, style: GoogleFonts.outfit(fontSize: 13, color: color)),
                ],
              ),
            ),
          ],
        ),
      );

  // ------------------------------------------------------------------ hours

  Widget _buildHoursPanel() {
    final week = (_salon!['working_hours'] as List?) ?? [];
    if (week.isEmpty) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: _cardDecoration(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _hoursExpanded,
          onExpansionChanged: (v) => setState(() => _hoursExpanded = v),
          tilePadding: EdgeInsets.symmetric(horizontal: 20),
          childrenPadding: EdgeInsets.fromLTRB(20, 0, 20, 16),
          leading: Icon(Icons.schedule, color: AppTheme.accentColor),
          title: Text('Opening hours',
              style: GoogleFonts.outfit(
                  fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.textPrimary)),
          children: week.map<Widget>((day) {
            final isToday = day['is_today'] == true;
            final closed = day['is_closed'] == true;

            return Padding(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(day['day_name'],
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday ? AppTheme.accentColor : context.colors.textSecondary,
                      )),
                  Text(
                    closed ? 'Closed' : '${day['open_time']} – ${day['close_time']}',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: closed
                          ? context.colors.textTertiary
                          : (isToday ? AppTheme.accentColor : context.colors.textPrimary),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- combos

  Widget _buildCombos() {
    final combos = (_salon!['combos'] as List?) ?? [];
    if (combos.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Value packages', 'Bundled services at a lower price'),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: combos.length,
            separatorBuilder: (_, __) => SizedBox(width: 12),
            itemBuilder: (context, index) => _comboCard(combos[index]),
          ),
        ),
      ],
    );
  }

  Widget _comboCard(Map<String, dynamic> combo) {
    final savings = _toDouble(combo['savings']);
    final lines = (combo['services'] as List?) ?? [];
    
    final bgColor = context.colors.accentSoft;
    final borderColor = context.colors.accentSoftHover;
    final textHeading = context.colors.textPrimary;
    final textBody = context.colors.textSecondary;
    final textLight = context.colors.textTertiary;

    return Container(
      width: 280,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(combo['name'] ?? 'Package',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.bold, color: textHeading)),
              ),
              if (savings > 0)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colors.success,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('SAVE ₹${savings.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text('${combo['duration_minutes']} mins · ${lines.length} services',
              style: GoogleFonts.outfit(fontSize: 13, color: textBody)),
          SizedBox(height: 14),
          Expanded(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: lines
                  .take(4)
                  .map<Widget>((line) => Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_circle, size: 14, color: AppTheme.accentColor),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(line['name'] ?? '',
                                  style: GoogleFonts.outfit(
                                      fontSize: 13, color: textBody, height: 1.3)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (savings > 0)
                    Text('₹${_toDouble(combo['original_price']).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: textLight,
                          decoration: TextDecoration.lineThrough,
                        )),
                  Text('₹${_toDouble(combo['price']).toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                ],
              ),
              _addButton(
                enabled: _isBookable,
                onTap: () => _addToCart(comboId: combo['id'].toString(), label: combo['name'] ?? 'Package'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- categories

  Widget _buildCategoryTabs() {
    final categories = (_salon!['categories'] as List?) ?? [];
    final allCount = (_salon!['services'] as List?)?.length ?? 0;

    if (allCount == 0) return _sectionHeader('Services', 'Nothing published yet');

    final tabs = <Map<String, dynamic>>[
      {'id': null, 'name': 'All Services', 'service_count': allCount},
      ...categories.cast<Map<String, dynamic>>(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Services', 'Tap add to build your booking'),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: tabs.length,
            separatorBuilder: (_, __) => SizedBox(width: 4),
            itemBuilder: (context, index) {
              final tab = tabs[index];
              final isSelected = _selectedCategoryId == tab['id'];
              final textColor = isSelected 
                  ? AppTheme.accentColor 
                  : (context.colors.textSecondary);

              return GestureDetector(
                onTap: () => setState(() => _selectedCategoryId = tab['id'] as String?),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(
                        '${tab['name']} (${tab['service_count']})',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      height: 3,
                      width: isSelected ? 32 : 0,
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(height: 12),
      ],
    );
  }

  // ---------------------------------------------------------------- services

  Widget _buildServiceSliver() {
    final services = _visibleServices;

    if (services.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: Text('No services in this category.',
                style: GoogleFonts.outfit(color: context.colors.textTertiary)),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _serviceCard(services[index]),
        ),
        childCount: services.length,
      ),
    );
  }

  Widget _serviceCard(Map<String, dynamic> service) {
    final hasStaff = (service['provider_count'] ?? 0) > 0;
    final canAdd = _isBookable && hasStaff;
    final description = (service['description'] ?? '').toString();

    // Highlight came-from-category service: matched on the real template_id so
    // the salon + service relationship stays exact, never a name guess.
    final isHighlighted = _highlightServiceId != null &&
        service['template_id']?.toString() == _highlightServiceId;

    return Opacity(
      opacity: canAdd ? 1.0 : 0.6,
      child: Container(
        key: isHighlighted ? _highlightServiceKey : null,
        padding: EdgeInsets.all(20),
        decoration: _cardDecoration(
          accentBorder: isHighlighted,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isHighlighted)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.touch_app, size: 13, color: AppTheme.accentColor),
                    const SizedBox(width: 5),
                    Text(
                      widget.categoryName ?? 'From category',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: context.colors.accentSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.spa_outlined, color: AppTheme.accentColor, size: 28),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service['name'] ?? 'Service',
                          style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: context.colors.textPrimary)),
                      SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _metaChip(Icons.access_time, '${service['duration_minutes']} mins'),
                          if (service['gender_focus'] != null &&
                              service['gender_focus'] != 'Unisex')
                            _metaChip(Icons.person_outline, service['gender_focus']),
                          if (service['refundable_advance'] == true)
                            _metaChip(Icons.replay, 'Refundable advance'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (description.isNotEmpty) ...[
              SizedBox(height: 16),
              Text(description,
                  style: GoogleFonts.outfit(
                      fontSize: 14, height: 1.5, color: context.colors.textSecondary)),
            ],

            if (!hasStaff) ...[
              SizedBox(height: 12),
              Text('No staff available for this service right now',
                  style: GoogleFonts.outfit(fontSize: 13, color: context.colors.danger)),
            ],

            SizedBox(height: 16),
            Divider(color: context.colors.border, height: 1),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹${_toDouble(service['price']).toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                        fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.accentColor)),
                _addButton(
                  enabled: canAdd,
                  onTap: () => _addToCart(
                    serviceId: service['id'].toString(),
                    label: service['name'] ?? 'Service',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.colors.textSecondary),
          SizedBox(width: 6),
          Text(text, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500, color: context.colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _addButton({required bool enabled, required VoidCallback onTap}) {
    return ElevatedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(Icons.add, size: 18),
      label: Text('ADD', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accentColor,
        foregroundColor: Colors.white,
        disabledBackgroundColor: context.colors.border,
        disabledForegroundColor: context.colors.textTertiary,
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // -------------------------------------------------------------------- team

  Widget _buildTeam() {
    final team = (_salon!['team'] as List?) ?? [];
    if (team.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Meet the team', 'Choose your stylist at checkout'),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: team.length,
            separatorBuilder: (_, __) => SizedBox(width: 12),
            itemBuilder: (context, index) {
              final member = team[index];
              final name = (member['name'] ?? 'Staff').toString();

              return Container(
                width: 108,
                padding: EdgeInsets.all(12),
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: context.colors.accentSoft,
                      child: Text(
                        InitialsAvatar.initialsOf(name),
                        style: GoogleFonts.outfit(
                            fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary)),
                    SizedBox(height: 2),
                    Text(
                      member['specialization'] ?? '${member['service_count']} services',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(fontSize: 11, color: context.colors.textTertiary),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- reviews

  Widget _buildReviews() {
    final rating = Map<String, dynamic>.from((_salon!['rating'] as Map?) ?? {});
    final count = (rating['count'] as num?)?.toInt() ?? 0;
    final recent = (rating['recent'] as List?) ?? const [];

    // The complete real list is loaded through the existing reviews endpoint
    // so the capsules can filter the full dataset. Until it loads (or if it
    // fails), the original newest-three preview is what the page shows — the
    // section never becomes empty or fake.
    final hasFullList = _allReviews.isNotEmpty;
    final filtered = hasFullList ? _filteredReviews : const <dynamic>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Ratings & reviews', count > 0 ? '$count customer ratings' : null),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: RatingSummaryCard(summary: rating),
        ),

        if (hasFullList) ...[
          SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _buildReviewFilterCapsules(),
          ),
        ],

        // A preview only. The full list is its own page — a salon page should
        // not carry four hundred reviews to show the newest three.
        if (hasFullList && filtered.isEmpty) ...[
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _buildNoFilteredReviews(),
          ),
        ] else if (hasFullList) ...[
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final review in filtered.take(_maxInlineReviews))
                  ReviewTile(review: Map<String, dynamic>.from(review as Map)),
              ],
            ),
          ),
        ] else if (recent.isNotEmpty) ...[
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final review in recent)
                  ReviewTile(review: Map<String, dynamic>.from(review as Map)),
              ],
            ),
          ),
        ],

        if (count > 0) ...[
          SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SalonReviewsScreen(
                      salonId: widget.salonId,
                      salonName: _salon!['name']?.toString() ?? 'Salon',
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentColor,
                  padding: EdgeInsets.symmetric(vertical: 13),
                  side: BorderSide(color: context.colors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  count == 1 ? 'See the 1 review' : 'See all $count reviews',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReviewFilterCapsules() {
    final borderColor = context.colors.border;
    final idleBg = context.colors.surface;
    final idleText = context.colors.textSecondary;

    Widget pill(_ReviewFilter filter, String label) {
      final selected = _reviewFilter == filter;
      return GestureDetector(
        onTap: () {
          AppHaptics.selectionClick();
          setState(() => _reviewFilter = filter);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentColor : idleBg,
            borderRadius: BorderRadius.circular(999),
            border: selected ? null : Border.all(color: borderColor, width: 1.2),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : idleText,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => switch (index) {
          0 => pill(_ReviewFilter.topRated, 'Top Rated'),
          1 => pill(_ReviewFilter.five, '5 ★'),
          2 => pill(_ReviewFilter.fourPlus, '4+ ★'),
          _ => pill(_ReviewFilter.threePlus, '3+ ★'),
        },
      ),
    );
  }

  Widget _buildNoFilteredReviews() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.border),
      ),
      child: Text(
        'No reviews found',
        textAlign: TextAlign.center,
        style: GoogleFonts.outfit(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }

  // ------------------------------------------------------------- sticky bar

  /// Price of one cart line. A combo is priced from its own special prices,
  /// not from the member services' list prices.
  double _lineTotal(dynamic item) {
    final quantity = (item['quantity'] ?? 1) as int;

    if (item['combo'] != null) {
      double comboPrice = 0;
      for (final service in (item['combo']['services'] as List? ?? [])) {
        comboPrice += _toDouble(service['pivot']?['combo_special_price'] ?? service['price']);
      }
      return comboPrice * quantity;
    }

    if (item['service'] != null) {
      return _toDouble(item['service']['price']) * quantity;
    }

    return 0;
  }

  /// Running total for the doc's sticky "View Cart" bar. Only counts a cart
  /// that belongs to this salon.
  Widget? _buildStickyBar() {
    final items = (_cart?['items'] as List?) ?? [];
    if (_cart == null || items.isEmpty) return null;
    if (_cart!['salon_id'].toString() != widget.salonId) return null;

    // The server sends the figures the booking will actually charge; only fall
    // back to a local sum if an older API build leaves them out.
    final summary = _cart!['summary'] as Map<String, dynamic>?;

    double total = 0;
    int count = 0;
    for (final item in items) {
      count += (item['quantity'] ?? 1) as int;
      total += _lineTotal(item);
    }

    double listTotal = total;
    double saving = 0;

    if (summary != null) {
      total = _toDouble(summary['total_amount']);
      listTotal = _toDouble(summary['list_total']);
      saving = _toDouble(summary['saving']);
      count = (summary['item_count'] ?? count) as int;
    }

    final colors = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: colors.prefersOutline ? Border(top: BorderSide(color: colors.raisedOutline)) : null,
        boxShadow: [
          if (!colors.prefersOutline)
            BoxShadow(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), offset: Offset(0, -4), blurRadius: 20),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count ${count == 1 ? 'item' : 'items'}',
                    style: GoogleFonts.outfit(fontSize: 12, color: context.colors.textSecondary)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${total.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: context.colors.textPrimary)),
                    if (saving > 0) ...[
                      SizedBox(width: 6),
                      Padding(
                        padding: EdgeInsets.only(bottom: 3),
                        child: Text('₹${listTotal.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: context.colors.textTertiary,
                              decoration: TextDecoration.lineThrough,
                            )),
                      ),
                    ],
                  ],
                ),
                if (saving > 0)
                  Text('Package saving ₹${saving.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.colors.success)),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _openCart,
              icon: Icon(Icons.shopping_cart, size: 18),
              label: Text('View Cart',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ shared

  Widget _sectionHeader(String title, String? subtitle) => Padding(
        padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.outfit(
                    fontSize: 20, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
            if (subtitle != null) ...[
              SizedBox(height: 2),
              Text(subtitle,
                  style: GoogleFonts.outfit(fontSize: 13, color: context.colors.textTertiary)),
            ],
          ],
        ),
      );

  BoxDecoration _cardDecoration({bool accentBorder = false}) {
    return BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(24),
      border: accentBorder
          ? Border.all(color: AppTheme.accentColor, width: 1.8)
          : Border.all(color: context.colors.border),
      boxShadow: accentBorder
          ? [
              BoxShadow(
                color: AppTheme.accentColor.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ]
          : [
              BoxShadow(color: context.colors.cardShadow, blurRadius: 16, offset: Offset(0, 4)),
            ],
    );
  }
}
