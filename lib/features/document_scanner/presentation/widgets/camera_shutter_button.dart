import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class CameraShutterButton extends StatelessWidget {
  final VoidCallback? onCapture;
  final bool isCapturing;
  final int pageCount;

  const CameraShutterButton({
    super.key,
    required this.onCapture,
    this.isCapturing = false,
    this.pageCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSpacing.shutterButtonSize + 12,
      height: AppSpacing.shutterButtonSize + 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer White Ring
          Container(
            width: AppSpacing.shutterButtonSize,
            height: AppSpacing.shutterButtonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.cameraShutterRing,
                width: 4.0,
              ),
            ),
          ),

          // Inner Shutter Button
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isCapturing ? null : onCapture,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: isCapturing
                    ? AppSpacing.shutterInnerSize - 12
                    : AppSpacing.shutterInnerSize,
                height: isCapturing
                    ? AppSpacing.shutterInnerSize - 12
                    : AppSpacing.shutterInnerSize,
                decoration: BoxDecoration(
                  color: isCapturing ? AppColors.primary : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: isCapturing
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),

          // Batch count badge
          if (pageCount > 0)
            Positioned(
              top: 0,
              right: 0,
              child: ShutterBadgeCounter(count: pageCount),
            ),
        ],
      ),
    );
  }
}

class ShutterBadgeCounter extends StatelessWidget {
  final int count;

  const ShutterBadgeCounter({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs + 2),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 4.0,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
