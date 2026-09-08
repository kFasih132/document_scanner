import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/yolo_vision/models/yolo_model_config.dart';

/// Interactive hardware acceleration delegate selector widget.
///
/// Follows strict Widget-First principles without helper UI methods.
class HardwareAccelerationSelector extends StatelessWidget {
  final YoloHardwareDelegate selectedDelegate;
  final ValueChanged<YoloHardwareDelegate> onDelegateSelected;

  const HardwareAccelerationSelector({
    super.key,
    required this.selectedDelegate,
    required this.onDelegateSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HardwareDelegateCard(
          delegate: YoloHardwareDelegate.cpu,
          title: 'CPU Multi-Threaded',
          subtitle: 'XNNPACK (6 threads) • 100% Reliable • 0 crashes',
          badge: 'Most Stable',
          badgeColor: Colors.teal,
          icon: Icons.memory_rounded,
          isSelected: selectedDelegate == YoloHardwareDelegate.cpu,
          onTap: () => onDelegateSelected(YoloHardwareDelegate.cpu),
        ),
        const SizedBox(height: AppSpacing.sm),
        HardwareDelegateCard(
          delegate: YoloHardwareDelegate.gpu,
          title: 'GPU Acceleration',
          subtitle: 'Vulkan / OpenGL V2 • Lowest frame latency',
          badge: 'High Speed',
          badgeColor: Colors.deepPurple,
          icon: Icons.speed_rounded,
          isSelected: selectedDelegate == YoloHardwareDelegate.gpu,
          onTap: () => onDelegateSelected(YoloHardwareDelegate.gpu),
        ),
        const SizedBox(height: AppSpacing.sm),
        HardwareDelegateCard(
          delegate: YoloHardwareDelegate.nnapi,
          title: 'Android NNAPI',
          subtitle: 'System NPU / Qualcomm Hexagon / Tensor chip',
          badge: 'NPU Engine',
          badgeColor: Colors.amber.shade900,
          icon: Icons.developer_board_rounded,
          isSelected: selectedDelegate == YoloHardwareDelegate.nnapi,
          onTap: () => onDelegateSelected(YoloHardwareDelegate.nnapi),
        ),
        const SizedBox(height: AppSpacing.sm),
        HardwareDelegateCard(
          delegate: YoloHardwareDelegate.auto,
          title: 'Auto Delegate',
          subtitle: 'Tries GPU, then NNAPI, and falls back to CPU',
          badge: 'Adaptive',
          badgeColor: Colors.blue,
          icon: Icons.auto_awesome_rounded,
          isSelected: selectedDelegate == YoloHardwareDelegate.auto,
          onTap: () => onDelegateSelected(YoloHardwareDelegate.auto),
        ),
      ],
    );
  }
}

/// Standalone card widget representing a single execution delegate option.
class HardwareDelegateCard extends StatelessWidget {
  final YoloHardwareDelegate delegate;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const HardwareDelegateCard({
    super.key,
    required this.delegate,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.icon,
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
                  icon,
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
