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
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Icon(Icons.local_offer, size: 48, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
            SizedBox(height: 12),
            Text(
              'No active offers right now',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Check back later for exciting spa and salon deals!',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final isInfinite = widget.banners.length > 1;

    return Column(
      children: [
        SizedBox(
          height: 180,
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
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Theme.of(context).dividerColor,
                    image: DecorationImage(
                      image: NetworkImage(banner.imageUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: 12),
        if (widget.banners.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.banners.length,
              (index) {
                final realCurrentPage = _currentPage % widget.banners.length;
                return AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: realCurrentPage == index ? 24 : 8,
                  decoration: BoxDecoration(
                    color: realCurrentPage == index ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }
            ),
          ),
      ],
    );
  }
}
