import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../screens/cart_screen.dart';

class PersistentCartCTA extends StatelessWidget {
  final Map<String, dynamic> cart;

  const PersistentCartCTA({super.key, required this.cart});

  @override
  Widget build(BuildContext context) {
    final items = (cart['items'] as List?) ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    final int count = items.length;
    final String label = count == 1 ? '1 item' : '$count items';

    return SafeArea(
      top: false,
      bottom: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Material(
            color: AppTheme.accentColor,
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(30),
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CartScreen()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 14,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.shopping_cart_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'View Cart',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

