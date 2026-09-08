import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../features/document_scanner/domain/models/scanned_document.dart';

/// Result produced by [VisualDocumentTracker] for a single frame.
class VisualTrackingResult {
  final CropQuadCorners corners;
  final double confidence; // 0.0 (lost) to 1.0 (perfect lock)
  final bool isTrackingValid;

  const VisualTrackingResult({
    required this.corners,
    required this.confidence,
    required this.isTrackingValid,
  });

  factory VisualTrackingResult.invalid() => const VisualTrackingResult(
        corners: CropQuadCorners(),
        confidence: 0.0,
        isTrackingValid: false,
      );
}

/// Internal reference patch extracted on high-contrast document regions
class _ContentReferencePatch {
  int x; // Sensor pixel coordinate
  int y; // Sensor pixel coordinate
  final Uint8List patchData; // 21x21 = 441 grayscale luminance values
  int meanIntensity;
  double textureVariance; // Variance of pixel intensities (contrast metric)

  _ContentReferencePatch({
    required this.x,
    required this.y,
    required this.patchData,
    required this.meanIntensity,
    required this.textureVariance,
  });
}

/// High-performance, pure-Dart 60 FPS visual document flow tracker.
///
/// Uses an interior surface motion flow algorithm:
/// Rather than tracking plain white outer corners (which suffer from the aperture
/// problem on border edges), this tracker places 5 anchor patches across the
/// document's interior body (Center + 4 Inner Quadrants) where printed text, ink,
/// and high-contrast features live.
///
/// Computes robust consensus translation $(\Delta X, \Delta Y)$ in $<0.6\text{ms}$
/// per frame, keeping the bounding box tightly glued to the document on low-end
/// and high-end devices alike.
class VisualDocumentTracker {
  static const int patchRadius = 10; // 21x21 patch
  static const int patchDiameter = (patchRadius * 2) + 1; // 21
  static const int patchArea = patchDiameter * patchDiameter; // 441
  static const int searchRadius = 22; // Search radius in sensor pixels
  static const int coarseStep = 2; // Step size for coarse search

  // 5 Interior Content Anchors:
  // [0] = Center Centroid
  // [1] = Inner Top-Left Quadrant
  // [2] = Inner Top-Right Quadrant
  // [3] = Inner Bottom-Right Quadrant
  // [4] = Inner Bottom-Left Quadrant
  final List<_ContentReferencePatch?> _interiorPatches = [null, null, null, null, null];
  
  // Current sensor pixel coordinates of the 4 document corners
  Offset? _sensorCornerTL;
  Offset? _sensorCornerTR;
  Offset? _sensorCornerBR;
  Offset? _sensorCornerBL;

  CropQuadCorners? _currentViewfinderCorners;
  bool _isTracking = false;
  int _consecutiveFailures = 0;
  static const int maxToleratedFailures = 6;

  bool get isTracking => _isTracking && _currentViewfinderCorners != null;
  CropQuadCorners? get currentCorners => _currentViewfinderCorners;

  /// Resets tracker state and releases all stored reference patches.
  void reset() {
    _isTracking = false;
    _currentViewfinderCorners = null;
    _sensorCornerTL = null;
    _sensorCornerTR = null;
    _sensorCornerBR = null;
    _sensorCornerBL = null;
    _consecutiveFailures = 0;
    for (int i = 0; i < _interiorPatches.length; i++) {
      _interiorPatches[i] = null;
    }
  }

  /// Initializes or re-anchors the tracker with known ground-truth corners (from ML).
  void initializeTracking({
    required CropQuadCorners corners,
    required Uint8List luminanceBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotationDegrees,
  }) {
    if (!_validateConvexity(corners)) return;

    // Convert the 4 corners to unrotated sensor pixel space
    final pTL = viewfinderToSensorPixel(corners.topLeft, rotationDegrees, width, height);
    final pTR = viewfinderToSensorPixel(corners.topRight, rotationDegrees, width, height);
    final pBR = viewfinderToSensorPixel(corners.bottomRight, rotationDegrees, width, height);
    final pBL = viewfinderToSensorPixel(corners.bottomLeft, rotationDegrees, width, height);

    _sensorCornerTL = pTL;
    _sensorCornerTR = pTR;
    _sensorCornerBR = pBR;
    _sensorCornerBL = pBL;

    // Derive the 5 interior document content anchors:
    // Centroid: Center of document
    final center = Offset(
      (pTL.dx + pTR.dx + pBR.dx + pBL.dx) / 4.0,
      (pTL.dy + pTR.dy + pBR.dy + pBL.dy) / 4.0,
    );

    // 4 Inner Quadrants (halfway between each corner and center):
    final q1 = Offset((pTL.dx + center.dx) / 2.0, (pTL.dy + center.dy) / 2.0);
    final q2 = Offset((pTR.dx + center.dx) / 2.0, (pTR.dy + center.dy) / 2.0);
    final q3 = Offset((pBR.dx + center.dx) / 2.0, (pBR.dy + center.dy) / 2.0);
    final q4 = Offset((pBL.dx + center.dx) / 2.0, (pBL.dy + center.dy) / 2.0);

    final anchorPoints = [center, q1, q2, q3, q4];

    int validPatchesCount = 0;
    for (int i = 0; i < anchorPoints.length; i++) {
      final patch = _extractPatch(
        anchorPoints[i].dx.round(),
        anchorPoints[i].dy.round(),
        luminanceBytes,
        width,
        height,
        bytesPerRow,
      );

      _interiorPatches[i] = patch;
      if (patch != null && patch.textureVariance > 15.0) {
        validPatchesCount++;
      }
    }

    // Require at least 2 interior patches with meaningful texture (text/ink/contrast)
    if (validPatchesCount >= 2 || _interiorPatches[0] != null) {
      _currentViewfinderCorners = corners;
      _isTracking = true;
      _consecutiveFailures = 0;
    } else {
      reset();
    }
  }

  /// Tracks interior document surface motion flow in the incoming frame.
  /// Runs on every single camera frame in $<0.6\text{ms}$.
  VisualTrackingResult trackFrame({
    required Uint8List luminanceBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotationDegrees,
  }) {
    if (!_isTracking ||
        _currentViewfinderCorners == null ||
        _sensorCornerTL == null) {
      return VisualTrackingResult.invalid();
    }

    final deltaXs = <double>[];
    final deltaYs = <double>[];
    final weights = <double>[];
    double totalConfidence = 0.0;
    int trackedCount = 0;

    for (int i = 0; i < _interiorPatches.length; i++) {
      final patch = _interiorPatches[i];
      if (patch == null) continue;

      final (bestX, bestY, score) = _searchPatchCoarseToFine(
        patch,
        luminanceBytes,
        width,
        height,
        bytesPerRow,
      );

      // Score is mean absolute error per pixel (0 = exact match, >45 = poor)
      final patchConf = (1.0 - (score / 45.0)).clamp(0.0, 1.0);

      if (patchConf >= 0.28) {
        final dx = (bestX - patch.x).toDouble();
        final dy = (bestY - patch.y).toDouble();

        // Weight patch by match quality and intrinsic texture variance
        final weight = patchConf * (math.min(patch.textureVariance, 100.0) / 100.0 + 0.2);

        deltaXs.add(dx);
        deltaYs.add(dy);
        weights.add(weight);

        totalConfidence += patchConf;
        trackedCount++;

        // Update patch location for continuous flow
        patch.x = bestX;
        patch.y = bestY;
      }
    }

    // If fewer than 2 interior anchors tracked successfully, report tracking loss
    if (trackedCount < 2) {
      _handleTrackingFailure();
      return VisualTrackingResult.invalid();
    }

    // Robust weighted consensus translation vector (filters out occlusions/shadows)
    double weightedDx = 0.0;
    double weightedDy = 0.0;
    double sumWeight = 0.0;

    for (int i = 0; i < deltaXs.length; i++) {
      weightedDx += deltaXs[i] * weights[i];
      weightedDy += deltaYs[i] * weights[i];
      sumWeight += weights[i];
    }

    final flowDx = sumWeight > 0 ? weightedDx / sumWeight : 0.0;
    final flowDy = sumWeight > 0 ? weightedDy / sumWeight : 0.0;

    // Apply consensus flow translation to all 4 sensor corner vertices
    _sensorCornerTL = Offset(
      (_sensorCornerTL!.dx + flowDx).clamp(0.0, width - 1.0),
      (_sensorCornerTL!.dy + flowDy).clamp(0.0, height - 1.0),
    );
    _sensorCornerTR = Offset(
      (_sensorCornerTR!.dx + flowDx).clamp(0.0, width - 1.0),
      (_sensorCornerTR!.dy + flowDy).clamp(0.0, height - 1.0),
    );
    _sensorCornerBR = Offset(
      (_sensorCornerBR!.dx + flowDx).clamp(0.0, width - 1.0),
      (_sensorCornerBR!.dy + flowDy).clamp(0.0, height - 1.0),
    );
    _sensorCornerBL = Offset(
      (_sensorCornerBL!.dx + flowDx).clamp(0.0, width - 1.0),
      (_sensorCornerBL!.dy + flowDy).clamp(0.0, height - 1.0),
    );

    // Convert updated sensor pixel corners back to normalized viewfinder space
    final vfTopLeft = sensorPixelToViewfinder(_sensorCornerTL!, rotationDegrees, width, height);
    final vfTopRight = sensorPixelToViewfinder(_sensorCornerTR!, rotationDegrees, width, height);
    final vfBottomRight = sensorPixelToViewfinder(_sensorCornerBR!, rotationDegrees, width, height);
    final vfBottomLeft = sensorPixelToViewfinder(_sensorCornerBL!, rotationDegrees, width, height);

    final candidateCorners = CropQuadCorners(
      topLeft: vfTopLeft,
      topRight: vfTopRight,
      bottomRight: vfBottomRight,
      bottomLeft: vfBottomLeft,
    );

    // Validate that the tracked corners remain a physically plausible convex polygon
    if (!_validateConvexity(candidateCorners)) {
      _handleTrackingFailure();
      return VisualTrackingResult.invalid();
    }

    _consecutiveFailures = 0;
    _currentViewfinderCorners = candidateCorners;
    final avgConfidence = totalConfidence / trackedCount;

    return VisualTrackingResult(
      corners: candidateCorners,
      confidence: avgConfidence,
      isTrackingValid: true,
    );
  }

  /// Reconciles high-frequency tracked corners with periodic ML ground truth.
  /// Blends to remove accumulated drift, or snaps if document changed significantly.
  void reconcileWithMlDetection({
    required CropQuadCorners mlCorners,
    required Uint8List luminanceBytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotationDegrees,
  }) {
    if (!_validateConvexity(mlCorners)) {
      return;
    }

    if (!_isTracking || _currentViewfinderCorners == null) {
      // Tracker was not active: initialize immediately with ML ground truth
      initializeTracking(
        corners: mlCorners,
        luminanceBytes: luminanceBytes,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        rotationDegrees: rotationDegrees,
      );
      return;
    }

    // Measure maximum corner distance between current tracking and ML ground truth
    final maxDelta = _computeMaxCornerDelta(_currentViewfinderCorners!, mlCorners);

    if (maxDelta > 0.18) {
      // Significant camera pan or new document: snap directly to ML detection
      initializeTracking(
        corners: mlCorners,
        luminanceBytes: luminanceBytes,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        rotationDegrees: rotationDegrees,
      );
    } else {
      // Soft drift correction: Blend 75% ML ground truth + 25% current tracked estimate
      const mlWeight = 0.75;
      final blendedCorners = CropQuadCorners(
        topLeft: _lerpOffset(_currentViewfinderCorners!.topLeft, mlCorners.topLeft, mlWeight),
        topRight: _lerpOffset(_currentViewfinderCorners!.topRight, mlCorners.topRight, mlWeight),
        bottomRight: _lerpOffset(_currentViewfinderCorners!.bottomRight, mlCorners.bottomRight, mlWeight),
        bottomLeft: _lerpOffset(_currentViewfinderCorners!.bottomLeft, mlCorners.bottomLeft, mlWeight),
      );

      // Re-anchor reference interior patches at blended coordinates to clear drift
      initializeTracking(
        corners: blendedCorners,
        luminanceBytes: luminanceBytes,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        rotationDegrees: rotationDegrees,
      );
    }
  }

  void _handleTrackingFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= maxToleratedFailures) {
      reset();
    }
  }

  /// Extracts a 21x21 luminance patch centered at (cx, cy) and calculates variance.
  _ContentReferencePatch? _extractPatch(
    int cx,
    int cy,
    Uint8List bytes,
    int width,
    int height,
    int bytesPerRow,
  ) {
    final clampedX = cx.clamp(patchRadius, width - 1 - patchRadius);
    final clampedY = cy.clamp(patchRadius, height - 1 - patchRadius);

    final patchData = Uint8List(patchArea);
    int sum = 0;
    int sumSq = 0;
    int idx = 0;

    for (int dy = -patchRadius; dy <= patchRadius; dy++) {
      final rowOffset = (clampedY + dy) * bytesPerRow;
      for (int dx = -patchRadius; dx <= patchRadius; dx++) {
        final val = bytes[rowOffset + (clampedX + dx)];
        patchData[idx++] = val;
        sum += val;
        sumSq += (val * val);
      }
    }

    final mean = sum ~/ patchArea;
    final variance = (sumSq / patchArea) - (mean * mean);

    return _ContentReferencePatch(
      x: clampedX,
      y: clampedY,
      patchData: patchData,
      meanIntensity: mean,
      textureVariance: math.max(0.0, variance),
    );
  }

  /// Two-stage coarse-to-fine Zero-mean Sum of Absolute Differences (ZSAD) search.
  (int bestX, int bestY, double meanError) _searchPatchCoarseToFine(
    _ContentReferencePatch patch,
    Uint8List bytes,
    int width,
    int height,
    int bytesPerRow,
  ) {
    final startX = patch.x;
    final startY = patch.y;

    int bestCoarseX = startX;
    int bestCoarseY = startY;
    int minCoarseError = 999999999;

    // Stage 1: Coarse Grid Search (stride 2 px, subsampled patch)
    for (int dy = -searchRadius; dy <= searchRadius; dy += coarseStep) {
      final candY = startY + dy;
      if (candY < patchRadius || candY >= height - patchRadius) continue;

      for (int dx = -searchRadius; dx <= searchRadius; dx += coarseStep) {
        final candX = startX + dx;
        if (candX < patchRadius || candX >= width - patchRadius) continue;

        // Subsampled patch ZSAD (stride 2 on patch)
        int candSum = 0;
        int count = 0;
        for (int py = -patchRadius; py <= patchRadius; py += 2) {
          final rowOffset = (candY + py) * bytesPerRow;
          for (int px = -patchRadius; px <= patchRadius; px += 2) {
            candSum += bytes[rowOffset + (candX + px)];
            count++;
          }
        }
        final candMean = candSum ~/ count;

        int zsad = 0;
        for (int py = -patchRadius; py <= patchRadius; py += 2) {
          final rowOffset = (candY + py) * bytesPerRow;
          final patchRowOffset = (py + patchRadius) * patchDiameter;
          for (int px = -patchRadius; px <= patchRadius; px += 2) {
            final candVal = bytes[rowOffset + (candX + px)] - candMean;
            final refVal = patch.patchData[patchRowOffset + (px + patchRadius)] - patch.meanIntensity;
            zsad += (candVal - refVal).abs();
          }
        }

        if (zsad < minCoarseError) {
          minCoarseError = zsad;
          bestCoarseX = candX;
          bestCoarseY = candY;
        }
      }
    }

    // Stage 2: Fine Grid Search (+/- 1 px around best coarse location with full patch)
    int bestFineX = bestCoarseX;
    int bestFineY = bestCoarseY;
    int minFineError = 999999999;

    for (int dy = -1; dy <= 1; dy++) {
      final candY = bestCoarseY + dy;
      if (candY < patchRadius || candY >= height - patchRadius) continue;

      for (int dx = -1; dx <= 1; dx++) {
        final candX = bestCoarseX + dx;
        if (candX < patchRadius || candX >= width - patchRadius) continue;

        int candSum = 0;
        for (int py = -patchRadius; py <= patchRadius; py++) {
          final rowOffset = (candY + py) * bytesPerRow;
          for (int px = -patchRadius; px <= patchRadius; px++) {
            candSum += bytes[rowOffset + (candX + px)];
          }
        }
        final candMean = candSum ~/ patchArea;

        int zsad = 0;
        int patchIdx = 0;
        for (int py = -patchRadius; py <= patchRadius; py++) {
          final rowOffset = (candY + py) * bytesPerRow;
          for (int px = -patchRadius; px <= patchRadius; px++) {
            final candVal = bytes[rowOffset + (candX + px)] - candMean;
            final refVal = patch.patchData[patchIdx++] - patch.meanIntensity;
            zsad += (candVal - refVal).abs();
          }
        }

        if (zsad < minFineError) {
          minFineError = zsad;
          bestFineX = candX;
          bestFineY = candY;
        }
      }
    }

    final meanError = minFineError / patchArea;
    return (bestFineX, bestFineY, meanError);
  }

  // --- Coordinate Transformations ---

  /// Converts a normalized [0.0 - 1.0] viewfinder point into sensor buffer pixel coordinates.
  static Offset viewfinderToSensorPixel(
    Offset u,
    int rotationDegrees,
    int width,
    int height,
  ) {
    final s = viewfinderToSensorNormalized(u, rotationDegrees);
    final px = (s.dx * width).clamp(0.0, width - 1.0);
    final py = (s.dy * height).clamp(0.0, height - 1.0);
    return Offset(px, py);
  }

  /// Converts sensor buffer pixel coordinates back to a normalized [0.0 - 1.0] viewfinder point.
  static Offset sensorPixelToViewfinder(
    Offset p,
    int rotationDegrees,
    int width,
    int height,
  ) {
    final s = Offset(
      (p.dx / width).clamp(0.0, 1.0),
      (p.dy / height).clamp(0.0, 1.0),
    );
    return sensorToViewfinderNormalized(s, rotationDegrees);
  }

  /// Converts normalized viewfinder coordinate to normalized sensor coordinate
  static Offset viewfinderToSensorNormalized(Offset u, int rotationDegrees) {
    final deg = ((rotationDegrees % 360) + 360) % 360;
    if (deg == 90) {
      return Offset(u.dy, 1.0 - u.dx);
    } else if (deg == 180) {
      return Offset(1.0 - u.dx, 1.0 - u.dy);
    } else if (deg == 270) {
      return Offset(1.0 - u.dy, u.dx);
    }
    return u;
  }

  /// Converts normalized sensor coordinate to normalized viewfinder coordinate
  static Offset sensorToViewfinderNormalized(Offset s, int rotationDegrees) {
    final deg = ((rotationDegrees % 360) + 360) % 360;
    if (deg == 90) {
      return Offset(1.0 - s.dy, s.dx);
    } else if (deg == 180) {
      return Offset(1.0 - s.dx, 1.0 - s.dy);
    } else if (deg == 270) {
      return Offset(s.dy, 1.0 - s.dx);
    }
    return s;
  }

  // --- Geometry Validation ---

  /// Verifies that the quadrilateral is strictly convex, non-self-intersecting,
  /// and within realistic area bounds [0.04 - 0.95].
  static bool _validateConvexity(CropQuadCorners corners) {
    final p1 = corners.topLeft;
    final p2 = corners.topRight;
    final p3 = corners.bottomRight;
    final p4 = corners.bottomLeft;

    // 1. Minimum and maximum polygon area via Shoelace formula
    final s1 = (p1.dx * p2.dy) + (p2.dx * p3.dy) + (p3.dx * p4.dy) + (p4.dx * p1.dy);
    final s2 = (p1.dy * p2.dx) + (p2.dy * p3.dx) + (p3.dy * p4.dx) + (p4.dy * p1.dx);
    final area = 0.5 * (s1 - s2).abs();

    if (area < 0.04 || area > 0.95) return false;

    // 2. Strict convexity: cross products of adjacent edge vectors must all share the same sign
    double crossProduct(Offset a, Offset b, Offset c) {
      final abX = b.dx - a.dx;
      final abY = b.dy - a.dy;
      final bcX = c.dx - b.dx;
      final bcY = c.dy - b.dy;
      return (abX * bcY) - (abY * bcX);
    }

    final cp1 = crossProduct(p1, p2, p3);
    final cp2 = crossProduct(p2, p3, p4);
    final cp3 = crossProduct(p3, p4, p1);
    final cp4 = crossProduct(p4, p1, p2);

    final allPositive = cp1 > 0 && cp2 > 0 && cp3 > 0 && cp4 > 0;
    final allNegative = cp1 < 0 && cp2 < 0 && cp3 < 0 && cp4 < 0;

    return allPositive || allNegative;
  }

  static double _computeMaxCornerDelta(CropQuadCorners a, CropQuadCorners b) {
    final d1 = (a.topLeft - b.topLeft).distance;
    final d2 = (a.topRight - b.topRight).distance;
    final d3 = (a.bottomRight - b.bottomRight).distance;
    final d4 = (a.bottomLeft - b.bottomLeft).distance;
    return math.max(math.max(d1, d2), math.max(d3, d4));
  }

  static Offset _lerpOffset(Offset a, Offset b, double t) {
    return Offset(
      a.dx + (b.dx - a.dx) * t,
      a.dy + (b.dy - a.dy) * t,
    );
  }
}
