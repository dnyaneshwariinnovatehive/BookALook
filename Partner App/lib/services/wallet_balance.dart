import 'package:flutter/foundation.dart';

import 'salon_access_api.dart';

/// The coin balance, held once for the whole app.
///
/// The pill appears in five different headers and they all have to agree. Five
/// screens each fetching their own copy would mean five requests on every tab
/// change and, worse, a number that differs depending on which tab you are
/// looking at — so the balance lives here and the headers only listen.
///
/// It is seeded from the salon-access check the dashboard already performs on
/// launch, which carries the balance with it. That means the pill costs nothing
/// to show; it only costs a request when something has actually changed it.
class WalletBalance {
  WalletBalance._();

  /// Null until the first reading arrives. The pill draws nothing rather than
  /// flashing a zero the salon does not have.
  static final ValueNotifier<WalletSnapshot?> snapshot =
      ValueNotifier<WalletSnapshot?>(null);

  /// Take the balance from a salon-access response that was fetched anyway.
  static void seedFrom(SalonAccess access) {
    snapshot.value = WalletSnapshot(
      coins: access.walletCoins,
      valueInr: access.walletValueInr,
    );
  }

  /// Re-read after something that spends or earns coins.
  ///
  /// Never throws. A stale balance in a header is a small problem; an
  /// unhandled error thrown from a screen the owner just navigated back to is
  /// a much bigger one.
  static Future<void> refresh(String salonId) async {
    try {
      seedFrom(await SalonAccessApi.check(salonId));
    } catch (_) {
      // Keep whatever was last known.
    }
  }

  static void clear() => snapshot.value = null;
}

@immutable
class WalletSnapshot {
  final int coins;
  final double valueInr;

  const WalletSnapshot({required this.coins, required this.valueInr});

  /// Indian digit grouping — 2,300 and 1,45,950, the way every amount in the
  /// country is written.
  String get formatted {
    final digits = coins.abs().toString();
    if (digits.length <= 3) return digits;

    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final groups = <String>[];

    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);

    return '${groups.join(',')},$last3';
  }
}
