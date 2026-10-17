import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:customer_app/services/app_version_service.dart';
import 'package:customer_app/screens/mandatory_update_screen.dart';
import 'package:customer_app/widgets/optional_update_dialog.dart';
import 'package:customer_app/services/http_client.dart' as app_http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final service = AppVersionService.instance;
    service.debugVersion = '1.5.0';
    service.debugBuildNumber = 10;
    service.debugClient = null;
  });

  tearDown(() {
    AppVersionService.instance.debugVersion = null;
    AppVersionService.instance.debugBuildNumber = null;
    AppVersionService.instance.debugClient = null;
  });

  group('Semantic Version Comparison', () {
    test('correctly compares major, minor, patch, and build numbers', () {
      expect(AppVersionService.compareVersions('1.0.0', 1, '1.0.0', 1), equals(0));
      expect(AppVersionService.compareVersions('1.0.0', 1, '1.0.0', 2), lessThan(0));
      expect(AppVersionService.compareVersions('1.0.1', 1, '1.0.0', 99), greaterThan(0));
      expect(AppVersionService.compareVersions('1.1.0', 1, '1.0.9', 99), greaterThan(0));
      expect(AppVersionService.compareVersions('2.0.0', 1, '1.99.99', 999), greaterThan(0));
      expect(AppVersionService.compareVersions('v2.4.0', 42, '2.4.0', 42), equals(0));

      // 2.9.0 vs 2.10.0
      expect(AppVersionService.compareVersions('2.9.0', 1, '2.10.0', 1), lessThan(0));
      expect(AppVersionService.compareVersions('2.10.0', 1, '2.9.0', 1), greaterThan(0));

      // Equal visible versions with different build numbers
      expect(AppVersionService.compareVersions('2.0.0', 10, '2.0.0', 20), lessThan(0));
      expect(AppVersionService.compareVersions('2.0.0', 20, '2.0.0', 10), greaterThan(0));

      // Build suffixes (+build)
      expect(AppVersionService.compareVersions('2.0.0+10', 0, '2.0.0+20', 0), lessThan(0));
      expect(AppVersionService.compareVersions('2.0.0+10', 0, '2.0.0', 10), equals(0));

      // Below, equal to, above minimum
      const minVer = '2.5.0';
      const minBuild = 50;
      expect(AppVersionService.compareVersions('2.4.9', 99, minVer, minBuild), lessThan(0));
      expect(AppVersionService.compareVersions('2.5.0', 49, minVer, minBuild), lessThan(0));
      expect(AppVersionService.compareVersions('2.5.0', 50, minVer, minBuild), equals(0));
      expect(AppVersionService.compareVersions('2.5.0', 51, minVer, minBuild), greaterThan(0));
      expect(AppVersionService.compareVersions('2.5.1', 1, minVer, minBuild), greaterThan(0));
    });
  });

  group('AppVersionService Policy Evaluation', () {
    test('detects mandatory update when client is below minimum version', () async {
      final mockResponse = jsonEncode({
        'success': true,
        'app': 'customer',
        'has_policy': true,
        'enforcement_active': true,
        'update_mode': 'mandatory',
        'message': 'Critical security update required.',
        'minimum': {
          'version': '2.0.0',
          'build_number': 20,
          'release_notes': 'Security hardening',
        },
        'latest': {
          'version': '2.4.0',
          'build_number': 42,
        },
        'store_urls': {
          'android': 'https://play.google.com/store/apps/details?id=in.bookalook.app',
          'ios': 'https://apps.apple.com/app/bookalook/id123',
        },
      });

      final service = AppVersionService.instance;
      service.debugVersion = '1.9.0';
      service.debugBuildNumber = 15;
      service.debugClient = MockClient((request) async {
        return http.Response(mockResponse, 200);
      });

      final info = await service.checkUpdate(forceRefresh: true);

      expect(info.type, equals(UpdateType.mandatory));
      expect(info.isMandatory, isTrue);
      expect(info.targetVersion, equals('2.0.0'));
      expect(info.targetBuild, equals(20));
      expect(info.message, equals('Critical security update required.'));
      expect(info.storeUrl, isNotEmpty);
    });

    test('detects optional update when client satisfies minimum but below latest', () async {
      final mockResponse = jsonEncode({
        'success': true,
        'app': 'customer',
        'has_policy': true,
        'enforcement_active': false,
        'update_mode': 'optional',
        'minimum': {
          'version': '1.0.0',
          'build_number': 1,
        },
        'latest': {
          'version': '2.4.0',
          'build_number': 42,
          'release_notes': 'New salon discovery filters',
        },
        'store_urls': {
          'android': 'https://play.google.com/store/apps/details?id=in.bookalook.app',
        },
      });

      final service = AppVersionService.instance;
      service.debugVersion = '2.0.0';
      service.debugBuildNumber = 20;
      service.debugClient = MockClient((request) async {
        return http.Response(mockResponse, 200);
      });

      final info = await service.checkUpdate(forceRefresh: true);

      expect(info.type, equals(UpdateType.optional));
      expect(info.isOptional, isTrue);
      expect(info.targetVersion, equals('2.4.0'));
      expect(info.releaseNotes, equals('New salon discovery filters'));
    });

    test('returns none when client is already up to date', () async {
      final mockResponse = jsonEncode({
        'success': true,
        'app': 'customer',
        'has_policy': true,
        'enforcement_active': true,
        'update_mode': 'mandatory',
        'minimum': {
          'version': '2.0.0',
          'build_number': 20,
        },
        'latest': {
          'version': '2.4.0',
          'build_number': 42,
        },
      });

      final service = AppVersionService.instance;
      service.debugVersion = '2.4.0';
      service.debugBuildNumber = 42;
      service.debugClient = MockClient((request) async {
        return http.Response(mockResponse, 200);
      });

      final info = await service.checkUpdate(forceRefresh: true);

      expect(info.type, equals(UpdateType.none));
      expect(info.hasUpdate, isFalse);
    });

    test('falls back to cached policy on network failure', () async {
      final cachedPolicy = jsonEncode({
        'has_policy': true,
        'enforcement_active': true,
        'update_mode': 'mandatory',
        'minimum': {
          'version': '2.0.0',
          'build_number': 20,
        },
        'latest': {
          'version': '2.4.0',
          'build_number': 42,
        },
      });

      SharedPreferences.setMockInitialValues({
        'cached_app_update_policy_customer': cachedPolicy,
        'cached_app_update_policy_time_customer': DateTime.now().toIso8601String(),
      });

      final service = AppVersionService.instance;
      service.debugVersion = '1.0.0';
      service.debugBuildNumber = 1;
      // Network throws error
      service.debugClient = MockClient((request) async {
        throw Exception('Simulated network disconnect');
      });

      final info = await service.checkUpdate(forceRefresh: true);

      expect(info.type, equals(UpdateType.mandatory));
      expect(info.targetVersion, equals('2.0.0'));
    });

    test('follows fail-open strategy when no cache exists and network is down', () async {
      SharedPreferences.setMockInitialValues({}); // Empty cache

      final service = AppVersionService.instance;
      service.debugVersion = '1.0.0';
      service.debugBuildNumber = 1;
      service.debugClient = MockClient((request) async {
        throw Exception('Simulated total network failure');
      });

      final info = await service.checkUpdate(forceRefresh: true);

      expect(info.type, equals(UpdateType.none)); // Does not lock user out
    });

    test('postpone optional update records timestamp and suppresses prompt', () async {
      final service = AppVersionService.instance;
      expect(await service.shouldPromptOptional('3.0.0'), isTrue);

      await service.postponeOptionalUpdate('3.0.0');
      expect(await service.shouldPromptOptional('3.0.0'), isFalse);
      expect(await service.shouldPromptOptional('3.0.1'), isTrue); // Different version allowed
    });
  });

  group('HTTP Client Version Header Injection', () {
    test('attaches X-App-Id, X-App-Version, and X-App-Build headers to requests', () async {
      Map<String, String>? capturedHeaders;

      final mockClient = MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response('{"success": true}', 200);
      });

      app_http.debugSetClient(mockClient);

      AppVersionService.instance.debugVersion = '2.4.0';
      AppVersionService.instance.debugBuildNumber = 42;

      await app_http.get(Uri.parse('https://api.bookalook.in/api/customer/categories'));

      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!['X-App-Id'], equals('customer'));
      expect(capturedHeaders!['X-App-Version'], equals('2.4.0'));
      expect(capturedHeaders!['X-App-Build'], equals('42'));
    });
  });

  group('MandatoryUpdateScreen Widget', () {
    testWidgets('renders non-dismissible UI with required version and update button', (tester) async {
      const updateInfo = AppUpdateInfo(
        type: UpdateType.mandatory,
        currentVersion: '1.0.0',
        currentBuild: 1,
        targetVersion: '2.0.0',
        targetBuild: 20,
        message: 'A critical update is required to keep your account safe.',
        releaseNotes: 'Fixed booking synchronization.',
        storeUrl: 'https://play.google.com/store/apps/details?id=in.bookalook.app',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MandatoryUpdateScreen(updateInfo: updateInfo),
        ),
      );

      expect(find.text('Update Required'), findsOneWidget);
      expect(find.textContaining('Minimum required: v2.0.0 (Build #20)'), findsOneWidget);
      expect(find.textContaining('A critical update is required'), findsOneWidget);
      expect(find.text("What's New:"), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);

      // Verify PopScope cannot pop
      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });

  group('OptionalUpdateDialog Widget', () {
    testWidgets('renders dismissible optional update dialog with update and later buttons', (tester) async {
      const updateInfo = AppUpdateInfo(
        type: UpdateType.optional,
        currentVersion: '2.0.0',
        currentBuild: 20,
        targetVersion: '2.4.0',
        targetBuild: 42,
        message: 'A new version with faster load times is available.',
        releaseNotes: 'Performance enhancements',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OptionalUpdateDialog(updateInfo: updateInfo),
          ),
        ),
      );

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('Version 2.4.0'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);

      // Tap later to dismiss
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
    });
  });
}
