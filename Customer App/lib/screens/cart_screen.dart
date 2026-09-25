import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import 'phone_screen.dart';
import '../widgets/cart_offers.dart';
import 'checkout_screen.dart';
import 'main_screen.dart';

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
        _error = e.toString();
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
      await _cartService.addItem(salonId, serviceId);
      await _loadCart();
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _addAll(List<String> serviceIds) async {
    final salonId = _cart?['salon_id']?.toString();
    if (salonId == null || _isAdding) return;

    setState(() => _isAdding = true);

    try {
      for (final id in serviceIds) {
        await _cartService.addItem(salonId, id);
      }
      await _loadCart();
    } catch (e) {
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _removeItem(String itemId) async {
    try {
      await _cartService.removeItem(itemId);
      _loadCart(); // Reload cart after removing item
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove item: $e', style: AppTheme.lightTheme.snackBarTheme.contentTextStyle)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final textHeading = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;

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
              color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
              shape: BoxShape.circle,
            ),
            child: IconButton(
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
      return Center(child: CircularProgressIndicator(color: AppTheme.accentColor));
    }
    if (_error.isNotEmpty) {
      return Center(child: Text(_error, style: TextStyle(color: AppTheme.lightDanger)));
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textLight = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;
    final textHeading = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;

    if (_cart == null || (_cart!['items'] as List).isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 80, color: textLight),
            SizedBox(height: 16),
            Text('Your cart is empty', style: GoogleFonts.outfit(fontSize: 18, color: textHeading, fontWeight: FontWeight.w600)),
          ],
        ),
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
            color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(isDark ? 0.2 : 0.03),
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
                  color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
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
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: 4),
                      Text(subtitle, style: GoogleFonts.outfit(fontSize: 13, color: isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody)),
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
                icon: Icon(Icons.delete_outline, color: isDark ? AppTheme.darkDanger : AppTheme.lightDanger),
                onPressed: () => _removeItem(item['id'].toString()),
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textBody = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final textHeading = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final textLight = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: isDark ? Border(top: BorderSide(color: AppTheme.darkBorder)) : null,
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
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
                          color: AppTheme.lightSuccess)),
              ],
            ),
            ElevatedButton(
              onPressed: () async {
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
