import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/salon_service.dart';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../services/review_service.dart';
import 'phone_screen.dart';
import 'cart_screen.dart';
import 'salon_reviews_screen.dart';
import '../widgets/initials_avatar.dart';
import '../widgets/rating_bars.dart';
import '../utils/app_haptics.dart';
import '../theme/app_colors.dart';
import '../utils/error_text.dart';
import '../widgets/feedback_states.dart';
import '../widgets/skeleton.dart';
import '../widgets/discount_badge.dart';
import '../widgets/flipping_savings_badge.dart';

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

  final bool initialScrollToServices;

  const SalonDetailScreen({
    Key? key,
    required this.salonId,
    this.categoryId,
    this.categoryName,
    this.serviceId,
    this.initialScrollToServices = false,
  }) : super(key: key);

  @override
  State<SalonDetailScreen> createState() => _SalonDetailScreenState();
}

class _SalonDetailScreenState extends State<SalonDetailScreen> {
  final SalonService _salonService = SalonService();
  final CartService _cartService = CartService();
  final PageController _galleryController = PageController();
  late final ScrollController _scrollController;
  final GlobalKey _reviewsKey = GlobalKey();
  final GlobalKey _categoryTabsKey = GlobalKey();
  final GlobalKey _combosKey = GlobalKey();
  final ScrollController _categoryTabsScrollController = ScrollController();

  Map<String, dynamic>? _salon;
  Map<String, dynamic>? _cart;
  bool _isLoading = true;
  String _error = '';
  bool _isFavourited = false;
  bool _isTogglingFavourite = false;
  final Set<String> _inFlightServiceIds = {};

  /// null = the "All Services" tab.
  String? _selectedCategoryId;
  bool _hoursExpanded = false;
  bool _isServicesExpanded = false;

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
    final shouldScrollToServices = widget.initialScrollToServices ||
        (widget.categoryId != null && widget.categoryId!.isNotEmpty) ||
        (widget.categoryName != null && widget.categoryName!.isNotEmpty);
    _scrollController = ScrollController(
      initialScrollOffset: shouldScrollToServices ? 380.0 : 0.0,
    );
    _loadSalonDetails();
    _loadCart();
    _loadAllReviews();
    CartService.globalCartNotifier.addListener(_onGlobalCartChanged);
  }

  @override
  void dispose() {
    CartService.globalCartNotifier.removeListener(_onGlobalCartChanged);
    _galleryController.dispose();
    _scrollController.dispose();
    _categoryTabsScrollController.dispose();
    super.dispose();
  }

  void _onGlobalCartChanged() {
    if (!mounted) return;
    setState(() {
      _cart = CartService.globalCartNotifier.value;
    });
  }

  int _getServiceQuantity(dynamic serviceId) {
    if (_cart == null) return 0;
    final items = (_cart!['items'] as List?) ?? const [];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final sId = item['service_id'] ?? item['service']?['id'];
        if (sId != null && sId.toString() == serviceId.toString()) {
          return (item['quantity'] as num?)?.toInt() ?? 1;
        }
      }
    }
    return 0;
  }

  Map<String, dynamic>? _getServiceCartItem(dynamic serviceId) {
    if (_cart == null) return null;
    final items = (_cart!['items'] as List?) ?? const [];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final sId = item['service_id'] ?? item['service']?['id'];
        if (sId != null && sId.toString() == serviceId.toString()) {
          return item;
        }
      }
    }
    return null;
  }

  int _getComboQuantity(dynamic comboId) {
    if (_cart == null) return 0;
    final items = (_cart!['items'] as List?) ?? const [];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final cId = item['combo_id'] ?? item['combo']?['id'];
        if (cId != null && cId.toString() == comboId.toString()) {
          return (item['quantity'] as num?)?.toInt() ?? 1;
        }
      }
    }
    return 0;
  }

  Map<String, dynamic>? _getComboCartItem(dynamic comboId) {
    if (_cart == null) return null;
    final items = (_cart!['items'] as List?) ?? const [];
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final cId = item['combo_id'] ?? item['combo']?['id'];
        if (cId != null && cId.toString() == comboId.toString()) {
          return item;
        }
      }
    }
    return null;
  }

  int get _cartItemCount {
    if (_cart == null) return 0;
    final items = (_cart!['items'] as List?) ?? const [];
    int count = 0;
    for (final item in items) {
      if (item is Map) {
        count += (item['quantity'] as num?)?.toInt() ?? 1;
      }
    }
    return count;
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
        return all
            .where((r) => ((r['rating'] as num?)?.toInt() ?? 0) >= 4)
            .toList();
      case _ReviewFilter.threePlus:
        return all
            .where((r) => ((r['rating'] as num?)?.toInt() ?? 0) >= 3)
            .toList();
      case _ReviewFilter.topRated:
        final rated = all.where((r) => (r['rating'] as num?) != null).toList();
        rated.sort(
          (a, b) => (b['rating'] as num).compareTo(a['rating'] as num),
        );
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
          (_scrollController.offset + 600).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
        );
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (_) {}
  }

  Future<void> _scrollToServicesSection() async {
    if (!_scrollController.hasClients) return;
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final isComboCategory = widget.categoryId == 'combo' ||
          (widget.categoryName?.toLowerCase() == 'combo');
      final targetKey = isComboCategory ? _combosKey : _categoryTabsKey;

      for (var attempt = 0; attempt < 5; attempt++) {
        if (targetKey.currentContext != null && mounted) {
          final targetContext = targetKey.currentContext!;
          if (!targetContext.mounted) return;
          final viewport = _scrollController.position.viewportDimension;
          final toolbar = MediaQuery.of(context).padding.top + kToolbarHeight;
          final alignment = (toolbar / viewport).clamp(0.0, 0.25).toDouble();
          await Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: alignment,
          );
          return;
        }
        _scrollController.jumpTo(
          (_scrollController.offset + 300).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
    } catch (_) {}
  }

  Future<void> _loadSalonDetails() async {
    setState(() => _error = '');
    try {
      final data = await _salonService.fetchSalonDetails(widget.salonId);
      if (!mounted) return;

      final categories = (data['categories'] as List?) ?? [];
      String? resolvedCatId = widget.categoryId;
      if (resolvedCatId != null && categories.isNotEmpty) {
        final exists = categories.any(
          (c) => c['id']?.toString().toLowerCase() == resolvedCatId!.toLowerCase(),
        );
        if (!exists) {
          final nameTarget = (widget.categoryName ?? resolvedCatId).toLowerCase();
          final nameMatch = categories.firstWhere(
            (c) {
              final cName = (c['name'] ?? '').toString().toLowerCase();
              return cName == nameTarget || cName.contains(nameTarget) || nameTarget.contains(cName);
            },
            orElse: () => null,
          );
          if (nameMatch != null) {
            resolvedCatId = nameMatch['id']?.toString();
          }
        }
      } else if (widget.categoryName != null && categories.isNotEmpty) {
        final nameTarget = widget.categoryName!.toLowerCase();
        final nameMatch = categories.firstWhere(
          (c) {
            final cName = (c['name'] ?? '').toString().toLowerCase();
            return cName == nameTarget || cName.contains(nameTarget) || nameTarget.contains(cName);
          },
          orElse: () => null,
        );
        if (nameMatch != null) {
          resolvedCatId = nameMatch['id']?.toString();
        }
      }

      setState(() {
        _salon = data;
        _isFavourited =
            data['is_favourited'] == true ||
            data['is_favourited'] == 1 ||
            data['is_favourited'] == '1';
        // Land on the category the customer came in through, so unrelated
        // categories stay out of the way until they switch tabs themselves.
        _selectedCategoryId = resolvedCatId;
        _highlightServiceId = widget.serviceId;
        if (widget.serviceId != null) {
          _isServicesExpanded = true;
        }
        _isLoading = false;
      });
      if (widget.serviceId != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _revealHighlightedService(),
        );
      } else if (widget.initialScrollToServices ||
          widget.categoryId != null ||
          widget.categoryName != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToServicesSection(),
        );
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
        MaterialPageRoute(
          builder: (context) => const PhoneScreen(isModal: true),
        ),
      );
      if (loggedIn != true) return;
    }

    if (_isTogglingFavourite) return;
    final bool currentFav = _isFavourited;

    // Optimistic UI update
    setState(() {
      _isTogglingFavourite = true;
      _isFavourited = !currentFav;
    });
    AppHaptics.lightImpact();

    try {
      final isFavourited = await _salonService.toggleFavourite(widget.salonId);
      if (!mounted) return;
      setState(() {
        _isFavourited = isFavourited;
        _actionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      // Revert optimistic update
      setState(() {
        _isFavourited = currentFav;
      });
      _showError(
        describeError(e, fallback: 'Could not update your favourites.'),
      );
    } finally {
      if (mounted) {
        setState(() => _isTogglingFavourite = false);
      }
    }
  }

  Future<void> _addToCart({
    String? serviceId,
    String? comboId,
    required String label,
    int quantity = 1,
  }) async {
    if (serviceId != null) {
      if (_inFlightServiceIds.contains(serviceId)) return;
      setState(() => _inFlightServiceIds.add(serviceId));
    }

    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      if (serviceId != null && mounted) {
        setState(() => _inFlightServiceIds.remove(serviceId));
      }
      if (!mounted) return;
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => const PhoneScreen(isModal: true),
        ),
      );
      if (loggedIn != true) return;
      if (serviceId != null && mounted) {
        setState(() => _inFlightServiceIds.add(serviceId));
      }
    }

    try {
      final cart = serviceId != null
          ? await _cartService.addItem(widget.salonId, serviceId, quantity: 1)
          : await _cartService.addCombo(
              widget.salonId,
              comboId!,
              quantity: quantity,
            );

      if (!mounted) return;

      AppHaptics.lightImpact();
      setState(() {
        _cart = cart;
        _actionError = null;
      });

      final replaced = cart?['_replaced_services'] as List?;
      if (replaced != null && replaced.isNotEmpty) {
        final msg = cart?['_message'] as String? ?? 'Replaced individual services with combo!';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      msg,
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
      } else if (cart?['_already_in_combo'] == true) {
        final msg = cart?['_message'] as String?;
        if (msg != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        msg,
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF2563EB),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
        }
      }
    } on CartConflictException catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Replace cart items?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
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
              child: Text(
                'Cancel',
                style: GoogleFonts.outfit(color: context.colors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                AppHaptics.lightImpact();
                Navigator.pop(ctx);
                await _cartService.clearGlobalCart();
                _addToCart(
                  serviceId: serviceId,
                  comboId: comboId,
                  label: label,
                  quantity: quantity,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
              ),
              child: Text(
                'Replace',
                style: GoogleFonts.outfit(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _showError(
        describeError(e, fallback: 'Could not add that to your cart.'),
      );
    } finally {
      if (serviceId != null && mounted) {
        setState(() => _inFlightServiceIds.remove(serviceId));
      }
    }
  }

  Future<void> _removeService(String serviceId, String label) async {
    final cartItem = _getServiceCartItem(serviceId);
    if (cartItem == null) return;
    if (_inFlightServiceIds.contains(serviceId)) return;

    final itemId = cartItem['id'].toString();

    setState(() => _inFlightServiceIds.add(serviceId));
    try {
      AppHaptics.lightImpact();
      await _cartService.removeItem(itemId);
      if (!mounted) return;
      setState(() {
        _cart = CartService.globalCartNotifier.value;
        _actionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _showError(describeError(e, fallback: 'Could not remove service.'));
    } finally {
      if (mounted) {
        setState(() => _inFlightServiceIds.remove(serviceId));
      }
    }
  }

  Future<void> _decrementCombo(String comboId, String label) async {
    final cartItem = _getComboCartItem(comboId);
    if (cartItem == null) return;

    final currentQty = (cartItem['quantity'] as num?)?.toInt() ?? 1;
    final itemId = cartItem['id'].toString();

    try {
      AppHaptics.lightImpact();
      final updatedCart = await _cartService.updateQuantity(
        widget.salonId,
        itemId,
        comboId: comboId,
        newQuantity: currentQty - 1,
      );

      if (!mounted) return;
      setState(() {
        _cart = updatedCart;
        _actionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _showError(
        describeError(e, fallback: 'Could not update package quantity.'),
      );
    }
  }

  /// Opens turn-by-turn navigation or map location for the salon.
  Future<void> _openDirections() async {
    if (_salon == null) return;
    AppHaptics.selectionClick();

    final rawLat = _salon!['latitude'];
    final rawLng = _salon!['longitude'];
    final lat = rawLat != null ? double.tryParse('$rawLat') : null;
    final lng = rawLng != null ? double.tryParse('$rawLng') : null;
    final bool hasValidCoords =
        lat != null &&
        lng != null &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lng >= -180.0 &&
        lng <= 180.0 &&
        !(lat == 0.0 && lng == 0.0);

    final address = [
      _salon!['address'],
      _salon!['city'],
      _salon!['pincode'],
    ].where((part) => part != null && '$part'.trim().isNotEmpty).join(', ');
    final name = _salon!['name']?.toString().trim() ?? '';
    final mapUrl = _salon!['map_url']?.toString().trim() ?? '';

    final Uri uri;
    if (hasValidCoords) {
      uri = Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '$lat,$lng',
      });
    } else if (mapUrl.isNotEmpty &&
        (mapUrl.startsWith('http://') || mapUrl.startsWith('https://'))) {
      uri = Uri.parse(mapUrl);
    } else if (address.isNotEmpty || name.isNotEmpty) {
      final String queryTarget = address.isNotEmpty
          ? (name.isNotEmpty ? '$name, $address' : address)
          : name;
      uri = Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': queryTarget,
      });
    } else {
      _toast('Location details are unavailable for this salon.');
      return;
    }

    try {
      if (!await canLaunchUrl(uri) ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _toast('Could not open maps.');
      }
    } catch (_) {
      _toast('Could not open maps.');
    }
  }

  Future<void> _openCart() async {
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (context) => const CartScreen()));
    _loadCart();
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
    final error = _actionError;
    if (error == null) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: InlineStatus(
              message: error,
              onDismiss: () => setState(() => _actionError = null),
            ),
          ),
        ),
      ],
    );
  }

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  bool get _isBookable => _salon?['is_bookable'] == true;

  List<dynamic> get _visibleServices {
    final rawServices = (_salon?['services'] as List?) ?? [];
    List<dynamic> filtered;
    if (_selectedCategoryId == null) {
      filtered = List<dynamic>.from(rawServices);
    } else {
      final target = _selectedCategoryId!.toLowerCase();
      filtered = rawServices.where((s) {
        final cId = s['category_id']?.toString().toLowerCase();
        final cName = s['category_name']?.toString().toLowerCase();
        return cId == target ||
            (widget.categoryName != null &&
                cName != null &&
                cName == widget.categoryName!.toLowerCase());
      }).toList();
    }

    filtered.sort((a, b) {
      final mapA = a is Map ? a : <String, dynamic>{};
      final mapB = b is Map ? b : <String, dynamic>{};

      // 1. Completed booking count (popularity) DESC
      final int countA = int.tryParse('${mapA['booking_count'] ?? 0}') ?? 0;
      final int countB = int.tryParse('${mapB['booking_count'] ?? 0}') ?? 0;
      if (countA != countB) {
        return countB.compareTo(countA);
      }

      // 2. Most recently booked (last_booked_at) DESC
      final String? lastBookedA = mapA['last_booked_at']?.toString();
      final String? lastBookedB = mapB['last_booked_at']?.toString();
      if (lastBookedA != null || lastBookedB != null) {
        if (lastBookedA == null) return 1;
        if (lastBookedB == null) return -1;
        final comp = lastBookedB.compareTo(lastBookedA);
        if (comp != 0) return comp;
      }

      // 3. Display order ASC
      final int orderA = int.tryParse('${mapA['display_order'] ?? 0}') ?? 0;
      final int orderB = int.tryParse('${mapB['display_order'] ?? 0}') ?? 0;
      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }

      // 4. Service name ASC
      final String nameA = (mapA['name'] ?? '').toString().toLowerCase();
      final String nameB = (mapB['name'] ?? '').toString().toLowerCase();
      final nameComp = nameA.compareTo(nameB);
      if (nameComp != 0) return nameComp;

      // 5. Fallback ID ASC
      final String idA = (mapA['id'] ?? '').toString();
      final String idB = (mapB['id'] ?? '').toString();
      return idA.compareTo(idB);
    });

    return filtered;
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
                onAction: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context, rootNavigator: true).maybePop();
                  }
                },
              ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      },
      child: Scaffold(
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
              SliverToBoxAdapter(child: _buildFirstTimeOfferBanner()),
              SliverToBoxAdapter(child: _buildHoursPanel()),
              SliverToBoxAdapter(key: _combosKey, child: _buildCombos()),
              SliverToBoxAdapter(key: _categoryTabsKey, child: _buildCategoryTabs()),
              _buildServiceSliver(),
              SliverToBoxAdapter(child: _buildTeam()),
              SliverToBoxAdapter(key: _reviewsKey, child: _buildReviews()),
              SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomArea(),
      ),
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
      title: Text(
        _salon!['name'] ?? 'Salon',
        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      leading: Padding(
        padding: const EdgeInsets.only(left: 12.0, top: 6.0, bottom: 6.0),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context, rootNavigator: true).maybePop();
              }
            },
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Container(
            width: 44,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: _isFavourited
                  ? 'Remove from favourites'
                  : 'Add to favourites',
              icon: Icon(
                _isFavourited ? Icons.favorite : Icons.favorite_border,
                size: 20,
              ),
              color: _isFavourited ? Colors.redAccent : Colors.white,
              onPressed: _toggleFavourite,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Open cart',
                  icon: const Icon(
                    Icons.shopping_bag_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _openCart,
                ),
              ),
              if (_cartItemCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppTheme.accentColor,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Center(
                      child: Text(
                        '$_cartItemCount',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (gallery.isEmpty)
              _galleryPlaceholder()
            else
              Image.network(
                gallery.first['url'] ?? '',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _galleryPlaceholder(),
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
    child: Center(
      child: Icon(
        Icons.storefront,
        size: 90,
        color: Colors.white.withValues(alpha: 0.45),
      ),
    ),
  );

  Widget _glassChip(String text) => Container(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: GoogleFonts.outfit(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
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
          color: count > 0
              ? context.colors.success
              : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, color: Colors.white, size: 15),
            SizedBox(width: 4),
            Text(
              count > 0 ? '${average.toStringAsFixed(1)} ($count)' : 'New',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (count > 0) ...[
              SizedBox(width: 3),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 15,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- header

  Widget _buildHeaderCard() {
    final isOpen = _salon!['is_open_now'] == true;
    final address = [
      _salon!['address'],
      _salon!['city'],
      _salon!['pincode'],
    ].where((part) => part != null && '$part'.trim().isNotEmpty).join(', ');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _salon!['name'] ?? 'Salon',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isOpen
                                ? context.colors.success
                                : context.colors.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _salon!['open_status_label'] ?? '',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isOpen
                                  ? context.colors.success
                                  : context.colors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Get directions',
                child: Semantics(
                  button: true,
                  label: 'Get directions',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _openDirections,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: context.colors.accentSoft,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.accentColor.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.directions_outlined,
                            size: 24,
                            color: AppTheme.accentColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (address.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: 'Open in maps',
                  child: Semantics(
                    button: true,
                    label: 'Open location in maps',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _openDirections,
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Icon(
                            Icons.location_on_outlined,
                            size: 20,
                            color: AppTheme.accentColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Tooltip(
                    message: 'Open in maps',
                    child: Semantics(
                      button: true,
                      label: 'Open address in maps: $address',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _openDirections,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6.0,
                              horizontal: 4.0,
                            ),
                            child: Text(
                              address,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: context.colors.textPrimary,
                                decoration: TextDecoration.underline,
                                decorationColor: AppTheme.accentColor
                                    .withValues(alpha: 0.35),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // The salon's phone is the owner's personal number — never surfaced
          // to customers. The description takes its place here.
          if ((_salon!['description'] ?? '').toString().isNotEmpty) ...[
            SizedBox(height: 14),
            Text(
              _salon!['description'],
              style: GoogleFonts.outfit(
                fontSize: 14,
                height: 1.5,
                color: context.colors.textSecondary,
              ),
            ),
          ],

          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  Icons.spa_outlined,
                  '${(_salon!['services'] as List?)?.length ?? 0}',
                  'Services',
                ),
              ),
              Expanded(
                child: _statTile(
                  Icons.people_outline,
                  '${(_salon!['team'] as List?)?.length ?? 0}',
                  'Staff',
                ),
              ),
              Expanded(
                child: _statTile(
                  Icons.percent,
                  '${_toDouble(_salon!['advance_percentage_default']).toStringAsFixed(0)}%',
                  'Advance',
                ),
              ),
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
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.colors.textPrimary,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: context.colors.textTertiary,
          ),
        ),
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
            body:
                _salon!['unavailable_reason'] ??
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
  }) => Container(
    width: double.infinity,
    margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
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
          title: Text(
            'Opening hours',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
          children: week.map<Widget>((day) {
            final isToday = day['is_today'] == true;
            final closed = day['is_closed'] == true;

            return Padding(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    day['day_name'],
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isToday
                          ? AppTheme.accentColor
                          : context.colors.textSecondary,
                    ),
                  ),
                  Text(
                    closed
                        ? 'Closed'
                        : '${day['open_time']} – ${day['close_time']}',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: closed
                          ? context.colors.textTertiary
                          : (isToday
                                ? AppTheme.accentColor
                                : context.colors.textPrimary),
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
    if (combos.isEmpty ||
        (_selectedCategoryId != null && _selectedCategoryId != 'combo')) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Value packages', 'Bundled services at a lower price'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: combos.asMap().entries.map((e) {
                final index = e.key;
                final combo = e.value;
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == combos.length - 1 ? 0 : 12,
                  ),
                  child: _comboCard(combo),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _comboCard(Map<String, dynamic> combo) {
    final savings = _toDouble(combo['savings']);
    final lines = (combo['services'] as List?) ?? [];
    final comboId = combo['id'].toString();
    final comboQty = _getComboQuantity(comboId);
    final isComboSelected = comboQty > 0;

    final bgColor = context.colors.accentSoft;
    final borderColor = context.colors.accentSoftHover;
    final textHeading = context.colors.textPrimary;
    final textBody = context.colors.textSecondary;
    final textLight = context.colors.textTertiary;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isComboSelected ? context.colors.accentSoft : bgColor,
        borderRadius: BorderRadius.circular(24),
        border: isComboSelected
            ? Border.all(color: AppTheme.accentColor, width: 2.0)
            : Border.all(color: borderColor, width: 1.5),
        boxShadow: isComboSelected
            ? [
                BoxShadow(
                  color: AppTheme.accentColor.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  combo['name'] ?? 'Package',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textHeading,
                  ),
                ),
              ),
              if (isComboSelected) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        comboQty > 1 ? 'Selected ($comboQty)' : 'Selected',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (savings > 0) FlippingSavingsBadge(savings: savings),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${combo['duration_minutes']} mins · ${lines.length} services',
            style: GoogleFonts.outfit(fontSize: 13, color: textBody),
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines
                .map<Widget>(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.check_circle,
                            size: 14,
                            color: AppTheme.accentColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            line['name'] ?? '',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: textBody,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const Spacer(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (savings > 0)
                    Text(
                      '₹${_toDouble(combo['original_price']).toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: textLight,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    '₹${_toDouble(combo['price']).toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentColor,
                    ),
                  ),
                  if (comboQty > 1)
                    Text(
                      'Total: ₹${(_toDouble(combo['price']) * comboQty).toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textSecondary,
                      ),
                    ),
                ],
              ),
              if (isComboSelected)
                _quantityStepper(
                  quantity: comboQty,
                  onIncrement: () => _addToCart(
                    comboId: comboId,
                    label: combo['name'] ?? 'Package',
                  ),
                  onDecrement: () =>
                      _decrementCombo(comboId, combo['name'] ?? 'Package'),
                )
              else
                _addButton(
                  enabled: _isBookable,
                  onTap: () => _addToCart(
                    comboId: comboId,
                    label: combo['name'] ?? 'Package',
                  ),
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

    if (allCount == 0)
      return _sectionHeader('Services', 'Nothing published yet');

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
            controller: _categoryTabsScrollController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: tabs.length,
            separatorBuilder: (_, __) => SizedBox(width: 4),
            itemBuilder: (context, index) {
              final tab = tabs[index];
              final isSelected = _selectedCategoryId == tab['id'] ||
                  (_selectedCategoryId != null &&
                   tab['id'] != null &&
                   tab['id'].toString().toLowerCase() == _selectedCategoryId!.toLowerCase());
              final textColor = isSelected
                  ? AppTheme.accentColor
                  : (context.colors.textSecondary);

              return GestureDetector(
                onTap: () => setState(() {
                  _selectedCategoryId = tab['id'] as String?;
                  _isServicesExpanded = false;
                }),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        '${tab['name']} (${tab['service_count']})',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w600,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: Text(
              'No services in this category.',
              style: GoogleFonts.outfit(color: context.colors.textTertiary),
            ),
          ),
        ),
      );
    }

    final bool hasToggle = services.length > 5;
    final int displayedCount =
        (_isServicesExpanded || !hasToggle) ? services.length : 5;
    final int totalCount = displayedCount + (hasToggle ? 1 : 0);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index < displayedCount) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _serviceCard(services[index]),
            );
          }
          return _buildExploreServicesButton();
        },
        childCount: totalCount,
      ),
    );
  }

  Widget _buildExploreServicesButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          key: const ValueKey('explore_all_services_button'),
          onPressed: () {
            AppHaptics.lightImpact();
            final wasExpanded = _isServicesExpanded;
            setState(() {
              _isServicesExpanded = !_isServicesExpanded;
            });
            if (wasExpanded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_categoryTabsKey.currentContext != null) {
                  Scrollable.ensureVisible(
                    _categoryTabsKey.currentContext!,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              });
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.accentColor,
            backgroundColor: context.colors.surface,
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(
              color: AppTheme.accentColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isServicesExpanded ? 'Show Less' : 'Explore All Services',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentColor,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                _isServicesExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: AppTheme.accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceCard(Map<String, dynamic> service) {
    final hasStaff = (service['provider_count'] ?? 0) > 0;
    final canAdd = _isBookable && hasStaff;
    final description = (service['description'] ?? '').toString();
    final serviceId = service['id'].toString();
    final qty = _getServiceQuantity(serviceId);
    final isSelected = qty > 0;

    final ftd = service['first_time_discount'] is Map<String, dynamic>
        ? service['first_time_discount'] as Map<String, dynamic>
        : (service['first_time_discount'] is Map
              ? Map<String, dynamic>.from(service['first_time_discount'] as Map)
              : null);
    final double rawPrice = _toDouble(service['price']);
    final double? origPriceNullable = service['original_price'] != null
        ? _toDouble(service['original_price'])
        : null;
    final double? discPriceNullable = service['discounted_price'] != null
        ? _toDouble(service['discounted_price'])
        : null;
    final double origPrice = origPriceNullable ?? rawPrice;
    final double discPrice =
        discPriceNullable ??
        (ftd != null && ftd['discount_amount'] != null
            ? (origPrice - _toDouble(ftd['discount_amount']))
            : rawPrice);
    final bool isDiscounted =
        ftd != null && origPrice > discPrice && discPrice > 0;
    final double effectivePrice = isDiscounted ? discPrice : rawPrice;
    final String? discountLabel = ftd?['discount_label']?.toString();

    // Highlight came-from-category service: matched on the real template_id so
    // the salon + service relationship stays exact, never a name guess.
    final isHighlighted = _highlightServiceId != null &&
        (service['template_id']?.toString() == _highlightServiceId ||
         service['id']?.toString() == _highlightServiceId ||
         (service['name'] != null &&
          service['name'].toString().toLowerCase() == _highlightServiceId!.toLowerCase()));

    return Opacity(
      opacity: canAdd ? 1.0 : 0.6,
      child: Container(
        key: isHighlighted ? _highlightServiceKey : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: _cardDecoration(
          accentBorder: isHighlighted,
          isSelected: isSelected,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isHighlighted)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.accentColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.touch_app,
                        size: 12,
                        color: AppTheme.accentColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.categoryName ?? 'From category',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.accentColor.withValues(alpha: 0.15)
                        : context.colors.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.spa_outlined,
                    color: AppTheme.accentColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service['name'] ?? 'Service',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _metaChip(
                            Icons.access_time,
                            '${service['duration_minutes']} mins',
                          ),
                          if (service['gender_focus'] != null &&
                              service['gender_focus'] != 'Unisex')
                            _metaChip(
                              Icons.person_outline,
                              service['gender_focus'],
                            ),
                          if (service['refundable_advance'] == true)
                            _metaChip(Icons.replay, 'Refundable advance'),
                          if (isDiscounted) _firstTimeOfferChip(discountLabel),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  height: 1.35,
                  color: context.colors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            if (!hasStaff) ...[
              const SizedBox(height: 6),
              Text(
                'No staff available for this service right now',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: context.colors.danger,
                ),
              ),
            ],

            const SizedBox(height: 10),
            Divider(color: context.colors.border, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '₹${effectivePrice.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentColor,
                          ),
                        ),
                        if (isDiscounted) ...[
                          const SizedBox(width: 6),
                          AnimatedOriginalPrice(
                            originalPrice: origPrice,
                            price: effectivePrice,
                          ),
                          const SizedBox(width: 6),
                          DiscountBadge(
                            originalPrice: origPrice,
                            price: effectivePrice,
                            customLabel: discountLabel,
                            style: DiscountBadgeStyle.compact,
                          ),
                        ],
                      ],
                    ),
                    if (isDiscounted)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Save ₹${(origPrice - effectivePrice).toStringAsFixed(0)} · First visit',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.colors.success,
                          ),
                        ),
                      ),
                  ],
                ),
                if (isSelected)
                  _addedButton(
                    inFlight: _inFlightServiceIds.contains(serviceId),
                    onRemove: () =>
                        _removeService(serviceId, service['name'] ?? 'Service'),
                  )
                else
                  _addButton(
                    enabled: canAdd && !_inFlightServiceIds.contains(serviceId),
                    inFlight: _inFlightServiceIds.contains(serviceId),
                    onTap: () => _addToCart(
                      serviceId: serviceId,
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.colors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: context.colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _firstTimeOfferChip(String? label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 11, color: AppTheme.accentColor),
          const SizedBox(width: 4),
          Text(
            label ?? 'First visit offer',
            style: GoogleFonts.outfit(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirstTimeOfferBanner() {
    final offer = _salon?['first_time_offer'] as Map<String, dynamic>?;
    if (offer == null || offer['eligible'] != true) {
      return const SizedBox.shrink();
    }

    final name = offer['offer_name']?.toString() ?? 'First-Time Customer Offer';
    final label =
        offer['label']?.toString() ??
        'Special discount on select services for your first booking';
    final discountType = offer['discount_type']?.toString();
    final discountVal = offer['discount_value'];
    final badgeText = discountType == 'percentage'
        ? '${discountVal ?? 20}% OFF'
        : '₹${discountVal ?? 0} OFF';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEE3ED).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: AppTheme.accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addButton({
    required bool enabled,
    bool inFlight = false,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 36,
      child: ElevatedButton.icon(
        key: const ValueKey('add_service_button'),
        onPressed: enabled && !inFlight ? onTap : null,
        icon: inFlight
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add, size: 16),
        label: Text(
          'ADD',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: context.colors.border,
          disabledForegroundColor: context.colors.textTertiary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _addedButton({
    required bool inFlight,
    required VoidCallback onRemove,
  }) {
    return SizedBox(
      height: 36,
      child: Container(
        key: const ValueKey('added_service_container'),
        decoration: BoxDecoration(
          color: context.colors.accentSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.accentColor.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: inFlight ? null : onRemove,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (inFlight)
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accentColor,
                        ),
                      )
                    else
                      const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: AppTheme.accentColor,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      'ADDED',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.4,
                        color: AppTheme.accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 16,
              color: AppTheme.accentColor.withValues(alpha: 0.25),
            ),
            IconButton(
              key: const ValueKey('remove_service_button'),
              tooltip: 'Remove from cart',
              icon: Icon(
                Icons.close_rounded,
                size: 15,
                color: context.colors.textSecondary,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 36),
              onPressed: inFlight ? null : onRemove,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quantityStepper({
    required int quantity,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.accentColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(14),
            ),
            onTap: onDecrement,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Icon(Icons.remove, size: 18, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$quantity',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ),
          InkWell(
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(14),
            ),
            onTap: onIncrement,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Icon(Icons.add, size: 18, color: Colors.white),
            ),
          ),
        ],
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
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentColor,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      member['specialization'] ??
                          '${member['service_count']} services',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: context.colors.textTertiary,
                      ),
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
        _sectionHeader(
          'Ratings & reviews',
          count > 0 ? '$count customer ratings' : null,
        ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  count == 1 ? 'See the 1 review' : 'See all $count reviews',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
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
            border: selected
                ? null
                : Border.all(color: borderColor, width: 1.2),
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

  // ------------------------------------------------------------------ shared

  Widget _sectionHeader(String title, String? subtitle) => Padding(
    padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: context.colors.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ],
    ),
  );

  BoxDecoration _cardDecoration({
    bool accentBorder = false,
    bool isSelected = false,
  }) {
    return BoxDecoration(
      color: isSelected ? context.colors.accentSoft : context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      border: (isSelected || accentBorder)
          ? Border.all(
              color: AppTheme.accentColor,
              width: 1.5,
            )
          : Border.all(
              color: context.colors.border,
              width: 1.5,
            ),
      boxShadow: (isSelected || accentBorder)
          ? [
              BoxShadow(
                color: AppTheme.accentColor.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ]
          : [
              BoxShadow(
                color: context.colors.cardShadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
    );
  }
}
