import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class CameraControlsHeader extends StatelessWidget {
  final bool isFlashOn;
  final bool isAutoCapture;
  final VoidCallback onClose;
  final VoidCallback onToggleFlash;
  final VoidCallback onToggleAutoCapture;

  const CameraControlsHeader({
    super.key,
    required this.isFlashOn,
    required this.isAutoCapture,
    required this.onClose,
    required this.onToggleFlash,
    required this.onToggleAutoCapture,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black87,
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Close Button
            HeaderIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close scanner',
              onPressed: onClose,
            ),

            // Middle Action Group
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Flash Toggle
                HeaderIconButton(
                  icon: isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  tooltip: isFlashOn ? 'Flash On' : 'Flash Off',
                  isActive: isFlashOn,
                  onPressed: onToggleFlash,
                ),
                const SizedBox(width: AppSpacing.sm),

                // Auto Capture Toggle
                AutoCaptureToggleChip(
                  isAuto: isAutoCapture,
                  onTap: onToggleAutoCapture,
                ),
              ],
            ),

            // Settings/Help Button
            const HeaderIconButton(
              icon: Icons.grid_on_rounded,
              tooltip: 'Grid lines',
            ),
          ],
        ),
      ),
    );
  }
}

class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback? onPressed;

  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.isActive = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive ? Colors.white : AppColors.cameraControlGlass,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Icon(
              icon,
              size: AppSpacing.iconMd,
              color: isActive ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class AutoCaptureToggleChip extends StatelessWidget {
  final bool isAuto;
  final VoidCallback onTap;

  const AutoCaptureToggleChip({
    super.key,
    required this.isAuto,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isAuto ? Colors.white : AppColors.cameraControlGlass,
      borderRadius: AppSpacing.roundedFull,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAuto ? Icons.auto_mode_rounded : Icons.touch_app_rounded,
                size: 16,
                color: isAuto ? Colors.black : Colors.white,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                isAuto ? 'AUTO' : 'MANUAL',
                style: TextStyle(
                  color: isAuto ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
