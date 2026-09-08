import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../bloc/scanner_state.dart';

/// Reusable glassmorphic model toggle selector for switching between YOLO detection models.
/// Follows widget-first architecture and adapts smoothly between mobile and tablet viewports.
class ModelSelectorToggle extends StatelessWidget {
  final ScannerModelOption selectedModel;
  final ValueChanged<ScannerModelOption> onModelSelected;
  final bool isLoading;

  const ModelSelectorToggle({
    super.key,
    required this.selectedModel,
    required this.onModelSelected,
    this.isLoading = false,
  });

  void _showModelBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalContext) => ModelSelectionModalSheet(
        selectedModel: selectedModel,
        onModelSelected: (model) {
          Navigator.pop(modalContext);
          onModelSelected(model);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;

    if (!isTablet) {
      return CompactModelDropdownPill(
        selectedModel: selectedModel,
        isLoading: isLoading,
        onTap: () => _showModelBottomSheet(context),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.cameraControlGlass,
        borderRadius: AppSpacing.roundedFull,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ScannerModelOption.values.map((model) {
          final isSelected = model == selectedModel;
          return ModelOptionPill(
            model: model,
            isSelected: isSelected,
            isLoading: isSelected && isLoading,
            isTablet: true,
            onTap: () => onModelSelected(model),
          );
        }).toList(),
      ),
    );
  }
}

/// Compact glassmorphic pill for mobile viewports showing active model with dropdown indicator.
class CompactModelDropdownPill extends StatelessWidget {
  final ScannerModelOption selectedModel;
  final bool isLoading;
  final VoidCallback onTap;

  const CompactModelDropdownPill({
    super.key,
    required this.selectedModel,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.roundedFull,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.cameraControlGlass,
            borderRadius: AppSpacing.roundedFull,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.scannerLaser),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ] else ...[
                const Icon(
                  Icons.bolt_rounded,
                  size: 14,
                  color: AppColors.scannerLaser,
                ),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(
                  selectedModel.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ModelBadgeTag(
                badge: selectedModel.badge,
                isSelected: false,
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glassmorphic bottom sheet for selecting YOLO models on mobile.
class ModelSelectionModalSheet extends StatelessWidget {
  final ScannerModelOption selectedModel;
  final ValueChanged<ScannerModelOption> onModelSelected;

  const ModelSelectionModalSheet({
    super.key,
    required this.selectedModel,
    required this.onModelSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceContainer,
        borderRadius: AppSpacing.roundedXl,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: AppColors.scannerLaser,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Select YOLO Detection Model',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: AppSpacing.sm),
            ...ScannerModelOption.values.map((model) {
              final isSelected = model == selectedModel;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Material(
                  color: isSelected
                      ? AppColors.scannerLaser.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: AppSpacing.roundedMd,
                  child: InkWell(
                    onTap: () => onModelSelected(model),
                    borderRadius: AppSpacing.roundedMd,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: isSelected
                                ? AppColors.scannerLaser
                                : Colors.white54,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      model.title,
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    ModelBadgeTag(
                                      badge: model.badge,
                                      isSelected: isSelected,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  model.subtitle,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Focused single-responsibility pill widget for a specific [ScannerModelOption].
class ModelOptionPill extends StatelessWidget {
  final ScannerModelOption model;
  final bool isSelected;
  final bool isLoading;
  final bool isTablet;
  final VoidCallback onTap;

  const ModelOptionPill({
    super.key,
    required this.model,
    required this.isSelected,
    required this.isLoading,
    required this.isTablet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final horizontalPad = isTablet ? AppSpacing.md : AppSpacing.sm;
    final verticalPad = isTablet ? AppSpacing.xs : 3.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.roundedFull,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPad,
            vertical: verticalPad,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? (isLoading
                    ? AppColors.scannerLaser.withValues(alpha: 0.3)
                    : AppColors.scannerLaser)
                : Colors.transparent,
            borderRadius: AppSpacing.roundedFull,
            boxShadow: isSelected && !isLoading
                ? [
                    const BoxShadow(
                      color: AppColors.scannerLaserGlow,
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading) ...[
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                model.title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected ? Colors.black87 : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: isTablet ? 12 : 10,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              ModelBadgeTag(
                badge: model.badge,
                isSelected: isSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small visual badge showing model weight size (e.g. "3 MB" / "10 MB").
class ModelBadgeTag extends StatelessWidget {
  final String badge;
  final bool isSelected;

  const ModelBadgeTag({
    super.key,
    required this.badge,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 1.0,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.black.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: AppSpacing.roundedXs,
      ),
      child: Text(
        badge,
        style: TextStyle(
          color: isSelected ? Colors.black87 : Colors.white60,
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
