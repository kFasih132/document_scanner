import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';
import '../bloc/scanner_state.dart';

/// Reusable model selection list widget following Widget-First architecture.
class ModelSelectionTile extends StatelessWidget {
  final ScannerModelOption selectedModel;
  final ValueChanged<ScannerModelOption> onModelSelected;

  const ModelSelectionTile({
    super.key,
    required this.selectedModel,
    required this.onModelSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ModelOptionCard(
          option: ScannerModelOption.v1Fp32,
          title: 'V1 (FP32) Document Pose',
          subtitle: 'notes-v1.tflite (10.3 MB) • 100% stable live stream',
          badge: 'Recommended',
          badgeColor: Colors.teal,
          isSelected: selectedModel == ScannerModelOption.v1Fp32,
          onTap: () => onModelSelected(ScannerModelOption.v1Fp32),
        ),
        const SizedBox(height: AppSpacing.sm),
        ModelOptionCard(
          option: ScannerModelOption.v2W8A16,
          title: 'V2 (W8A16) Compressed',
          subtitle: 'notes-v2-n-w8a16.tflite (3.1 MB) • Fast low footprint',
          badge: 'Experimental',
          badgeColor: Colors.orange,
          isSelected: selectedModel == ScannerModelOption.v2W8A16,
          onTap: () => onModelSelected(ScannerModelOption.v2W8A16),
        ),
        const SizedBox(height: AppSpacing.sm),
        ModelOptionCard(
          option: ScannerModelOption.v4Fp32,
          title: 'V4 (FP32) Document Pose',
          subtitle: 'notes-v4.tflite (10.3 MB) • 100% stable live stream',
          badge: 'New',
          badgeColor: Colors.orange,
          isSelected: selectedModel == ScannerModelOption.v4Fp32,
          onTap: () => onModelSelected(ScannerModelOption.v4Fp32),
        ),
      ],
    );
  }
}

/// Standalone card widget for a single model option.
class ModelOptionCard extends StatelessWidget {
  final ScannerModelOption option;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final bool isSelected;
  final VoidCallback onTap;

  const ModelOptionCard({
    super.key,
    required this.option,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withAlpha(80);

    final cardBgColor = isSelected
        ? theme.colorScheme.primaryContainer.withAlpha(50)
        : theme.colorScheme.surfaceContainerLow;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.roundedMd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: AppSpacing.roundedMd,
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs + 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: AppSpacing.roundedSm,
                ),
                child: Icon(
                  Icons.psychology_rounded,
                  size: 20,
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs + 2,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withAlpha(35),
                            borderRadius: AppSpacing.roundedSm,
                            border: Border.all(
                              color: badgeColor.withAlpha(90),
                            ),
                          ),
                          child: Text(
                            badge,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: badgeColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
