import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../domain/models/scanned_document.dart';

/// CustomPainter that renders sleek, glowing quadrilateral overlays
/// over the corners of all live detected documents in the camera viewfinder.
/// Transitions from high-tech cyan to locked emerald green when stabilized.
/// Displays clean document index badges (#1, #2, ...) when multiple documents are in view.
class LiveDocumentQuadPainter extends CustomPainter {
  final List<CropQuadCorners> cornersList;
  final Color primaryColor;
  final Color lockedColor;
  final bool isLocked;
  final double lockProgress;
  final double animationValue;

  LiveDocumentQuadPainter({
    List<CropQuadCorners>? cornersList,
    CropQuadCorners? corners,
    this.primaryColor = const Color(0xFF00E5FF),
    this.lockedColor = const Color(0xFF00E676),
    this.isLocked = false,
    this.lockProgress = 0.0,
    this.animationValue = 1.0,
  }) : cornersList = cornersList ?? (corners != null ? [corners] : const []);

  CropQuadCorners? get corners =>
      cornersList.isNotEmpty ? cornersList.first : null;

  @override
  void paint(Canvas canvas, Size size) {
    if (cornersList.isEmpty) return;

    final activeColor = isLocked ? lockedColor : primaryColor;
    final isMulti = cornersList.length > 1;

    for (int i = 0; i < cornersList.length; i++) {
      final quad = cornersList[i];
      _paintSingleQuad(
        canvas: canvas,
        size: size,
        quad: quad,
        index: i + 1,
        showIndexBadge: isMulti,
        activeColor: activeColor,
      );
    }
  }

  void _paintSingleQuad({
    required Canvas canvas,
    required Size size,
    required CropQuadCorners quad,
    required int index,
    required bool showIndexBadge,
    required Color activeColor,
  }) {
    final p1 = Offset(quad.topLeft.dx * size.width, quad.topLeft.dy * size.height);
    final p2 = Offset(quad.topRight.dx * size.width, quad.topRight.dy * size.height);
    final p3 = Offset(quad.bottomRight.dx * size.width, quad.bottomRight.dy * size.height);
    final p4 = Offset(quad.bottomLeft.dx * size.width, quad.bottomLeft.dy * size.height);

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    // 1. Shaded polygon interior
    final fillAlpha = isLocked ? 0.32 : (0.18 * animationValue);
    final fillPaint = Paint()
      ..color = activeColor.withValues(alpha: fillAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 2. Glowing outer border stroke
    final glowPaint = Paint()
      ..color = activeColor.withValues(alpha: isLocked ? 0.65 : (0.40 * animationValue))
      ..strokeWidth = isLocked ? 7.0 : 5.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawPath(path, glowPaint);

    // 3. Crisp border stroke
    final strokePaint = Paint()
      ..color = activeColor.withValues(alpha: 1.0 * animationValue)
      ..strokeWidth = isLocked ? 3.0 : 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // 4. Corner target circles & countdown arcs
    final cornerPoints = [p1, p2, p3, p4];
    final circleFillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final circleBorderPaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final arcPaint = Paint()
      ..color = activeColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final pt in cornerPoints) {
      canvas.drawCircle(pt, 4.5, circleFillPaint);
      canvas.drawCircle(pt, 7.0, circleBorderPaint);

      if (lockProgress > 0.05) {
        const sweepAngleBase = 2 * math.pi;
        final rect = Rect.fromCircle(center: pt, radius: 11.0);
        canvas.drawArc(
          rect,
          -math.pi / 2,
          sweepAngleBase * lockProgress,
          false,
          arcPaint,
        );
      }
    }

    // 5. Document Numbering Badge (#1, #2, ...) when multiple items are detected
    if (showIndexBadge) {
      _paintDocumentBadge(canvas, p1, index, activeColor);
    }
  }

  void _paintDocumentBadge(
    Canvas canvas,
    Offset topLeft,
    int index,
    Color activeColor,
  ) {
    const badgeRadius = 13.0;
    final badgeCenter = Offset(topLeft.dx + 16, topLeft.dy + 16);

    // Badge shadow
    canvas.drawCircle(
      badgeCenter.translate(0, 1.5),
      badgeRadius,
      Paint()
        ..color = Colors.black45
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    // Badge background
    canvas.drawCircle(
      badgeCenter,
      badgeRadius,
      Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill,
    );

    // Badge border
    canvas.drawCircle(
      badgeCenter,
      badgeRadius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Text "#1", "#2"
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$index',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        badgeCenter.dx - (textPainter.width / 2),
        badgeCenter.dy - (textPainter.height / 2),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant LiveDocumentQuadPainter oldDelegate) {
    return !listEquals(oldDelegate.cornersList, cornersList) ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.lockedColor != lockedColor ||
        oldDelegate.isLocked != isLocked ||
        oldDelegate.lockProgress != lockProgress ||
        oldDelegate.animationValue != animationValue;
  }
}
