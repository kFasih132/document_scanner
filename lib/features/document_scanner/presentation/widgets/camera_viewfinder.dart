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

  const CameraViewfinder({
    super.key,
    required this.controller,
    required this.isInitialized,
    required this.statusMessage,
    this.liveCorners,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppSpacing.roundedLg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Preview or Simulated Viewport
          if (controller != null && controller!.value.isInitialized)
            CameraPreview(controller!)
          else
            const SimulatedCameraFeed(),

          // Clean Document Guide Frame (White corner guides)
          const DocumentGuideOverlay(),

          // Live AI Detected Quadrilateral Overlay
          if (liveCorners != null)
            Positioned.fill(
              child: CustomPaint(
                painter: LiveDocumentQuadPainter(
                  corners: liveCorners!,
                  primaryColor: AppColors.cropHandle,
                ),
              ),
            ),

          // Status & Guidance Badge
          Positioned(
            top: AppSpacing.xl,
            left: 0,
            right: 0,
            child: Center(
              child: ViewfinderStatusBadge(message: statusMessage),
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

  const ViewfinderStatusBadge({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.cameraOverlayDark,
        borderRadius: AppSpacing.roundedFull,
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.document_scanner_outlined,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
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
