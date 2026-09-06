import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/scanned_document.dart';

class BatchThumbnailTray extends StatelessWidget {
  final List<ScannedPage> pages;
  final ValueChanged<int> onPageTapped;
  final VoidCallback onReviewAll;

  const BatchThumbnailTray({
    super.key,
    required this.pages,
    required this.onPageTapped,
    required this.onReviewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: AppColors.cameraOverlayDark,
        borderRadius: AppSpacing.roundedXl,
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          // Thumbnails scroll
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              itemCount: pages.length,
              separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                return ThumbnailCard(
                  page: pages[index],
                  index: index,
                  onTap: () => onPageTapped(index),
                );
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Done / Proceed button with count
          DoneReviewButton(
            count: pages.length,
            onPressed: onReviewAll,
          ),
        ],
      ),
    );
  }
}

class ThumbnailCard extends StatelessWidget {
  final ScannedPage page;
  final int index;
  final VoidCallback onTap;

  const ThumbnailCard({
    super.key,
    required this.page,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isLocalFile = File(page.imagePath).existsSync();

    return Material(
      color: Colors.white12,
      borderRadius: AppSpacing.roundedSm,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 60,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isLocalFile)
                Image.file(
                  File(page.imagePath),
                  fit: BoxFit.cover,
                )
              else
                Container(
                  color: Colors.grey.shade900,
                  child: Center(
                    child: Icon(
                      Icons.article_outlined,
                      color: Colors.white.withValues(alpha: 0.5),
                      size: 20,
                    ),
                  ),
                ),
              // Page index badge
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: AppSpacing.roundedXs,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DoneReviewButton extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const DoneReviewButton({
    super.key,
    required this.count,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        shape: const RoundedRectangleBorder(borderRadius: AppSpacing.roundedLg),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
      label: Text(
        '($count)',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
