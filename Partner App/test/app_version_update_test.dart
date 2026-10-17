import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:partner_app/services/api_config.dart';
import 'package:partner_app/services/app_version_service.dart';
import 'package:partner_app/screens/mandatory_update_screen.dart';
import 'package:partner_app/widgets/optional_update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final service = AppVersionService.instance;
    service.debugVersion = '1.0.0';
    service.debugBuildNumber = 1;
    service.debugClient = null;
  });

  tearDown(() {
    AppVersionService.instance.debugVersion = null;
    AppVersionService.instance.debugBuildNumber = null;
    AppVersionService.instance.debugClient = null;
  });

  group('Partner App Semantic Version Comparison', () {
    test('compares partner versions accurately', () {
      expect(AppVersionService.compareVersions('1.0.0', 1, '1.0.0', 1), equals(0));
      expect(AppVersionService.compareVersions('1.0.0', 1, '1.0.1', 1), lessThan(0));
      expect(AppVersionService.compareVersions('1.2.0', 5, '1.1.9', 50), greaterThan(0));
      expect(AppVersionService.compareVersions('v2.0.0', 10, '2.0.0', 10), equals(0));

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

  group('Partner AppVersionService Policy Evaluation', () {
    test('flags mandatory update when partner app version is outdated', () async {
      final mockResponse = jsonEncode({
        'success': true,
        'app': 'partner',
        'has_policy': true,
        'enforcement_active': true,
        'update_mode': 'mandatory',
        'message': 'Partner app update required for settlement syncing.',
        'minimum': {
          'version': '1.5.0',
          'build_number': 20,
          'release_notes': 'Settlement and payout calculation upgrade',
        },
        'latest': {
          'version': '1.6.0',
          'build_number': 25,
        },
        'store_urls': {
          'android': 'https://play.google.com/store/apps/details?id=in.bookalook.partner',
        },
      });

      final service = AppVersionService.instance;
      service.debugVersion = '1.2.0';
      service.debugBuildNumber = 10;
      service.debugClient = MockClient((request) async {
        return http.Response(mockResponse, 200);
      });

      final info = await service.checkUpdate(forceRefresh: true);

      expect(info.type, equals(UpdateType.mandatory));
      expect(info.isMandatory, isTrue);
      expect(info.targetVersion, equals('1.5.0'));
      expect(info.targetBuild, equals(20));
      expect(info.message, equals('Partner app update required for settlement syncing.'));
    });

    test('flags optional update when partner app meets minimum but has new release', () async {
      final mockResponse = jsonEncode({
        'success': true,
        'app': 'partner',
        'has_policy': true,
        'enforcement_active': false,
        'update_mode': 'optional',
        'minimum': {
          'version': '1.0.0',
          'build_number': 1,
        },
        'latest': {
          'version': '1.5.0',
          'build_number': 20,
          'release_notes': 'New staff calendar view',
        },
      });

      final service = AppVersionService.instance;
      service.debugVersion = '1.2.0';
      service.debugBuildNumber = 10;
      service.debugClient = MockClient((request) async {
        return http.Response(mockResponse, 200);
      });

      final info = await service.checkUpdate(forceRefresh: true);

      expect(info.type, equals(UpdateType.optional));
      expect(info.isOptional, isTrue);
      expect(info.targetVersion, equals('1.5.0'));
    });

    test('recovers policy from disk cache when offline', () async {
      final cachedPolicy = jsonEncode({
        'has_policy': true,
        'enforcement_active': true,
        'update_mode': 'mandatory',
        'minimum': {
          'version': '1.5.0',
          'build_number': 20,
        },
        'latest': {
          'version': '1.6.0',
          'build_number': 25,
        },
      });

      SharedPreferences.setMockInitialValues({
        'cached_app_update_policy_partner': cachedPolicy,
        'cached_app_update_policy_time_partner': DateTime.now().toIso8601String(),
      });

      final service = AppVersionService.instance;
      service.debugVersion = '1.1.0';
      service.debugBuildNumber = 5;
      service.debugClient = MockClient((request) async {
        throw Exception('Offline network simulation');
      });

      final info = await service.checkUpdate(forceRefresh: true);

      expect(info.type, equals(UpdateType.mandatory));
      expect(info.targetVersion, equals('1.5.0'));
    });

    test('fails open without locking user out if offline and no cache exists', () async {
      SharedPreferences.setMockInitialValues({});

      final service = AppVersionService.instance;
      service.debugVersion = '1.0.0';
      service.debugBuildNumber = 1;
      service.debugClient = MockClient((request) async {
        throw Exception('Offline network simulation');
      });

      final info = await service.checkUpdate(forceRefresh: true);

      expect(info.type, equals(UpdateType.none));
    });

    test('postpones optional update for 24 hours', () async {
      final service = AppVersionService.instance;
      expect(await service.shouldPromptOptional('1.8.0'), isTrue);

      await service.postponeOptionalUpdate('1.8.0');
      expect(await service.shouldPromptOptional('1.8.0'), isFalse);
    });
  });

  group('Partner ApiConfig Header Generation', () {
    test('generates headers containing partner app identifier and version info', () async {
      AppVersionService.instance.debugVersion = '1.4.0';
      AppVersionService.instance.debugBuildNumber = 14;

      final headers = await ApiConfig.headers();

      expect(headers['X-App-Id'], equals('partner'));
      expect(headers['X-App-Version'], equals('1.4.0'));
      expect(headers['X-App-Build'], equals('14'));
    });
  });

  group('Partner MandatoryUpdateScreen Widget', () {
    testWidgets('renders non-dismissible blocking partner update screen', (tester) async {
      const updateInfo = AppUpdateInfo(
        type: UpdateType.mandatory,
        currentVersion: '1.0.0',
        currentBuild: 1,
        targetVersion: '1.5.0',
        targetBuild: 20,
        message: 'An update to BookALook Partner is mandatory.',
        releaseNotes: 'Performance enhancements',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: MandatoryUpdateScreen(updateInfo: updateInfo),
        ),
      );

      expect(find.text('Partner App Update Required'), findsOneWidget);
      expect(find.textContaining('Required: v1.5.0 (Build #20)'), findsOneWidget);
      expect(find.text('Update Partner App'), findsOneWidget);

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });

  group('Partner OptionalUpdateDialog Widget', () {
    testWidgets('renders optional update prompt with Later and Update buttons', (tester) async {
      const updateInfo = AppUpdateInfo(
        type: UpdateType.optional,
        currentVersion: '1.2.0',
        currentBuild: 10,
        targetVersion: '1.5.0',
        targetBuild: 20,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OptionalUpdateDialog(updateInfo: updateInfo),
          ),
        ),
      );

      expect(find.text('Partner App Update'), findsOneWidget);
      expect(find.text('Version 1.5.0'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
    });
  });
}
