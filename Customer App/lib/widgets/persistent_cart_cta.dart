import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../screens/cart_screen.dart';

class PersistentCartCTA extends StatelessWidget {
  final Map<String, dynamic> cart;

  const PersistentCartCTA({Key? key, required this.cart}) : super(key: key);

  double _toDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final items = (cart['items'] as List?) ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    final summary = cart['summary'] as Map<String, dynamic>?;

    final double total;
    final double listTotal;
    
    if (summary != null) {
      total = _toDouble(summary['total_payable']);
      listTotal = _toDouble(summary['total_list_price']);
    } else {
      total = items.fold(0.0, (sum, item) => sum + _itemTotal(item));
      listTotal = items.fold(0.0, (sum, item) => sum + _itemListTotal(item));
    }

    final double saving = listTotal > total ? listTotal - total : 0;
    final int count = items.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.listBorder)),
        boxShadow: [
          if (!context.colors.prefersOutline)
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), 
              offset: const Offset(0, -4), 
              blurRadius: 20
            ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: false,
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
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
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
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CartScreen()),
                );
              },
              icon: const Icon(Icons.shopping_cart, size: 18),
              label: Text('View Cart',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _itemTotal(dynamic item) {
    final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
    if (item['combo'] != null) {
      return _toDouble(item['combo']['price']) * quantity;
    }
    if (item['service'] != null) {
      return _toDouble(item['service']['price']) * quantity;
    }
    return 0;
  }

  double _itemListTotal(dynamic item) {
    final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
    if (item['combo'] != null) {
      final double serviceSum = ((item['combo']['services'] as List?) ?? [])
          .fold(0.0, (s, srv) => s + _toDouble(srv['price']));
      final double comboPrice = _toDouble(item['combo']['price']);
      return (serviceSum > comboPrice ? serviceSum : comboPrice) * quantity;
    }
    if (item['service'] != null) {
      return _toDouble(item['service']['price']) * quantity;
    }
    return 0;
  }
}
