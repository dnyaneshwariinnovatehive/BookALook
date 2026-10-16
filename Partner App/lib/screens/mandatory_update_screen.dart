import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_version_service.dart';
import '../theme/app_theme.dart';
import 'splash_screen.dart';

class MandatoryUpdateScreen extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const MandatoryUpdateScreen({
    super.key,
    required this.updateInfo,
  });

  @override
  State<MandatoryUpdateScreen> createState() => _MandatoryUpdateScreenState();
}

class _MandatoryUpdateScreenState extends State<MandatoryUpdateScreen>
    with WidgetsBindingObserver {
  bool _isLaunching = false;
  bool _isRechecking = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheckVersion();
    }
  }

  Future<void> _recheckVersion() async {
    if (_isRechecking) return;
    setState(() {
      _isRechecking = true;
      _errorMessage = null;
    });

    final info = await AppVersionService.instance.checkUpdate(forceRefresh: true);
    if (!mounted) return;

    setState(() {
      _isRechecking = false;
    });

    if (info.type != UpdateType.mandatory) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _handleUpdateNow() async {
    setState(() {
      _isLaunching = true;
      _errorMessage = null;
    });

    final storeUrl = widget.updateInfo.storeUrl;
    final success = await AppVersionService.launchStoreUrl(storeUrl);

    if (!mounted) return;

    setState(() {
      _isLaunching = false;
      if (!success) {
        _errorMessage =
            'Could not open the app store link automatically. Please open the Play Store or App Store and search for "BookALook Partner".';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              children: [
                const Spacer(),

                // Visual Icon Badge
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentColor.withValues(alpha: 0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.storefront_rounded,
                      color: Colors.white,
                      size: 52,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                Text(
                  'Partner App Update Required',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Description
                Text(
                  widget.updateInfo.message ??
                      'An update to BookALook Partner is mandatory to maintain salon booking sync, appointment billing, and staff schedules.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.5,
                    color: bodyColor,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Version Badge Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.accentColor),
                      const SizedBox(width: 8),
                      Text(
                        'Required: v${widget.updateInfo.targetVersion} (Build #${widget.updateInfo.targetBuild})',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Release notes if available
                if (widget.updateInfo.releaseNotes != null &&
                    widget.updateInfo.releaseNotes!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Partner Improvements:",
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.updateInfo.releaseNotes!,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            height: 1.45,
                            color: bodyColor,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.lightDangerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.lightDanger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: AppTheme.lightDanger,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const Spacer(),

                // Primary Update Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLaunching ? null : _handleUpdateNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLaunching
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.open_in_new_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Update Partner App',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // Recheck status button
                TextButton(
                  onPressed: _isRechecking ? null : _recheckVersion,
                  child: _isRechecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Already updated? Tap to refresh',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: bodyColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
