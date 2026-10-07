import 'package:flutter/material.dart';
import '../models/banner.dart';
import '../theme/app_theme.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

class BannerCarousel extends StatefulWidget {
  final List<PromoBanner> banners;
  final bool autoPlay;

  const BannerCarousel({
    super.key,
    required this.banners,
    this.autoPlay = true,
  });

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late PageController _pageController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Start at a large multiple so the user can scroll left immediately
    final int initialPage = widget.banners.length > 1 ? widget.banners.length * 1000 : 0;
    _pageController = PageController(initialPage: initialPage);
  }

  /// Auto-advance only when it helps. Not with the platform's reduce-motion
  /// setting, and not under a screen reader — the page would move away while
  /// it is being read. Both are re-checked whenever the MediaQuery changes.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final shouldPlay = widget.autoPlay &&
        widget.banners.length > 1 &&
        !(media?.disableAnimations ?? false) &&
        !(media?.accessibleNavigation ?? false);

    if (shouldPlay && _timer == null) {
      _startAutoPlay();
    } else if (!shouldPlay) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startAutoPlay() {
    _timer = Timer.periodic(const Duration(seconds: 4), (Timer timer) {
      // A Timer is not a Ticker, so TickerMode does not stop it: on a hidden
      // tab it would keep paging. Skip the tick while this tab is off screen.
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeIn,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.colors.accentSoft.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Icon(Icons.local_offer,
                size: 44,
                color: AppTheme.accentColor.withValues(alpha: 0.35)),
            SizedBox(height: 12),
            Text(
              'No active offers right now',
              style: TextStyle(
                color: AppTheme.accentColor,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Check back later for exciting spa and salon deals!',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final isInfinite = widget.banners.length > 1;

    return SizedBox(
      height: 160,
      child: PageView.builder(
        controller: _pageController,
        itemCount: isInfinite ? null : widget.banners.length,
        itemBuilder: (context, index) {
          final realIndex = isInfinite ? index % widget.banners.length : index;
          final banner = widget.banners[realIndex];
          final opensLink = banner.actionUrl != null && banner.actionUrl!.isNotEmpty;
          return Semantics(
            // The title is drawn at half opacity over a photo; read it plainly,
            // with where it sits in the set and whether tapping does anything.
            label: '${banner.title}. Offer ${realIndex + 1} of ${widget.banners.length}',
            button: opensLink,
            onTapHint: opensLink ? 'open offer' : null,
            excludeSemantics: true,
            child: GestureDetector(
            onTap: () async {
              if (banner.actionUrl != null && banner.actionUrl!.isNotEmpty) {
                final uri = Uri.parse(banner.actionUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: context.colors.accentSoft,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Banner Image (Static or Animated GIF/WebP)
                  if (banner.imageUrl.isNotEmpty)
                    Image.network(
                      banner.imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: context.colors.accentSoft,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: context.colors.textTertiary,
                            size: 32,
                          ),
                        );
                      },
                      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) {
                          return child;
                        }
                        return Container(
                          color: context.colors.accentSoft,
                        );
                      },
                    ),

                  // Very subtle gradient overlay so the image is the main focus
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.2),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                banner.title,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          );
        },
      ),
    );
  }
}