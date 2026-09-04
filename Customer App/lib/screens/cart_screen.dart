import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/cart_service.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  final String salonId;
  const CartScreen({Key? key, required this.salonId}) : super(key: key);

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
      final cart = await _cartService.getCart(widget.salonId);
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Your Cart', style: AppTheme.lightTheme.appBarTheme.titleTextStyle),
        centerTitle: true,
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
    if (_cart == null || (_cart!['items'] as List).isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 80, color: AppTheme.lightTextLight),
            SizedBox(height: 16),
            Text('Your cart is empty', style: GoogleFonts.outfit(fontSize: 18, color: AppTheme.lightTextHeading, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    final items = _cart!['items'] as List;

    return ListView.separated(
      padding: EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final service = item['service'];
        return Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.lightBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.lightAccentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.spa, color: AppTheme.accentColor),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service != null ? service['name'] : 'Unknown Service',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.lightTextHeading),
                    ),
                    SizedBox(height: 4),
                    Text(
                      service != null ? '\$${service['price']}' : '\$0',
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.accentColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: AppTheme.lightDanger),
                onPressed: () => _removeItem(item['id'].toString()),
              )
            ],
          ),
        );
      },
    );
  }

  Widget? _buildCheckoutBar() {
    if (_cart == null || (_cart!['items'] as List).isEmpty) return null;

    double total = 0.0;
    for (var item in _cart!['items']) {
      if (item['service'] != null) {
        total += double.tryParse(item['service']['price'].toString()) ?? 0.0;
      }
    }

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.lightSurface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: Offset(0, -4),
            blurRadius: 16,
          )
        ],
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total', style: GoogleFonts.outfit(fontSize: 14, color: AppTheme.lightTextBody)),
                Text('\$${total.toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.lightTextHeading)),
              ],
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => CheckoutScreen(salonId: widget.salonId)
                ));
              },
              style: AppTheme.lightTheme.elevatedButtonTheme.style?.copyWith(
                padding: MaterialStateProperty.all(EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
              ),
              child: Text('Checkout', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}
