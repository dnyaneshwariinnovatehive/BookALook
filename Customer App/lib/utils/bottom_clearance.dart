import 'package:flutter/widgets.dart';

/// Space to leave under the last item of a scrollable page.
///
/// MainScreen floats its navigation pill over every tab (`extendBody: true`),
/// and a Scaffold with extendBody reports the pill's footprint to everything
/// in its body as bottom padding — including pages pushed inside a tab's own
/// navigator. So the clearance is that padding plus a small [gap]: right in
/// portrait and landscape, with or without a gesture bar, and just the safe
/// area plus the gap on a page outside the shell.
///
/// Inside a SafeArea the padding has already been applied and removed from
/// the MediaQuery, so this correctly comes out as the gap alone.
///
/// Replaces the hardcoded `140` several lists used, which was too much under
/// a SafeArea and could be too little on a device with a tall gesture inset.
double bottomClearance(BuildContext context, {double gap = 24}) =>
    MediaQuery.paddingOf(context).bottom + gap;
