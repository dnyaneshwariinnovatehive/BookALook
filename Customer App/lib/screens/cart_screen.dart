import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import 'phone_screen.dart';
import '../widgets/cart_offers.dart';
import 'checkout_screen.dart';
import 'main_screen.dart';
import '../utils/app_haptics.dart';
import '../theme/app_colors.dart';
import '../utils/error_text.dart';
import '../widgets/feedback_states.dart';
import '../widgets/skeleton.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CartService _cartService = CartService();
  Map<String, dynamic>? _cart;
  bool _isLoading = true;
  String _error = '';

  /// A failed add or remove, shown at the top of the cart until dismissed
  /// or the next action succeeds. Not a SnackBar: it would cover the
  /// checkout bar, which is exactly what the customer looks at next.
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final cart = await _cartService.getGlobalCart();
      setState(() {
        _cart = cart;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = describeError(e, fallback: 'We could not load your cart.');
        _isLoading = false;
      });
    }
  }

  bool _isAdding = false;

  /// Adds a suggested or missing service straight from the cart, then reloads
  /// so a newly completed package re-prices immediately.
  Future<void> _addService(String serviceId) async {
    final salonId = _cart?['salon_id']?.toString();
    if (salonId == null || _isAdding) return;

    setState(() => _isAdding = true);

    try {
      AppHaptics.lightImpact();
      await _cartService.addItem(salonId, serviceId);
      await _loadCart();
      if (mounted) setState(() => _actionError = null);
    } catch (e) {
      AppHaptics.error();
      _showError(describeError(e, fallback: 'Could not add that service.'));
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _addAll(List<String> serviceIds) async {
    final salonId = _cart?['salon_id']?.toString();
    if (salonId == null || _isAdding) return;

    setState(() => _isAdding = true);

    try {
      AppHaptics.lightImpact();
      for (final id in serviceIds) {
        await _cartService.addItem(salonId, id);
      }
      await _loadCart();
      if (mounted) setState(() => _actionError = null);
    } catch (e) {
      AppHaptics.error();
      _showError(describeError(e, fallback: 'Could not add that service.'));
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  void _showError(String text) {
    if (!mounted) return;
    setState(() => _actionError = text);
  }

  /// Label on the left, figure on the right — the same row style the booking
  /// dialogs use, so every confirmation in the app reads the same.
  Widget _dialogRow(String label, String value, Color valueColor) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary)),
          Text(value, style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      );

  /// One tap here hard-deletes the line and re-prices the whole cart, so the
  /// customer is told what is going and what it costs them before it happens.
  Future<void> _removeItem(
    String itemId, {
    required String title,
    required double lineTotal,
    required bool isCombo,
  }) async {
    final textHeading = context.colors.textPrimary;
    final textBody = context.colors.textSecondary;
    final textLight = context.colors.textTertiary;
    final danger = context.colors.danger;
    final dangerBg = context.colors.dangerBg;
    final surface = context.colors.surface;

    final summary = _cart?['summary'] as Map<String, dynamic>?;
    final saving = double.tryParse('${summary?['saving'] ?? 0}') ?? 0.0;
    final hasOffers = ((_cart?['applied_combos'] as List?) ?? const []).isNotEmpty || saving > 0;

    AppHaptics.lightImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: surface,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        title: Text('Remove this item?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20, color: textHeading)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: textHeading)),
            SizedBox(height: 12),
            _dialogRow('Item price', '₹${lineTotal.toStringAsFixed(0)}', textHeading),
            if (isCombo) ...[
              SizedBox(height: 6),
              _dialogRow('Type', 'Package', textBody),
            ],
            if (hasOffers) ...[
              SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: dangerBg, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: danger),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        saving > 0
                            ? 'You save ₹${saving.toStringAsFixed(0)} on this cart. Removing an item can change which offers apply, and your total will be recalculated.'
                            : 'This item is part of an applied offer. Removing it can change which offers apply, and your total will be recalculated.',
                        style: GoogleFonts.outfit(fontSize: 12, color: danger),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 14),
            Text(
              isCombo
                  ? 'The whole package comes out of your cart, including every service in it.'
                  : 'This only takes it out of your cart. You can add it again from the salon.',
              style: GoogleFonts.outfit(fontSize: 12, color: textLight),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(dialogContext, false);
            },
            child: Text('Keep it', style: GoogleFonts.outfit(color: textBody)),
          ),
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(dialogContext, true);
            },
            child: Text('Remove item',
                style: GoogleFonts.outfit(color: danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _cartService.removeItem(itemId);
      AppHaptics.mediumImpact();
      if (mounted) setState(() => _actionError = null);
      _loadCart(); // Reload cart after removing item
    } catch (e) {
      AppHaptics.error();
      _showError(describeError(e, fallback: 'Could not remove that item. Please try again.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = context.colors.surfaceMuted;
    final textHeading = context.colors.textPrimary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _cart != null && _cart!['salon'] != null ? 'Cart - ${_cart!['salon']['name']}' : 'Your Cart',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: textHeading),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0, top: 6.0, bottom: 6.0),
          child: Container(
            decoration: BoxDecoration(
              color: context.colors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back, color: textHeading, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildCheckoutBar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return SkeletonList(
        itemBuilder: (context) => const CartItemSkeleton(),
        count: 3,
        padding: const EdgeInsets.all(16),
      );
    }
    if (_error.isNotEmpty) {
      return RefreshIndicator(
        color: AppTheme.accentColor,
        onRefresh: _loadCart,
        child: ScrollableStateView(
          child: ErrorState(
            title: 'Could not load your cart',
            message: _error,
            onRetry: _loadCart,
          ),
        ),
      );
    }
    if (_cart == null || (_cart!['items'] as List).isEmpty) {
      return EmptyState(
        icon: Icons.shopping_bag_outlined,
        title: 'Your cart is empty',
        message: 'Add services from a salon to book them together.',
        actionLabel: 'Browse salons',
        onAction: () => Navigator.pop(context),
      );
    }

    final items = _cart!['items'] as List;
    final summary = _cart!['summary'] as Map<String, dynamic>? ?? const {};
    final applied = (_cart!['applied_combos'] as List?) ?? const [];
    final offers = (_cart!['combo_offers'] as List?) ?? const [];
    final suggestions = (_cart!['suggestions'] as List?) ?? const [];
    final saving = double.tryParse('${summary['saving'] ?? 0}') ?? 0.0;

    return RefreshIndicator(
      color: AppTheme.accentColor,
      onRefresh: _loadCart,
      child: ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16),
        children: [
          if (_actionError != null) ...[
            InlineStatus(
              message: _actionError!,
              onDismiss: () => setState(() => _actionError = null),
            ),
            SizedBox(height: 16),
          ],
          // What the cart already qualifies for comes first — the customer
          // should see they are ahead before they see the bill.
          if (applied.isNotEmpty) ...[
            AppliedComboBanner(appliedCombos: applied, totalSaving: saving),
            SizedBox(height: 16),
          ],

          ...items.map(_buildItemTile),

          if (offers.isNotEmpty) ...[
            SizedBox(height: 20),
            ...offers.map((offer) => Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: ComboOfferCard(
                    offer: offer as Map<String, dynamic>,
                    onAddService: _isAdding ? null : _addService,
                    onCompletePackage: _isAdding ? null : _addAll,
                  ),
                )),
          ],

          if (suggestions.isNotEmpty) ...[
            SizedBox(height: 20),
            SuggestionStrip(
              suggestions: suggestions,
              onAdd: _isAdding ? null : _addService,
            ),
          ],

          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildItemTile(dynamic raw) {
    final item = raw as Map<String, dynamic>;
    {
      {
        final service = item['service'];
        final combo = item['combo'];
        final isCombo = combo != null;
        final title = isCombo
            ? (combo['name'] ?? 'Package')
            : (service != null ? (service['template']?['name'] ?? 'Unknown Service') : 'Unknown Service');
        final subtitle = isCombo
            ? '${(combo['services'] as List?)?.length ?? 0} services in this package'
            : null;

        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          margin: EdgeInsets.only(bottom: 14),
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.colors.accentSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(isCombo ? Icons.card_giftcard : Icons.spa_outlined, color: AppTheme.accentColor, size: 28),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: 4),
                      Text(subtitle, style: GoogleFonts.outfit(fontSize: 13, color: context.colors.textSecondary)),
                    ],
                    SizedBox(height: 8),
                    Text(
                      '₹${_lineTotal(item).toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: context.colors.danger),
                tooltip: 'Remove from cart',
                onPressed: () => _removeItem(
                  item['id'].toString(),
                  title: title,
                  lineTotal: _lineTotal(item),
                  isCombo: isCombo,
                ),
              )
            ],
          ),
        );
      }
    }
  }

  /// Price of one cart line. A combo is priced from its own special prices,
  /// not from the services' list prices.
  double _lineTotal(dynamic item) {
    final quantity = (item['quantity'] ?? 1) as int;

    if (item['combo'] != null) {
      double comboPrice = 0.0;
      for (final service in (item['combo']['services'] as List? ?? [])) {
        final special = service['pivot']?['combo_special_price'] ?? service['price'];
        comboPrice += double.tryParse('$special') ?? 0.0;
      }
      return comboPrice * quantity;
    }

    if (item['service'] != null) {
      return (double.tryParse('${item['service']['price']}') ?? 0.0) * quantity;
    }

    return 0.0;
  }

  Widget? _buildCheckoutBar() {
    if (_cart == null || (_cart!['items'] as List).isEmpty) return null;

    // Prefer the server's figure — it is what checkout will charge.
    final summary = _cart!['summary'] as Map<String, dynamic>?;

    final listTotal = double.tryParse('${summary?['list_total'] ?? 0}') ?? 0.0;
    final saving = double.tryParse('${summary?['saving'] ?? 0}') ?? 0.0;

    double total = 0.0;
    if (summary != null) {
      total = double.tryParse('${summary['total_amount'] ?? 0}') ?? 0.0;
    } else {
      for (var item in _cart!['items']) {
        total += _lineTotal(item);
      }
    }

    final surfaceColor = context.colors.surface;
    final textBody = context.colors.textSecondary;
    final textHeading = context.colors.textPrimary;
    final textLight = context.colors.textTertiary;

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: context.colors.prefersOutline
            ? Border(top: BorderSide(color: context.colors.raisedOutline))
            : null,
        boxShadow: [
          if (!context.colors.prefersOutline)
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
              offset: Offset(0, -6),
              blurRadius: 24,
            )
        ],
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total', style: GoogleFonts.outfit(fontSize: 14, color: textBody)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${total.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textHeading)),
                    if (saving > 0) ...[
                      SizedBox(width: 8),
                      Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('₹${listTotal.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              color: textLight,
                              decoration: TextDecoration.lineThrough,
                            )),
                      ),
                    ],
                  ],
                ),
                if (saving > 0)
                  Text('You save ₹${saving.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.success)),
              ],
            ),
            ElevatedButton(
              onPressed: () async {
                AppHaptics.lightImpact();
                final token = await AuthService.getToken();
                if (token == null || token.isEmpty) {
                  final loggedIn = await Navigator.of(context, rootNavigator: true).push<bool>(
                    MaterialPageRoute(builder: (context) => PhoneScreen(isModal: true))
                  );
                  if (loggedIn != true) return;
                }

                if (!mounted) return;
                final booked = await Navigator.push<bool>(context, MaterialPageRoute(
                  builder: (context) => CheckoutScreen(salonId: _cart!['salon_id'].toString())
                ));
                if (booked == true) {
                  Navigator.of(context, rootNavigator: true)
                      .pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const MainScreen(initialIndex: 2),
                    ),
                    (route) => false,
                  );
                } else {
                  _loadCart();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text('Checkout', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}
