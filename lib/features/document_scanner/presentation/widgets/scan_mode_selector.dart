import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/scanned_document.dart';

class ScanModeSelector extends StatelessWidget {
  final ScanMode activeMode;
  final ValueChanged<ScanMode> onModeSelected;

  const ScanModeSelector({
    super.key,
    required this.activeMode,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: ScanMode.values.map((mode) {
              final isSelected = mode == activeMode;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: ScanModePill(
                  mode: mode,
                  isSelected: isSelected,
                  onTap: () => onModeSelected(mode),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class ScanModePill extends StatelessWidget {
  final ScanMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  const ScanModePill({
    super.key,
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? Colors.white : Colors.transparent,
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
                mode.icon,
                size: 16,
                color: isSelected ? Colors.black : Colors.white70,
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                mode.label,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
