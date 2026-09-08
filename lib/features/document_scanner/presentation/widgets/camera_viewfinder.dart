import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/scanned_document.dart';
import 'live_document_quad_painter.dart';

class CameraViewfinder extends StatelessWidget {
  final CameraController? controller;
  final bool isInitialized;
  final String statusMessage;
  final CropQuadCorners? liveCorners;
  final List<CropQuadCorners> liveCornersList;
  final bool isLocked;
  final double lockProgress;
  final bool showEmbeddedStatusBadge;

  const CameraViewfinder({
    super.key,
    required this.controller,
    required this.isInitialized,
    required this.statusMessage,
    this.liveCorners,
    this.liveCornersList = const [],
    this.isLocked = false,
    this.lockProgress = 0.0,
    this.showEmbeddedStatusBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final corners = liveCornersList.isNotEmpty
        ? liveCornersList
        : (liveCorners != null ? [liveCorners!] : const <CropQuadCorners>[]);

    return ClipRRect(
      borderRadius: AppSpacing.roundedLg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Preview with pixel-perfect quadrilateral overlay alignment
          if (controller != null && controller!.value.isInitialized)
            LayoutBuilder(
              builder: (context, constraints) {
                final cameraAspectRatio = 1 / controller!.value.aspectRatio;
                final boxWidth = constraints.maxWidth;
                final boxHeight = boxWidth / cameraAspectRatio;

                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: boxWidth,
                        height: boxHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(controller!),
                            if (corners.isNotEmpty)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: LiveDocumentQuadPainter(
                                    cornersList: corners,
                                    primaryColor: AppColors.cropHandle,
                                    lockedColor: const Color(0xFF00E676),
                                    isLocked: isLocked,
                                    lockProgress: lockProgress,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          else
            const SimulatedCameraFeed(),

          // Status & Guidance Badge (rendered embedded only if requested)
          if (showEmbeddedStatusBadge)
            Positioned(
              top: AppSpacing.xl,
              left: 0,
              right: 0,
              child: Center(
                child: ViewfinderStatusBadge(
                  message: statusMessage,
                  isLocked: isLocked,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SimulatedCameraFeed extends StatelessWidget {
  const SimulatedCameraFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: AppSpacing.huge,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Camera Feed Active',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ViewfinderStatusBadge extends StatelessWidget {
  final String message;
  final bool isLocked;

  const ViewfinderStatusBadge({
    super.key,
    required this.message,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: isLocked
            ? const Color(0xFF00E676).withValues(alpha: 0.85)
            : AppColors.cameraOverlayDark,
        borderRadius: AppSpacing.roundedFull,
        border: Border.all(
          color: isLocked ? Colors.white : Colors.white24,
          width: isLocked ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLocked ? Icons.check_circle_outline : Icons.document_scanner_outlined,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DocumentGuideOverlay extends StatelessWidget {
  const DocumentGuideOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // Standard A4 document ratio
    const double targetAspectRatio = 1 / 1.414;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxW = constraints.maxWidth * 0.86;
        final double maxH = constraints.maxHeight * 0.72;

        double boxW = maxW;
        double boxH = boxW / targetAspectRatio;

        if (boxH > maxH) {
          boxH = maxH;
          boxW = boxH * targetAspectRatio;
        }

        return Center(
          child: SizedBox(
            width: boxW,
            height: boxH,
            child: Stack(
              children: [
                // Subtle border outline
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1.0,
                    ),
                    borderRadius: AppSpacing.roundedMd,
                  ),
                ),
                // 4 Clean White Corner Brackets
                const Positioned(top: 0, left: 0, child: ViewfinderCornerBracket(corner: CornerType.topLeft)),
                const Positioned(top: 0, right: 0, child: ViewfinderCornerBracket(corner: CornerType.topRight)),
                const Positioned(bottom: 0, left: 0, child: ViewfinderCornerBracket(corner: CornerType.bottomLeft)),
                const Positioned(bottom: 0, right: 0, child: ViewfinderCornerBracket(corner: CornerType.bottomRight)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ViewfinderCornerBracket extends StatelessWidget {
  final CornerType corner;
  static const double armLength = 26.0;
  static const double thickness = 3.0;

  const ViewfinderCornerBracket({super.key, required this.corner});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(armLength, armLength),
      painter: _CornerBracketPainter(
        corner: corner,
        color: Colors.white,
        thickness: thickness,
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final CornerType corner;
  final Color color;
  final double thickness;

  _CornerBracketPainter({
    required this.corner,
    required this.color,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    switch (corner) {
      case CornerType.topLeft:
        path.moveTo(0, size.height);
        path.lineTo(0, 0);
        path.lineTo(size.width, 0);
        break;
      case CornerType.topRight:
        path.moveTo(0, 0);
        path.lineTo(size.width, 0);
        path.lineTo(size.width, size.height);
        break;
      case CornerType.bottomLeft:
        path.moveTo(0, 0);
        path.lineTo(0, size.height);
        path.lineTo(size.width, size.height);
        break;
      case CornerType.bottomRight:
        path.moveTo(0, size.height);
        path.lineTo(size.width, size.height);
        path.lineTo(size.width, 0);
        break;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) =>
      oldDelegate.corner != corner || oldDelegate.color != color;
}
