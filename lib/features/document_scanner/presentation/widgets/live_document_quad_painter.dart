import 'package:flutter/material.dart';
import '../../domain/models/scanned_document.dart';

/// CustomPainter that renders a sleek, glowing quadrilateral overlay
/// over the 4 corners of the live detected document in the camera viewfinder.
class LiveDocumentQuadPainter extends CustomPainter {
  final CropQuadCorners corners;
  final Color primaryColor;
  final double animationValue;

  LiveDocumentQuadPainter({
    required this.corners,
    this.primaryColor = const Color(0xFF00E5FF),
    this.animationValue = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Offset(corners.topLeft.dx * size.width, corners.topLeft.dy * size.height);
    final p2 = Offset(corners.topRight.dx * size.width, corners.topRight.dy * size.height);
    final p3 = Offset(corners.bottomRight.dx * size.width, corners.bottomRight.dy * size.height);
    final p4 = Offset(corners.bottomLeft.dx * size.width, corners.bottomLeft.dy * size.height);

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    // 1. Shaded polygon interior
    final fillPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.22 * animationValue)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 2. Glowing outer border stroke
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.5 * animationValue)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(path, glowPaint);

    // 3. Crisp border stroke
    final strokePaint = Paint()
      ..color = primaryColor.withValues(alpha: 1.0 * animationValue)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // 4. Corner target circles
    final cornerPoints = [p1, p2, p3, p4];
    final circleFillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final circleBorderPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final pt in cornerPoints) {
      canvas.drawCircle(pt, 6.0, circleFillPaint);
      canvas.drawCircle(pt, 6.0, circleBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LiveDocumentQuadPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.animationValue != animationValue;
  }
}
