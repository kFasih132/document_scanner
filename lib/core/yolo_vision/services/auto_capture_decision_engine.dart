import 'dart:math' as math;
import 'dart:ui';
import '../../../features/document_scanner/domain/models/scanned_document.dart';

/// Result evaluated on each camera frame by [AutoCaptureDecisionEngine]
class AutoCaptureEvaluation {
  final bool shouldCapture;
  final bool isLocked;
  final double lockProgress; // 0.0 to 1.0
  final bool isGeometryValid;
  final bool isSharp;
  final bool isStable;
  final String statusReason;

  const AutoCaptureEvaluation({
    required this.shouldCapture,
    required this.isLocked,
    required this.lockProgress,
    required this.isGeometryValid,
    required this.isSharp,
    required this.isStable,
    required this.statusReason,
  });

  factory AutoCaptureEvaluation.idle() => const AutoCaptureEvaluation(
        shouldCapture: false,
        isLocked: false,
        lockProgress: 0.0,
        isGeometryValid: false,
        isSharp: false,
        isStable: false,
        statusReason: 'Align document within borders',
      );
}

/// Production decision engine implementing Google Drive / ML Kit-grade
/// auto-capture heuristics:
/// 1. Stability Index: Corner displacement variance < epsilon
/// 2. Sharpness Score: Discrete Laplacian variance > threshold (no blur/shake)
/// 3. Perspective Geometry: Convex, non-concave quadrilateral with valid area and aspect ratio
class AutoCaptureDecisionEngine {
  final double stabilityEpsilon;
  final double sharpnessThreshold;
  final int requiredStableFrames;
  final double minAreaRatio;
  final double maxAreaRatio;

  int _consecutiveValidFrames = 0;
  CropQuadCorners? _previousCorners;
  List<CropQuadCorners> _previousCornersList = [];
  DateTime _lastCaptureTriggerTime = DateTime.fromMillisecondsSinceEpoch(0);

  AutoCaptureDecisionEngine({
    this.stabilityEpsilon = 0.018, // Max normalized corner drift (< 1.8% of screen)
    this.sharpnessThreshold = 65.0, // Minimum Laplacian variance
    this.requiredStableFrames = 4, // Consecutive frames needed to trigger
    this.minAreaRatio = 0.05, // Quad must cover at least 5% of viewfinder
    this.maxAreaRatio = 0.94, // Quad must not exceed 94% of viewfinder
  });

  /// Resets internal state (e.g. after capture or mode change)
  void reset() {
    _consecutiveValidFrames = 0;
    _previousCorners = null;
    _previousCornersList = [];
  }

  /// Evaluates multiple detected corner quads simultaneously
  AutoCaptureEvaluation evaluateMultiple({
    required List<CropQuadCorners> cornersList,
    required double sharpnessScore,
    required bool isAutoCaptureEnabled,
  }) {
    if (cornersList.isEmpty) {
      _consecutiveValidFrames = 0;
      _previousCorners = null;
      _previousCornersList = [];
      return AutoCaptureEvaluation.idle();
    }

    if (cornersList.length == 1) {
      return evaluate(
        corners: cornersList.first,
        sharpnessScore: sharpnessScore,
        isAutoCaptureEnabled: isAutoCaptureEnabled,
      );
    }

    // Filter to geometrically valid quads (using relaxed 2% min area for multi-box)
    final validCorners = <CropQuadCorners>[];
    String? geometryFailureReason;

    for (final quad in cornersList) {
      final (isValid, failure) = _checkGeometry(quad, 0.02);
      if (isValid) {
        validCorners.add(quad);
      } else {
        geometryFailureReason ??= failure;
      }
    }

    if (validCorners.isEmpty) {
      _consecutiveValidFrames = 0;
      _previousCornersList = cornersList;
      return AutoCaptureEvaluation(
        shouldCapture: false,
        isLocked: false,
        lockProgress: 0.0,
        isGeometryValid: false,
        isSharp: false,
        isStable: false,
        statusReason: geometryFailureReason ?? 'Align documents within borders',
      );
    }

    final count = validCorners.length;

    // Sharpness Heuristic
    final isSharp = sharpnessScore >= sharpnessThreshold;
    if (!isSharp) {
      _consecutiveValidFrames = 0;
      _previousCornersList = validCorners;
      return AutoCaptureEvaluation(
        shouldCapture: false,
        isLocked: false,
        lockProgress: 0.0,
        isGeometryValid: true,
        isSharp: false,
        isStable: false,
        statusReason: 'Hold camera still (Focusing...)',
      );
    }

    // Stability Index Heuristic across all detected quads
    bool isStable = false;
    if (_previousCornersList.length == count) {
      double maxDisplacementAcrossAll = 0.0;
      for (int i = 0; i < count; i++) {
        final disp = _computeMaxCornerDisplacement(
          _previousCornersList[i],
          validCorners[i],
        );
        if (disp > maxDisplacementAcrossAll) {
          maxDisplacementAcrossAll = disp;
        }
      }
      isStable = maxDisplacementAcrossAll <= stabilityEpsilon;
    }
    _previousCornersList = validCorners;

    if (!isStable) {
      _consecutiveValidFrames = math.max(0, _consecutiveValidFrames - 1);
      return AutoCaptureEvaluation(
        shouldCapture: false,
        isLocked: false,
        lockProgress:
            (_consecutiveValidFrames / requiredStableFrames).clamp(0.0, 1.0),
        isGeometryValid: true,
        isSharp: true,
        isStable: false,
        statusReason: '$count documents detected - Hold steady',
      );
    }

    _consecutiveValidFrames++;
    final progress =
        (_consecutiveValidFrames / requiredStableFrames).clamp(0.0, 1.0);
    final isLocked = _consecutiveValidFrames >= (requiredStableFrames - 1);

    final now = DateTime.now();
    final canTrigger = isAutoCaptureEnabled &&
        _consecutiveValidFrames >= requiredStableFrames &&
        now.difference(_lastCaptureTriggerTime).inMilliseconds > 2500;

    if (canTrigger) {
      _lastCaptureTriggerTime = now;
      _consecutiveValidFrames = 0;
      return AutoCaptureEvaluation(
        shouldCapture: true,
        isLocked: true,
        lockProgress: 1.0,
        isGeometryValid: true,
        isSharp: true,
        isStable: true,
        statusReason: '$count documents locked! Capturing...',
      );
    }

    return AutoCaptureEvaluation(
      shouldCapture: false,
      isLocked: isLocked,
      lockProgress: progress,
      isGeometryValid: true,
      isSharp: true,
      isStable: true,
      statusReason: isLocked
          ? '$count documents locked! Hold still...'
          : '$count documents detected - Holding steady...',
    );
  }

  /// Evaluates the current frame detection and returns an [AutoCaptureEvaluation]
  AutoCaptureEvaluation evaluate({
    required CropQuadCorners? corners,
    required double sharpnessScore,
    required bool isAutoCaptureEnabled,
  }) {
    if (corners == null) {
      _consecutiveValidFrames = 0;
      _previousCorners = null;
      return AutoCaptureEvaluation.idle();
    }

    // 1. Perspective Geometry Heuristic
    final (isGeometryValid, geometryReason) =
        _checkGeometry(corners, minAreaRatio);
    if (!isGeometryValid) {
      _consecutiveValidFrames = 0;
      _previousCorners = corners;
      return AutoCaptureEvaluation(
        shouldCapture: false,
        isLocked: false,
        lockProgress: 0.0,
        isGeometryValid: false,
        isSharp: false,
        isStable: false,
        statusReason: geometryReason ?? 'Align document within borders',
      );
    }

    // 2. Sharpness Heuristic (Laplacian Variance)
    final isSharp = sharpnessScore >= sharpnessThreshold;
    if (!isSharp) {
      _consecutiveValidFrames = 0;
      _previousCorners = corners;
      return AutoCaptureEvaluation(
        shouldCapture: false,
        isLocked: false,
        lockProgress: 0.0,
        isGeometryValid: true,
        isSharp: false,
        isStable: false,
        statusReason: 'Hold camera still (Focusing...)',
      );
    }

    // 3. Stability Index Heuristic
    bool isStable = false;
    if (_previousCorners != null) {
      final maxDisplacement =
          _computeMaxCornerDisplacement(_previousCorners!, corners);
      isStable = maxDisplacement <= stabilityEpsilon;
    }
    _previousCorners = corners;

    if (!isStable) {
      _consecutiveValidFrames = math.max(0, _consecutiveValidFrames - 1);
      return AutoCaptureEvaluation(
        shouldCapture: false,
        isLocked: false,
        lockProgress:
            (_consecutiveValidFrames / requiredStableFrames).clamp(0.0, 1.0),
        isGeometryValid: true,
        isSharp: true,
        isStable: false,
        statusReason: 'Document detected - Hold steady',
      );
    }

    // All 3 conditions satisfied!
    _consecutiveValidFrames++;
    final progress =
        (_consecutiveValidFrames / requiredStableFrames).clamp(0.0, 1.0);
    final isLocked = _consecutiveValidFrames >= (requiredStableFrames - 1);

    final now = DateTime.now();
    final canTrigger = isAutoCaptureEnabled &&
        _consecutiveValidFrames >= requiredStableFrames &&
        now.difference(_lastCaptureTriggerTime).inMilliseconds > 2500;

    if (canTrigger) {
      _lastCaptureTriggerTime = now;
      _consecutiveValidFrames = 0;
      return const AutoCaptureEvaluation(
        shouldCapture: true,
        isLocked: true,
        lockProgress: 1.0,
        isGeometryValid: true,
        isSharp: true,
        isStable: true,
        statusReason: 'Document locked! Capturing...',
      );
    }

    return AutoCaptureEvaluation(
      shouldCapture: false,
      isLocked: isLocked,
      lockProgress: progress,
      isGeometryValid: true,
      isSharp: true,
      isStable: true,
      statusReason: isLocked ? 'Locked! Hold still...' : 'Holding steady...',
    );
  }

  /// Calculates max displacement across all 4 vertices
  double _computeMaxCornerDisplacement(CropQuadCorners a, CropQuadCorners b) {
    final d1 = (a.topLeft - b.topLeft).distance;
    final d2 = (a.topRight - b.topRight).distance;
    final d3 = (a.bottomRight - b.bottomRight).distance;
    final d4 = (a.bottomLeft - b.bottomLeft).distance;
    return math.max(math.max(d1, d2), math.max(d3, d4));
  }

  /// Validates quadrilateral convexity, area, and aspect ratio, returning
  /// whether it is valid and a descriptive failure reason if not.
  (bool, String?) _checkGeometry(CropQuadCorners c, double minArea) {
    final p0 = c.topLeft;
    final p1 = c.topRight;
    final p2 = c.bottomRight;
    final p3 = c.bottomLeft;

    // 1. True directed edge turn test for quadrilateral convexity:
    // Directed edges: e0 = p1 - p0, e1 = p2 - p1, e2 = p3 - p2, e3 = p0 - p3
    // Cross product z-component: a.dx * b.dy - a.dy * b.dx
    double crossProduct2D(Offset a, Offset b) {
      return (a.dx * b.dy) - (a.dy * b.dx);
    }

    final e0 = p1 - p0;
    final e1 = p2 - p1;
    final e2 = p3 - p2;
    final e3 = p0 - p3;

    final cp0 = crossProduct2D(e0, e1);
    final cp1 = crossProduct2D(e1, e2);
    final cp2 = crossProduct2D(e2, e3);
    final cp3 = crossProduct2D(e3, e0);

    final allPositive = cp0 > 0 && cp1 > 0 && cp2 > 0 && cp3 > 0;
    final allNegative = cp0 < 0 && cp1 < 0 && cp2 < 0 && cp3 < 0;
    if (!allPositive && !allNegative) {
      return (false, 'Straighten document angle');
    }

    // 2. Area check via Shoelace formula
    final area = c.polygonArea;
    if (area < minArea) {
      return (false, 'Move camera closer');
    }
    if (area > maxAreaRatio) {
      return (false, 'Move camera back');
    }

    // 3. Aspect ratio check
    final widthAvg = (e0.distance + e2.distance) / 2.0;
    final heightAvg = (e1.distance + e3.distance) / 2.0;
    if (heightAvg < 0.02 || widthAvg < 0.02) {
      return (false, 'Move camera closer');
    }

    final ratio = widthAvg / heightAvg;
    if (ratio < 0.15 || ratio > 6.0) {
      return (false, 'Straighten document angle');
    }

    return (true, null);
  }
}
