import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http_base;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum UpdateType {
  none,
  optional,
  mandatory,
}

class AppUpdateInfo {
  final UpdateType type;
  final String currentVersion;
  final int currentBuild;
  final String targetVersion;
  final int targetBuild;
  final String? message;
  final String? releaseNotes;
  final String? storeUrl;

  const AppUpdateInfo({
    required this.type,
    required this.currentVersion,
    required this.currentBuild,
    required this.targetVersion,
    required this.targetBuild,
    this.message,
    this.releaseNotes,
    this.storeUrl,
  });

  bool get isMandatory => type == UpdateType.mandatory;
  bool get isOptional => type == UpdateType.optional;
  bool get hasUpdate => type != UpdateType.none;
}

class AppVersionService {
  AppVersionService._();
  static final AppVersionService instance = AppVersionService._();

  static const String appId = 'customer';
  static const String _cachePolicyKey = 'cached_app_update_policy_customer';
  static const String _cacheTimestampKey = 'cached_app_update_policy_time_customer';
  static const String _postponeVersionKey = 'postponed_optional_version_customer';
  static const String _postponeTimeKey = 'postponed_optional_time_customer';

  // In-memory cache & throttle
  DateTime? _lastFetchTime;
  AppUpdateInfo? _cachedUpdateInfo;
  bool _isChecking = false;

  // Overrides for unit tests
  @visibleForTesting
  String? debugVersion;
  @visibleForTesting
  int? debugBuildNumber;
  @visibleForTesting
  http_base.Client? debugClient;

  /// Semantic version and build number comparison.
  /// Returns:
  ///   < 0 if (v1, b1) < (v2, b2)
  ///   = 0 if (v1, b1) == (v2, b2)
  ///   > 0 if (v1, b1) > (v2, b2)
  static int compareVersions(String v1, int b1, String v2, int b2) {
    final clean1 = v1.replaceAll(RegExp(r'^[vV]'), '').trim();
    final clean2 = v2.replaceAll(RegExp(r'^[vV]'), '').trim();

    final parts1 = clean1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = clean2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) {
        return p1.compareTo(p2);
      }
    }

    return b1.compareTo(b2);
  }

  /// Get currently installed version and build number.
  Future<Map<String, dynamic>> getInstalledVersion() async {
    if (debugVersion != null && debugBuildNumber != null) {
      return {
        'version': debugVersion!,
        'build_number': debugBuildNumber!,
      };
    }

    try {
      final info = await PackageInfo.fromPlatform();
      return {
        'version': info.version.isNotEmpty ? info.version : '1.0.0',
        'build_number': int.tryParse(info.buildNumber) ?? 1,
      };
    } catch (e) {
      // In tests or unsupported desktop platforms
      return {
        'version': debugVersion ?? '1.0.0',
        'build_number': debugBuildNumber ?? 1,
      };
    }
  }

  /// Resolve API base URL for update policy checks.
  String get _baseUrl {
    try {
      if (dotenv.isInitialized) {
        final configured = dotenv.env['API_BASE_URL'];
        if (configured != null && configured.trim().isNotEmpty) {
          return configured.trim();
        }
      }
    } catch (_) {}
    if (kIsWeb) return 'http://localhost:8000/api';
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000/api';
    return 'http://localhost:8000/api';
  }

  /// Detect platform name for query param
  String get _platformName {
    if (kIsWeb) return 'android';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  /// Evaluate update policy against installed version.
  Future<AppUpdateInfo> checkUpdate({bool forceRefresh = false}) async {
    if (_isChecking && _cachedUpdateInfo != null) {
      return _cachedUpdateInfo!;
    }

    // Throttle checks to once every 2 minutes unless forced
    if (!forceRefresh &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < const Duration(minutes: 2) &&
        _cachedUpdateInfo != null) {
      return _cachedUpdateInfo!;
    }

    _isChecking = true;

    try {
      final installed = await getInstalledVersion();
      final currentVersion = installed['version'] as String;
      final currentBuild = installed['build_number'] as int;

      final policyData = await _fetchPolicyWithCacheFallback(forceRefresh: forceRefresh);

      if (policyData == null || !(policyData['has_policy'] ?? false)) {
        _cachedUpdateInfo = AppUpdateInfo(
          type: UpdateType.none,
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          targetVersion: currentVersion,
          targetBuild: currentBuild,
        );
        _lastFetchTime = DateTime.now();
        return _cachedUpdateInfo!;
      }

      final isEnforcementActive = policyData['enforcement_active'] == true;
      final updateMode = policyData['update_mode'] as String? ?? 'optional';
      final minRelease = policyData['minimum'] as Map<String, dynamic>?;
      final latestRelease = policyData['latest'] as Map<String, dynamic>?;
      final message = policyData['message'] as String?;
      final storeUrl = _resolveStoreUrl(policyData);

      // 1. Check Mandatory Enforcement (below minimum version and enforcement is active)
      if (isEnforcementActive && minRelease != null) {
        final minVersion = minRelease['version'] as String? ?? '0.0.0';
        final minBuild = (minRelease['build_number'] as num?)?.toInt() ?? 0;

        if (compareVersions(currentVersion, currentBuild, minVersion, minBuild) < 0) {
          _cachedUpdateInfo = AppUpdateInfo(
            type: UpdateType.mandatory,
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            targetVersion: minVersion,
            targetBuild: minBuild,
            message: message,
            releaseNotes: minRelease['release_notes'] as String?,
            storeUrl: storeUrl,
          );
          _lastFetchTime = DateTime.now();
          return _cachedUpdateInfo!;
        }
      }

      // 2. Check if a newer version is published
      if (latestRelease != null) {
        final latestVersion = latestRelease['version'] as String? ?? currentVersion;
        final latestBuild = (latestRelease['build_number'] as num?)?.toInt() ?? currentBuild;

        if (compareVersions(currentVersion, currentBuild, latestVersion, latestBuild) < 0) {
          final isHardMandatory = isEnforcementActive && updateMode == 'mandatory';
          _cachedUpdateInfo = AppUpdateInfo(
            type: isHardMandatory ? UpdateType.mandatory : UpdateType.optional,
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            targetVersion: latestVersion,
            targetBuild: latestBuild,
            message: message,
            releaseNotes: latestRelease['release_notes'] as String?,
            storeUrl: storeUrl,
          );
          _lastFetchTime = DateTime.now();
          return _cachedUpdateInfo!;
        }
      }

      // 3. Current version satisfies all rules
      _cachedUpdateInfo = AppUpdateInfo(
        type: UpdateType.none,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        targetVersion: currentVersion,
        targetBuild: currentBuild,
      );
      _lastFetchTime = DateTime.now();
      return _cachedUpdateInfo!;
    } finally {
      _isChecking = false;
    }
  }

  /// Fetches policy from server with disk caching and sensible fail-open strategy.
  Future<Map<String, dynamic>?> _fetchPolicyWithCacheFallback({bool forceRefresh = false}) async {
    final client = debugClient ?? http_base.Client();

    try {
      final uri = Uri.parse('$_baseUrl/app-version/$appId?platform=$_platformName');
      final response = await client.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _savePolicyCache(data);
        return data;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[AppVersionService] Network check failed: $e. Falling back to cached policy.');
      }
    }

    // Network failed: attempt to retrieve cached policy from SharedPreferences
    return await _readPolicyCache();
  }

  /// Store policy payload in SharedPreferences.
  Future<void> _savePolicyCache(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachePolicyKey, jsonEncode(data));
      await prefs.setString(_cacheTimestampKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  /// Read cached policy with 24-hour validity window.
  Future<Map<String, dynamic>?> _readPolicyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cachePolicyKey);
      final cachedTimeStr = prefs.getString(_cacheTimestampKey);

      if (cachedJson == null || cachedTimeStr == null) {
        return null; // Fail-open: no cached policy ever obtained
      }

      final cachedTime = DateTime.tryParse(cachedTimeStr);
      if (cachedTime == null) return null;

      // Cache expires after 24 hours of total network failure
      if (DateTime.now().difference(cachedTime) > const Duration(hours: 24)) {
        return null;
      }

      return jsonDecode(cachedJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Resolve platform-specific store URL
  String? _resolveStoreUrl(Map<String, dynamic> policy) {
    if (policy['store_url'] != null && (policy['store_url'] as String).isNotEmpty) {
      return policy['store_url'] as String;
    }
    final storeUrls = policy['store_urls'] as Map<String, dynamic>?;
    if (storeUrls == null) return null;

    if (!kIsWeb && Platform.isIOS) {
      return storeUrls['ios'] as String?;
    }
    return storeUrls['android'] as String?;
  }

  /// Launch platform store URL in external browser/store app
  static Future<bool> launchStoreUrl(String? url) async {
    if (url == null || url.trim().isEmpty) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;

    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (kDebugMode) print('[AppVersionService] Could not launch store URL: $e');
    }
    return false;
  }

  /// Postpone prompt for this optional version
  Future<void> postponeOptionalUpdate(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_postponeVersionKey, version);
      await prefs.setString(_postponeTimeKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  /// Check whether optional update should be prompted
  Future<bool> shouldPromptOptional(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final postponedVer = prefs.getString(_postponeVersionKey);
      final postponedTimeStr = prefs.getString(_postponeTimeKey);

      if (postponedVer == version && postponedTimeStr != null) {
        final postponedTime = DateTime.tryParse(postponedTimeStr);
        if (postponedTime != null &&
            DateTime.now().difference(postponedTime) < const Duration(hours: 24)) {
          return false; // User postponed this version within last 24h
        }
      }
      return true;
    } catch (_) {
      return true;
    }
  }
}
