import 'package:flutter/material.dart';

class ParallaxHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double maxHeight;
  final double minHeight;
  final String title;
  final String imageUrl;

  ParallaxHeaderDelegate({
    required this.maxHeight,
    required this.minHeight,
    required this.title,
    required this.imageUrl,
  });

  @override
  double get maxExtent => maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  bool shouldRebuild(covariant ParallaxHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        title != oldDelegate.title ||
        imageUrl != oldDelegate.imageUrl;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Progress from 0.0 (fully expanded) to 1.0 (fully collapsed)
    final double progress = (shrinkOffset / (maxHeight - minHeight)).clamp(
      0.0,
      1.0,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Background Image with Parallax Translation
        ClipRect(
          child: Transform.translate(
            // Moves background at half-speed upward as user scrolls down
            offset: Offset(0, -shrinkOffset * 0.5),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
        ),

        // 2. Darkening Gradient Overlay (intensifies as header collapses)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.3 + (0.4 * progress)),
                Colors.black.withValues(alpha: 0.6),
              ],
            ),
          ),
        ),

        // 3. Expanded Title (Fades out and scales down)
        Positioned(
          left: 20,
          bottom: 24,
          child: Opacity(
            opacity: (1.0 - (progress * 1.5)).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -shrinkOffset * 0.2),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),

        // 4. Collapsed Navigation Bar Title (Fades in near full collapse)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: minHeight,
          child: Container(
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 16),
            child: Opacity(
              opacity: (progress > 0.8) ? ((progress - 0.8) / 0.2) : 0.0,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
