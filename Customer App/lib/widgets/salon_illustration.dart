import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SalonIllustration extends StatelessWidget {
  const SalonIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 230,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: context.colors.accentSoft, // Light soft background matching modal
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Background city skyline
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: _buildCityScape(),
          ),
          
          // Floor base
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, -2))
                ]
              ),
            ),
          ),
          
          // Salon Storefront
          Positioned(
            bottom: 20,
            child: _buildStorefront(),
          ),

          // Plant
          Positioned(
            bottom: 20,
            left: 20,
            child: _buildDetailedPlant(),
          ),

          // Map card
          Positioned(
            bottom: 10,
            right: 15,
            child: Transform.rotate(
              angle: -0.05,
              child: _buildDetailedMapCard(),
            ),
          ),

          // Big Purple Pin & Cutout
          Positioned(
            bottom: 120,
            child: _buildPinArea(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCityScape() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCityBuilding(40, 80),
        _buildCityBuilding(30, 110),
        _buildCityBuilding(50, 60),
        _buildCityBuilding(45, 90),
        _buildCityBuilding(35, 120),
        _buildCityBuilding(40, 70),
      ],
    );
  }

  Widget _buildCityBuilding(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFFE5E0F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          (height / 20).floor(),
          (index) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Container(width: 8, height: 8, color: const Color(0xFFDCD5EE)),
              Container(width: 8, height: 8, color: const Color(0xFFDCD5EE)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStorefront() {
    return Container(
      width: 220,
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFFE9E5F2), // Building base color
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Inner glow / warm light
          Positioned(
            top: 15,
            left: 8,
            right: 8,
            bottom: 4,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFDF5E6), // very warm white
              ),
              child: Row(
                children: [
                  // Left door
                  Container(
                    width: 70,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF3B3B4F), width: 3),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFBE4D2), Color(0xFFFDF0E6)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Door handle
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(color: AppTheme.accentGradientLightEnd, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Right wide window
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: const Border(
                          top: BorderSide(color: Color(0xFF3B3B4F), width: 3),
                          right: BorderSide(color: Color(0xFF3B3B4F), width: 3),
                          bottom: BorderSide(color: Color(0xFF3B3B4F), width: 3),
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFBE4D2), Color(0xFFFDF0E6)],
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // Table
                          Positioned(
                            bottom: 10,
                            child: Container(
                              width: 30,
                              height: 15,
                              decoration: const BoxDecoration(
                                border: Border(top: BorderSide(color: Color(0xFF5A5A72), width: 3)),
                              ),
                              child: Center(
                                child: Container(width: 6, height: 12, color: const Color(0xFF5A5A72)),
                              ),
                            ),
                          ),
                          // Chairs
                          Positioned(
                            bottom: 10,
                            left: 10,
                            child: _buildChair(false),
                          ),
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: _buildChair(true),
                          ),
                          // Mirrors
                          Positioned(
                            top: 10,
                            left: 20,
                            child: _buildMirror(),
                          ),
                          Positioned(
                            top: 10,
                            right: 20,
                            child: _buildMirror(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Awning / Roof
          Positioned(
            top: -15,
            left: -10,
            right: -10,
            child: Container(
              height: 35,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 4))
                ]
              ),
              child: Row(
                children: List.generate(6, (index) {
                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: index % 2 == 0 ? AppTheme.accentColor : AppTheme.accentGradientEnd,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: index % 2 == 0 
                            ? [AppTheme.accentGradientLightEnd, AppTheme.accentColor]
                            : [AppTheme.accentColor, AppTheme.accentGradientEnd],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChair(bool faceLeft) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.rotationY(faceLeft ? 3.14159 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppTheme.accentColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Container(
            width: 16,
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.accentGradientEnd,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            width: 4,
            height: 8,
            color: const Color(0xFF5A5A72),
          ),
        ],
      ),
    );
  }

  Widget _buildMirror() {
    return Container(
      width: 18,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accentGradientEnd, width: 2),
        color: const Color(0xFFFDFDFD),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 2))
        ]
      ),
    );
  }

  Widget _buildDetailedPlant() {
    return SizedBox(
      width: 40,
      height: 70,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Pot Base
          Container(
            width: 22,
            height: 20,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.accentColor, AppTheme.accentGradientEnd]),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
            ),
          ),
          // Pot Rim
          Positioned(
            bottom: 18,
            child: Container(
              width: 26,
              height: 6,
              decoration: BoxDecoration(
                color: AppTheme.accentGradientLightEnd,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Leaves (Custom Shapes)
          Positioned(
            bottom: 22,
            child: _buildLeaf(24, 35, 0, const Color(0xFF5F9E63)),
          ),
          Positioned(
            bottom: 24,
            left: -5,
            child: _buildLeaf(20, 28, -0.6, const Color(0xFF78B37A)),
          ),
          Positioned(
            bottom: 24,
            right: -5,
            child: _buildLeaf(20, 28, 0.6, const Color(0xFF78B37A)),
          ),
          Positioned(
            bottom: 30,
            left: 2,
            child: _buildLeaf(16, 22, -0.3, const Color(0xFF91CC93)),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaf(double width, double height, double angle, Color color) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedMapCard() {
    return Container(
      width: 90,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFF0F0F0), width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          children: [
            // Map background grid / blocks
            Positioned(top: -10, left: -20, child: Container(width: 120, height: 40, color: const Color(0xFFF3F4F6))),
            Positioned(top: 20, left: 30, child: Container(width: 80, height: 60, color: const Color(0xFFE5E7EB))),
            Positioned(bottom: -10, left: -10, child: Container(width: 60, height: 40, color: const Color(0xFFEFF6FF))),

            // Roads
            Positioned(top: 10, left: 0, right: 0, child: Container(height: 6, color: Colors.white)),
            Positioned(top: 40, left: 0, right: 0, child: Container(height: 8, color: Colors.white)),
            Positioned(left: 30, top: 0, bottom: 0, child: Container(width: 7, color: Colors.white)),

            // Dotted red route
            Positioned(
              bottom: 10,
              left: 20,
              child: Transform.rotate(
                angle: -0.3,
                child: Container(
                  width: 30,
                  height: 25,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: const Color(0xFFF43F5E), width: 4),
                      right: BorderSide(color: const Color(0xFFF43F5E), width: 4),
                    ),
                    borderRadius: const BorderRadius.only(bottomRight: Radius.circular(10)),
                  ),
                ),
              ),
            ),
            
            // Route end dot
            Positioned(
              bottom: 18,
              left: 15,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFE11D48),
                  shape: BoxShape.circle,
                ),
              ),
            ),

            // Map Pin target circles
            Positioned(
              top: 35,
              left: 35,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFCA5A5), width: 2),
                ),
              ),
            ),

            // Green Pin
            const Positioned(
              top: 12,
              left: 30,
              child: Icon(Icons.location_on, color: Color(0xFF22C55E), size: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinArea(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 90,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // White Cutout in the roof
          Positioned(
            bottom: 0,
            child: Container(
              width: 70,
              height: 35,
              decoration: BoxDecoration(
                color: context.colors.accentSoft, // Match background to simulate cutout
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(35)),
              ),
            ),
          ),
          
          // Big Purple Pin (Animated slightly if desired, or static)
          const Positioned(
            top: 0,
            child: _AnimatedBigPin(),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBigPin extends StatefulWidget {
  const _AnimatedBigPin();

  @override
  State<_AnimatedBigPin> createState() => _AnimatedBigPinState();
}

class _AnimatedBigPinState extends State<_AnimatedBigPin> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  late final Animation<double> _animation = Tween<double>(begin: 0, end: -8).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 3D Shadow/Glow
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentColor.withValues(alpha: 0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // Main Pin 
          const Icon(
            Icons.location_on,
            size: 72,
            color: AppTheme.accentColor,
          ),
          // Inner White Dot
          Positioned(
            top: 16,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
