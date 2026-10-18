import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/phone_screen.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_haptics.dart';
import '../theme/app_colors.dart';
import '../utils/error_text.dart';
import 'feedback_states.dart';

/// The horizontally scrolling services of one category inside a salon card.
///
/// A customer browsing a category has already decided they want that service, so
/// this is where they act on it: the price and an add button for each service the
/// salon offers in that category, without opening the salon. Tapping the card
/// around the strip still opens the salon, so browsing is never a dead end.
class CategoryServiceStrip extends StatefulWidget {
  final String salonId;
  final List<Map<String, dynamic>> services;
  final String? categoryName;

  const CategoryServiceStrip({
    super.key,
    required this.salonId,
    required this.services,
    this.categoryName,
  });

  @override
  State<CategoryServiceStrip> createState() => _CategoryServiceStripState();
}

class _CategoryServiceStripState extends State<CategoryServiceStrip> {
  final CartService _cartService = CartService();

  final Set<String> _adding = {};

  @override
  void initState() {
    super.initState();
    CartService.globalCartNotifier.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    CartService.globalCartNotifier.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  /// How many services to show before the "see all" affordance. Enough to fill
  /// the width of a card on the largest common phone, so the scroll gesture
  /// reads as deliberate rather than as an accident of layout.
  static const int _previewCount = 6;

  List<Map<String, dynamic>> get _visible =>
      widget.services.length > _previewCount
      ? widget.services.take(_previewCount).toList()
      : widget.services;

  bool get _hasMore => widget.services.length > _previewCount;

  Future<void> _addService(Map<String, dynamic> service) async {
    final serviceId = service['id'].toString();
    if (_adding.contains(serviceId)) return;
    if (CartService.isServiceInCart(serviceId)) return;

    // Booking needs an account, so an anonymous customer is asked to sign in at
    // the moment they try to act, not before they have chosen anything.
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const PhoneScreen(isModal: true)),
      );
      if (loggedIn != true || !mounted) return;
    }

    setState(() => _adding.add(serviceId));

    try {
      await _cartService.addItem(widget.salonId, serviceId);
      if (!mounted) return;
      AppHaptics.lightImpact();
      setState(() => _error = null);
    } on CartConflictException catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _confirmReplace(e, service);
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      setState(
        () => _error = describeError(
          e,
          fallback: 'Could not add that to your cart.',
        ),
      );
    } finally {
      if (mounted) setState(() => _adding.remove(serviceId));
    }
  }

  /// The cart holds one salon at a time, so a service from a second salon is a
  /// question rather than an error. Same wording as the salon page so the rule
  /// is not learned twice.
  void _confirmReplace(CartConflictException e, Map<String, dynamic> service) {
    final bodyColor = context.colors.textSecondary;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Replace cart items?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Your cart contains items from ${e.otherSalonName}. '
          'Do you want to discard that selection and add items from this salon?',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(ctx);
            },
            child: Text('Cancel', style: GoogleFonts.outfit(color: bodyColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              AppHaptics.lightImpact();
              Navigator.pop(ctx);
              try {
                await _cartService.clearGlobalCart();
              } catch (_) {
                if (!mounted) return;
                setState(
                  () => _error = 'Could not clear your cart. Please try again.',
                );
                return;
              }
              if (!mounted) return;
              await _addService(service);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
            ),
            child: Text(
              'Replace',
              style: GoogleFonts.outfit(color: context.colors.onAccent),
            ),
          ),
        ],
      ),
    );
  }

  /// A failed add, shown under the strip.
  String? _error;

  @override
  Widget build(BuildContext context) {
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final borderColor = context.colors.listBorder;

    if (widget.services.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              widget.categoryName == null
                  ? 'Services'
                  : '${widget.categoryName} services',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: bodyColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${widget.services.length}',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentColor,
              ),
            ),
            const Spacer(),
            if (_hasMore)
              Text(
                '+${widget.services.length - _previewCount} more',
                style: GoogleFonts.outfit(fontSize: 11, color: bodyColor),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: _visible.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final service = _visible[index];
              return _buildChip(
                service,
                headingColor: headingColor,
                bodyColor: bodyColor,
                borderColor: borderColor,
              );
            },
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          InlineStatus(
            message: _error!,
            onDismiss: () => setState(() => _error = null),
          ),
        ],
      ],
    );
  }

  Widget _buildChip(
    Map<String, dynamic> service, {
    required Color headingColor,
    required Color bodyColor,
    required Color borderColor,
  }) {
    final serviceId = service['id'].toString();
    final isAdding = _adding.contains(serviceId);
    final isInCart = CartService.isServiceInCart(serviceId);
    final double rawPrice = (service['price'] as num?)?.toDouble() ?? 0;
    final double? origPrice = (service['original_price'] as num?)?.toDouble();
    final double? discPrice = (service['discounted_price'] as num?)?.toDouble();
    final bool hasDiscount =
        service['first_time_discount'] != null &&
        origPrice != null &&
        discPrice != null &&
        origPrice > discPrice &&
        discPrice > 0;
    final double displayPrice = hasDiscount ? discPrice : rawPrice;

    // Zero trained staff means it cannot be booked, so the salon page greys
    // these out and so must the strip — an enabled button here would only
    // produce a dead end at checkout.
    final isBookable = (service['provider_count'] as num?)?.toInt() != 0;

    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.serviceTileBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  service['name'] ?? 'Service',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: headingColor,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      isBookable
                          ? '₹${displayPrice.toStringAsFixed(0)}'
                          : 'Unavailable',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isBookable ? AppTheme.accentColor : bodyColor,
                      ),
                    ),
                    if (isBookable && hasDiscount) ...[
                      const SizedBox(width: 4),
                      Text(
                        '₹${origPrice.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: bodyColor,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _buildButton(
            isBookable: isBookable,
            isAdding: isAdding,
            isInCart: isInCart,
            onPressed: () => _addService(service),
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required bool isBookable,
    required bool isAdding,
    required bool isInCart,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: isBookable && !isAdding && !isInCart ? onPressed : null,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !isBookable
              ? context.colors.iconIdle
              : isInCart
              ? context.colors.accentSoft
              : AppTheme.accentColor,
          borderRadius: BorderRadius.circular(10),
          border: isInCart
              ? Border.all(color: AppTheme.accentColor, width: 1.5)
              : null,
        ),
        child: isAdding
            ? SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.onAccent,
                ),
              )
            : isInCart
            ? Icon(Icons.check, size: 16, color: AppTheme.accentColor)
            : Text(
                '+',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.onAccent,
                ),
              ),
      ),
    );
  }
}
