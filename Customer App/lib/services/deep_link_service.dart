import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../screens/salon_detail_screen.dart';

/// Opens the app at the right place when a link brings somebody in.
///
/// Today that means one thing: a salon's printed QR code. Someone scans the
/// poster in the window, the website hands over to `bookalook://salon/{id}`,
/// and they land on that salon's page instead of a home screen they then have
/// to search from.
///
/// Two ways a link arrives, and both have to work:
///
///   - cold start, where the link launched the app and is waiting on the
///     initial route
///   - warm, where the app was already running in the background
///
/// Routing goes through a global navigator key rather than a BuildContext,
/// because a link can land before any screen has been built.
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  /// Held by MaterialApp so a link can navigate without a BuildContext.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  bool _started = false;

  /// Begin listening. Safe to call more than once.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      // The link that launched the app, if it was launched by one.
      final initial = await _appLinks.getInitialLink();

      if (initial != null) {
        // Deferred: the first frame has not been drawn yet, so there is no
        // navigator to push onto until the splash screen has mounted.
        WidgetsBinding.instance.addPostFrameCallback((_) => _handle(initial));
      }

      _subscription = _appLinks.uriLinkStream.listen(
        _handle,
        onError: (Object e) => debugPrint('Deep link stream error: $e'),
      );
    } catch (e) {
      // A broken link must never stop the app from starting normally.
      debugPrint('Could not start deep link handling: $e');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }

  /// Route one incoming link.
  ///
  /// Accepts both `bookalook://salon/{id}` and an https `/s/{slug}` address,
  /// so the same code keeps working when the website is verified for App Links
  /// after launch and the browser stops being involved at all.
  Future<void> _handle(Uri uri) async {
    var salonId = _salonIdFrom(uri);

    // The printed poster carries /s/{slug}, and the app addresses salons by id,
    // so a web link costs one lookup before anything can be shown.
    salonId ??= await _resolveSlug(_slugFrom(uri));

    if (salonId == null) {
      debugPrint('Ignoring a link we do not handle: $uri');
      return;
    }

    _openSalon(salonId);
  }

  void _openSalon(String salonId) {
    final navigator = navigatorKey.currentState;

    if (navigator == null) {
      // Nothing mounted yet; try again once a frame has been built rather than
      // dropping the link on the floor.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSalon(salonId));
      return;
    }

    navigator.push(
      MaterialPageRoute(builder: (_) => SalonDetailScreen(salonId: salonId)),
    );
  }

  /// Turn a printed /s/{slug} address into the id the app navigates by.
  Future<String?> _resolveSlug(String? slug) async {
    if (slug == null) return null;

    try {
      final base = dotenv.env['API_BASE_URL'] ?? 'http://127.0.0.1:8000/api';

      final response = await http.get(
        Uri.parse('$base/public/salons/$slug'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      return (body['salon'] as Map<String, dynamic>?)?['id']?.toString();
    } catch (e) {
      debugPrint('Could not resolve the salon slug: $e');
      return null;
    }
  }

  /// The slug in a printed link, or null when this is not one.
  static String? _slugFrom(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;

    final segments = uri.pathSegments;

    return segments.length >= 2 && segments.first == 's' ? segments[1] : null;
  }

  /// The salon this link points at, or null when it points at something else.
  @visibleForTesting
  static String? salonIdFrom(Uri uri) => _salonIdFrom(uri);

  static String? _salonIdFrom(Uri uri) {
    // bookalook://salon/{id} — the host carries "salon" on a custom scheme.
    if (uri.scheme == 'bookalook') {
      if (uri.host == 'salon' && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }

      // Tolerates bookalook:///salon/{id}, which some scanners produce by
      // normalising the authority away.
      if (uri.host.isEmpty &&
          uri.pathSegments.length >= 2 &&
          uri.pathSegments.first == 'salon') {
        return uri.pathSegments[1];
      }

      return null;
    }

    // https://…/salon/{id} once the domain is verified for App Links.
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      final segments = uri.pathSegments;

      if (segments.length >= 2 && segments.first == 'salon') {
        return segments[1];
      }
    }

    return null;
  }
}
