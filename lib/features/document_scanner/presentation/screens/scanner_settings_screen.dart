import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/yolo_vision/models/yolo_model_config.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import '../widgets/hardware_acceleration_selector.dart';
import '../widgets/model_selection_tile.dart';
import '../widgets/settings_slider_tile.dart';

/// Screen for configuring YOLO detection parameters, hardware acceleration,
/// and AI model choices safely.
///
/// Strictly follows Widget-First Architecture with zero helper UI methods.
class ScannerSettingsScreen extends StatelessWidget {
  const ScannerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Scanner & AI Config',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [
          SettingsResetActionButton(),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: BlocBuilder<ScannerBloc, ScannerState>(
        builder: (context, state) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                children: [
                  // Section 1: Active Model Selection
                  const SettingsSectionHeader(
                    icon: Icons.psychology_rounded,
                    title: 'YOLO Detection Model',
                    subtitle:
                        'Select neural network weights for document edge detection',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ModelSelectionTile(
                    selectedModel: state.activeModel,
                    onModelSelected: (model) {
                      context.read<ScannerBloc>().add(
                            UpdateScannerConfigEvent(model: model),
                          );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Section 2: Hardware Acceleration
                  const SettingsSectionHeader(
                    icon: Icons.bolt_rounded,
                    title: 'Hardware Acceleration',
                    subtitle:
                        'Choose execution backend delegate for TensorFlow Lite runtime',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  HardwareAccelerationSelector(
                    selectedDelegate: state.hardwareDelegate,
                    onDelegateSelected: (delegate) {
                      context.read<ScannerBloc>().add(
                            UpdateScannerConfigEvent(
                              hardwareDelegate: delegate,
                            ),
                          );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Section 3: Detection Sensitivity & Overlap Thresholds
                  const SettingsSectionHeader(
                    icon: Icons.tune_rounded,
                    title: 'Detection Thresholds',
                    subtitle:
                        'Safely tune confidence filtering and Non-Maximum Suppression (IoU)',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SettingsSliderTile(
                    icon: Icons.verified_user_rounded,
                    title: 'Confidence Threshold',
                    description:
                        'Minimum probability required to accept a detected document box. Lower values capture faint documents; higher values avoid false edges.',
                    value: state.confThreshold,
                    min: 0.10,
                    max: 0.90,
                    divisions: 16,
                    valueFormatter: (val) => '${(val * 100).round()}%',
                    minLabel: '10% (Sensitive)',
                    maxLabel: '90% (Strict)',
                    onChanged: (newConf) {
                      context.read<ScannerBloc>().add(
                            UpdateScannerConfigEvent(confThreshold: newConf),
                          );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SettingsSliderTile(
                    icon: Icons.layers_rounded,
                    title: 'IoU Threshold (Overlap)',
                    description:
                        'Intersection-over-Union threshold for multi-box suppression. Regulates how strictly overlapping candidates are merged.',
                    value: state.iouThreshold,
                    min: 0.10,
                    max: 0.90,
                    divisions: 16,
                    valueFormatter: (val) => '${(val * 100).round()}%',
                    minLabel: '10% (Aggressive NMS)',
                    maxLabel: '90% (Permissive)',
                    onChanged: (newIou) {
                      context.read<ScannerBloc>().add(
                            UpdateScannerConfigEvent(iouThreshold: newIou),
                          );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Section 4: Engine Status Card
                  EngineStatusCard(
                    statusMessage: state.statusMessage ?? 'Engine active',
                    activeModel: state.activeModel,
                    delegate: state.hardwareDelegate,
                    isModelLoaded: state.isModelLoaded,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Standalone action button for restoring default settings in the AppBar.
class SettingsResetActionButton extends StatelessWidget {
  const SettingsResetActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.restart_alt_rounded),
      tooltip: 'Reset to Defaults',
      onPressed: () {
        showDialog<bool>(
          context: context,
          builder: (dialogContext) => const ResetSettingsConfirmDialog(),
        ).then((confirmed) {
          if (confirmed == true && context.mounted) {
            context.read<ScannerBloc>().add(const ResetScannerConfigEvent());
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Settings reset to recommended defaults (10 MB V1, CPU, 25% Conf, 45% IoU)',
                ),
                duration: Duration(seconds: 3),
              ),
            );
          }
        });
      },
    );
  }
}

/// Standalone dialog for confirming settings reset.
class ResetSettingsConfirmDialog extends StatelessWidget {
  const ResetSettingsConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.restart_alt_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          const Text('Reset Configuration?'),
        ],
      ),
      content: const Text(
        'This will reset Confidence to 25%, IoU to 45%, Hardware Acceleration to CPU, and restore the stable 10 MB model.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Reset'),
        ),
      ],
    );
  }
}

/// Standalone section header widget.
class SettingsSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const SettingsSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs + 2),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
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
    );
  }
}

/// Standalone card displaying live engine status and active runtime specs.
class EngineStatusCard extends StatelessWidget {
  final String statusMessage;
  final ScannerModelOption activeModel;
  final YoloHardwareDelegate delegate;
  final bool isModelLoaded;

  const EngineStatusCard({
    super.key,
    required this.statusMessage,
    required this.activeModel,
    required this.delegate,
    required this.isModelLoaded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.roundedMd,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isModelLoaded
                      ? Icons.check_circle_rounded
                      : Icons.hourglass_top_rounded,
                  size: 18,
                  color: isModelLoaded ? Colors.teal : Colors.amber.shade800,
                ),
                const SizedBox(width: AppSpacing.xs + 2),
                Expanded(
                  child: Text(
                    'Runtime Status: $statusMessage',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Input Tensor Size',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  '768 × 768 (NCHW Float32)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Model Footprint',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  '${activeModel.title} • ${activeModel.badge}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Delegate Engine',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  delegate.name.toUpperCase(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
