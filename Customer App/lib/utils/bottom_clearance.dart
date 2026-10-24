import 'package:flutter/widgets.dart';

/// Space to leave under the last item of a scrollable page.
///
/// MainScreen hosts its navigation bar fixed at the bottom with the body
/// ending cleanly above it. The clearance provides the padding plus a small
/// [gap]: right in portrait and landscape, accounting for any safe area or
/// insets (such as persistent floating CTAs), and leaving clean whitespace
/// above the bottom navigation bar.
///
/// Replaces the hardcoded `140` several lists used, which was too much under
/// a SafeArea and could be too little on a device with a tall gesture inset.
double bottomClearance(BuildContext context, {double gap = 24}) =>
    MediaQuery.paddingOf(context).bottom + gap;

/// Space to leave under a bottom sheet's own content.
///
/// A sheet gets none of the shell's padding: off the root navigator it only
/// sees the system navigation bar, and `useSafeArea` does not help, because
/// SafeArea leaves its bottom edge alone. So a sheet adds this itself.
///
/// With the keyboard up, padding is already zero and the keyboard is the whole
/// inset — which is why this adds the two instead of taking the larger: taken
/// separately they would double count the bar on every keyboard.
double sheetBottomInset(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
