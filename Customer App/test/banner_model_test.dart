import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/models/banner.dart';

void main() {
  group('PromoBanner Model & MediaKind Parsing', () {
    test('parses static image media_kind correctly', () {
      final json = {
        'id': '1',
        'title': 'Summer Glow',
        'image_url': 'https://res.cloudinary.com/demo/image/upload/banner.jpg',
        'media_kind': 'image',
        'target_scope': 'platform',
      };

      final banner = PromoBanner.fromJson(json);
      expect(banner.id, '1');
      expect(banner.title, 'Summer Glow');
      expect(banner.imageUrl, 'https://res.cloudinary.com/demo/image/upload/banner.jpg');
      expect(banner.mediaKind, 'image');
      expect(banner.isAnimated, isFalse);
    });

    test('parses animated media_kind correctly', () {
      final json = {
        'id': '2',
        'title': 'Flash Sale Loop',
        'image_url': 'https://res.cloudinary.com/demo/image/upload/sale.gif',
        'media_kind': 'animated',
        'target_scope': 'city',
        'target_city_id': '4',
      };

      final banner = PromoBanner.fromJson(json);
      expect(banner.id, '2');
      expect(banner.mediaKind, 'animated');
      expect(banner.isAnimated, isTrue);
      expect(banner.targetCity, '4');
    });

    test('media_kind defaults to image when omitted or null (legacy backwards compatibility)', () {
      final jsonWithoutKind = {
        'id': '3',
        'title': 'Legacy Banner',
        'image_url': 'https://res.cloudinary.com/demo/image/upload/legacy.png',
        'target_scope': 'platform',
      };

      final banner1 = PromoBanner.fromJson(jsonWithoutKind);
      expect(banner1.mediaKind, 'image');
      expect(banner1.isAnimated, isFalse);

      final jsonWithNullKind = {
        'id': '4',
        'title': 'Null Kind Banner',
        'image_url': 'https://res.cloudinary.com/demo/image/upload/null.png',
        'media_kind': null,
        'target_scope': 'platform',
      };

      final banner2 = PromoBanner.fromJson(jsonWithNullKind);
      expect(banner2.mediaKind, 'image');
      expect(banner2.isAnimated, isFalse);
    });

    test('case-insensitively parses media_kind and handles unknown values safely', () {
      final jsonUpper = {
        'id': '5',
        'title': 'Uppercase Animated',
        'image_url': 'https://res.cloudinary.com/demo/image/upload/hero.webp',
        'media_kind': 'ANIMATED',
        'target_scope': 'platform',
      };

      final bannerUpper = PromoBanner.fromJson(jsonUpper);
      expect(bannerUpper.mediaKind, 'animated');
      expect(bannerUpper.isAnimated, isTrue);

      final jsonUnknown = {
        'id': '6',
        'title': 'Unknown Kind',
        'image_url': 'https://res.cloudinary.com/demo/image/upload/video.mp4',
        'media_kind': 'video',
        'target_scope': 'platform',
      };

      final bannerUnknown = PromoBanner.fromJson(jsonUnknown);
      expect(bannerUnknown.mediaKind, 'image');
      expect(bannerUnknown.isAnimated, isFalse);
    });

    test('defensively handles missing or null title and image_url without crashing', () {
      final jsonSparse = <String, dynamic>{
        'id': 7,
      };

      final banner = PromoBanner.fromJson(jsonSparse);
      expect(banner.id, '7');
      expect(banner.title, '');
      expect(banner.imageUrl, '');
      expect(banner.mediaKind, 'image');
      expect(banner.targetScope, 'platform');
    });
  });
}
