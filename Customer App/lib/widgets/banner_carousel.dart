import 'package:flutter/material.dart';
import '../models/banner.dart';
import '../theme/app_theme.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

class BannerCarousel extends StatefulWidget {
  final List<PromoBanner> banners;
  final bool autoPlay;

  const BannerCarousel({
    Key? key,
    required this.banners,
    this.autoPlay = true,
  }) : super(key: key);

  @override
  _BannerCarouselState createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Start at a large multiple so the user can scroll left immediately
    int initialPage = widget.banners.length > 1 ? widget.banners.length * 1000 : 0;
    _currentPage = initialPage;
    _pageController = PageController(initialPage: initialPage);
    
    if (widget.banners.length > 1 && widget.autoPlay) {
      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    _timer = Timer.periodic(Duration(seconds: 4), (Timer timer) {
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: Duration(milliseconds: 350),
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
          color: AppTheme.lightAccentSoft.withOpacity(0.35),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Icon(Icons.local_offer,
                size: 44,
                color: AppTheme.accentColor.withOpacity(0.35)),
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
              style: TextStyle(color: AppTheme.lightTextBody, fontSize: 13),
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
        onPageChanged: (int page) {
          setState(() {
            _currentPage = page;
          });
        },
        itemCount: isInfinite ? null : widget.banners.length,
        itemBuilder: (context, index) {
          final realIndex = isInfinite ? index % widget.banners.length : index;
          final banner = widget.banners[realIndex];
          return GestureDetector(
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
                color: AppTheme.lightAccentSoft,
                image: DecorationImage(
                  image: NetworkImage(banner.imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Very subtle gradient overlay so the image is the main focus
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.2),
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
                                  color: Colors.white.withOpacity(0.5),
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
          );
        },
      ),
    );
  }
}