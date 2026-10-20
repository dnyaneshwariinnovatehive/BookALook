import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A modern, purpose-built hero art visual for the Partner Location Permission dialog.
///
/// Features an elevated 3D salon location beacon with concentric radar wave rings,
/// floating discovery and GPS status badges, and ambient glow accents.
class SalonIllustration extends StatelessWidget {
  const SalonIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      height: 115,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  const Color(0xFF261D3B),
                  const Color(0xFF1E1B2E),
                  AppTheme.darkSurface,
                ]
              : [
                  const Color(0xFFF3EAFF),
                  const Color(0xFFF8F4FF),
                  AppTheme.lightSurface,
                ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ambient radar wave rings
          _buildRadarRing(diameter: 140, opacity: isDark ? 0.06 : 0.05),
          _buildRadarRing(diameter: 100, opacity: isDark ? 0.10 : 0.08),
          _buildRadarRing(diameter: 68, opacity: isDark ? 0.16 : 0.12),

          // Soft ambient glow circle behind the beacon
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentColor.withValues(
                alpha: isDark ? 0.20 : 0.14,
              ),
            ),
          ),

          // Subtle decorative floating stars / dots
          Positioned(
            left: 38,
            top: 26,
            child: _buildSparkleDot(size: 5, alpha: isDark ? 0.35 : 0.30),
          ),
          Positioned(
            right: 46,
            bottom: 30,
            child: _buildSparkleDot(size: 4, alpha: isDark ? 0.30 : 0.25),
          ),
          Positioned(
            left: 54,
            bottom: 24,
            child: _buildSparkleDot(size: 3, alpha: isDark ? 0.25 : 0.20),
          ),

          // Central Elevated 3D Salon Location Beacon & Badges
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Main beacon circle
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.accentGradientStart,
                        AppTheme.accentGradientEnd,
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentColor.withValues(
                          alpha: isDark ? 0.45 : 0.32,
                        ),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: AppTheme.accentColor.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ),

                // Floating discovery beacon badge (Top-Right)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2E2744) : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.30 : 0.08,
                          ),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.near_me_rounded,
                        size: 12,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ),
                ),

                // Floating live GPS status indicator (Bottom-Left)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2E2744) : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.25 : 0.06,
                          ),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF10B981),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(
                                alpha: 0.50,
                              ),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarRing({required double diameter, required double opacity}) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: opacity),
          width: 1.2,
        ),
      ),
    );
  }

  Widget _buildSparkleDot({required double size, required double alpha}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.accentColor.withValues(alpha: alpha),
      ),
    );
  }
}
