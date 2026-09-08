import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../bloc/scanner_state.dart';
import 'model_selector_toggle.dart';

class CameraControlsHeader extends StatelessWidget {
  final bool isFlashOn;
  final bool isAutoCapture;
  final ScannerModelOption activeModel;
  final ValueChanged<ScannerModelOption> onSelectModel;
  final bool isModelLoading;
  final VoidCallback onClose;
  final VoidCallback onToggleFlash;
  final VoidCallback onToggleAutoCapture;

  const CameraControlsHeader({
    super.key,
    required this.isFlashOn,
    required this.isAutoCapture,
    required this.activeModel,
    required this.onSelectModel,
    this.isModelLoading = false,
    required this.onClose,
    required this.onToggleFlash,
    required this.onToggleAutoCapture,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
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

            // Model Switcher Pill Toggle
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: ModelSelectorToggle(
                  selectedModel: activeModel,
                  onModelSelected: onSelectModel,
                  isLoading: isModelLoading,
                ),
              ),
            ),

            // Camera Action Group
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
                const SizedBox(width: AppSpacing.xs),

                // Auto Capture Toggle
                AutoCaptureToggleChip(
                  isAuto: isAutoCapture,
                  onTap: onToggleAutoCapture,
                ),
              ],
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
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs + 1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAuto ? Icons.auto_mode_rounded : Icons.touch_app_rounded,
                size: 15,
                color: isAuto ? Colors.black : Colors.white,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                isAuto ? 'AUTO' : 'MANUAL',
                style: TextStyle(
                  color: isAuto ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10.5,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
