import 'package:flutter/material.dart';

class ScrollMotionItem extends StatelessWidget {
  final ScrollController scrollController;
  final int index;
  final double itemHeight;
  final Widget child;

  const ScrollMotionItem({
    super.key,
    required this.scrollController,
    required this.index,
    required this.itemHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, staticChild) {
        if (!scrollController.hasClients) {
          return SizedBox(height: itemHeight, child: staticChild);
        }

        final double currentOffset = scrollController.offset;
        final double itemTop = index * itemHeight;
        final double distanceFromTop = itemTop - currentOffset;

        // Calculates collapse progress when scrolling off the top of the viewport
        double progress = 1.0;
        if (distanceFromTop < 0) {
          progress = (1.0 + (distanceFromTop / itemHeight)).clamp(0.0, 1.0);
        }

        final double scale = 0.85 + (0.15 * progress);
        final double opacity = progress.clamp(0.0, 1.0);

        return SizedBox(
          height: itemHeight,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Opacity(opacity: opacity, child: staticChild),
          ),
        );
      },
      child: child,
    );
  }
}
