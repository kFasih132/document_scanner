import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/scanned_document.dart';

class FilterPresetSelector extends StatelessWidget {
  final DocumentFilter activeFilter;
  final ValueChanged<DocumentFilter> onFilterSelected;

  const FilterPresetSelector({
    super.key,
    required this.activeFilter,
    required this.onFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 48,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: DocumentFilter.values.map((filter) {
              final isSelected = filter == activeFilter;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: FilterChipItem(
                  filter: filter,
                  isSelected: isSelected,
                  theme: theme,
                  onTap: () => onFilterSelected(filter),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class FilterChipItem extends StatelessWidget {
  final DocumentFilter filter;
  final bool isSelected;
  final ThemeData theme;
  final VoidCallback onTap;

  const FilterChipItem({
    super.key,
    required this.filter,
    required this.isSelected,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(
        filter.icon,
        size: 16,
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(filter.label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      selectedColor: theme.colorScheme.primaryContainer,
      shape: const RoundedRectangleBorder(borderRadius: AppSpacing.roundedFull),
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.5)
            : theme.colorScheme.outlineVariant,
      ),
      onSelected: (_) => onTap(),
    );
  }
}
