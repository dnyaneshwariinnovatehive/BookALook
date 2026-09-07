import 'package:flutter/material.dart';

/// Gives a bottom-navigation tab its own [Navigator] so pages pushed from
/// inside the tab render in the tab's body instead of covering the whole
/// screen. The bottom navigation bar therefore stays visible on every page.
///
/// A screen that genuinely has to leave the shell — the login screen after a
/// logout, for example — must push with
/// `Navigator.of(context, rootNavigator: true)`.
class TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;

  const TabNavigator({
    super.key,
    required this.navigatorKey,
    required this.root,
  });

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => root,
      ),
    );
  }
}
