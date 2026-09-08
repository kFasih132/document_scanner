import 'dart:math' as math;
import 'dart:ui';
import '../../../features/document_scanner/domain/models/scanned_document.dart';

/// Temporal Corner Smoother implementing velocity-adaptive 1€ filtering
/// and outlier rejection on the 4 quadrilateral document vertices.
///
/// Eliminates high-frequency sensor noise and micro-jitter when the phone
/// is held still, while adapting to high responsiveness during swift camera pans.
class TemporalCornerSmoother {
  final double minAlpha;
  final double maxAlpha;
  final double velocityThreshold;
  final double outlierThreshold;
  final int maxMissedFrames;

  CropQuadCorners? _smoothedCorners;
  CropQuadCorners? _previousRawCorners;
  int _missedFrameCount = 0;
  List<TemporalCornerSmoother> _multiSmoothers = [];

  TemporalCornerSmoother({
    this.minAlpha = 0.35, // Stable lock at rest
    this.maxAlpha = 0.90, // Immediate responsiveness during camera motion
    this.velocityThreshold = 0.05, // Adapted for 15-20 FPS frame delta
    this.outlierThreshold = 0.35, // Distance jump to reject as glitch
    this.maxMissedFrames = 4, // ~200-250ms persistence at 15-20 FPS
  });

  CropQuadCorners? get currentSmoothed => _smoothedCorners;

  List<CropQuadCorners> get currentSmoothedList => _multiSmoothers
      .map((s) => s.currentSmoothed)
      .whereType<CropQuadCorners>()
      .toList();

  /// Resets smoothing history
  void reset() {
    _smoothedCorners = null;
    _previousRawCorners = null;
    _missedFrameCount = 0;
    _multiSmoothers.clear();
  }

  /// Feeds multiple newly detected raw corner quads and returns smooth, jitter-free corners
  /// for every tracked object.
  List<CropQuadCorners> processMultiple(List<CropQuadCorners> rawBoxes) {
    if (rawBoxes.isEmpty) {
      final surviving = <TemporalCornerSmoother>[];
      final results = <CropQuadCorners>[];
      for (final smoother in _multiSmoothers) {
        final smoothed = smoother.process(null);
        if (smoothed != null) {
          surviving.add(smoother);
          results.add(smoothed);
        }
      }
      _multiSmoothers = surviving;
      _smoothedCorners = results.isNotEmpty ? results.first : null;
      return results;
    }

    final matchedIndices = <int>{};
    final surviving = <TemporalCornerSmoother>[];
    final results = <CropQuadCorners>[];

    for (final raw in rawBoxes) {
      final rawCenter = raw.center;
      int bestIdx = -1;
      double minDistance = double.infinity;

      for (int i = 0; i < _multiSmoothers.length; i++) {
        if (matchedIndices.contains(i)) continue;
        final candidate = _multiSmoothers[i].currentSmoothed;
        if (candidate == null) continue;
        final dist = (candidate.center - rawCenter).distance;
        if (dist < minDistance && dist < 0.35) {
          minDistance = dist;
          bestIdx = i;
        }
      }

      if (bestIdx != -1) {
        matchedIndices.add(bestIdx);
        final smoother = _multiSmoothers[bestIdx];
        final smoothed = smoother.process(raw);
        if (smoothed != null) {
          surviving.add(smoother);
          results.add(smoothed);
        }
      } else {
        // New object detected: create a new smoother
        final newSmoother = TemporalCornerSmoother(
          minAlpha: minAlpha,
          maxAlpha: maxAlpha,
          velocityThreshold: velocityThreshold,
          outlierThreshold: outlierThreshold,
          maxMissedFrames: maxMissedFrames,
        );
        final smoothed = newSmoother.process(raw);
        if (smoothed != null) {
          surviving.add(newSmoother);
          results.add(smoothed);
        }
      }
    }

    // Update unmatched existing smoothers with null (persistence)
    for (int i = 0; i < _multiSmoothers.length; i++) {
      if (!matchedIndices.contains(i)) {
        final smoother = _multiSmoothers[i];
        final smoothed = smoother.process(null);
        if (smoothed != null) {
          surviving.add(smoother);
          results.add(smoothed);
        }
      }
    }

    _multiSmoothers = surviving;
    _smoothedCorners = results.isNotEmpty ? results.first : null;
    return results;
  }

  /// Feeds newly detected raw corners and returns smooth, jitter-free corners.
  /// If [rawCorners] is null (no document detected in current frame),
  /// applies temporal persistence before clearing.
  CropQuadCorners? process(CropQuadCorners? rawCorners) {
    if (rawCorners == null) {
      _missedFrameCount++;
      if (_missedFrameCount > maxMissedFrames) {
        _smoothedCorners = null;
        _previousRawCorners = null;
      }
      return _smoothedCorners;
    }

    _missedFrameCount = 0;

    // First frame initialization
    if (_smoothedCorners == null) {
      _smoothedCorners = rawCorners;
      _previousRawCorners = rawCorners;
      return rawCorners;
    }

    // Outlier rejection: if corners jumped an impossible distance in 1 frame
    final maxJump = _computeMaxCornerDelta(_smoothedCorners!, rawCorners);
    if (maxJump > outlierThreshold) {
      // Reject single-frame glitch, keep existing smoothed estimate
      return _smoothedCorners;
    }

    // Calculate corner velocity between consecutive raw frames
    final velocity = _previousRawCorners != null
        ? _computeMaxCornerDelta(_previousRawCorners!, rawCorners)
        : 0.0;
    _previousRawCorners = rawCorners;

    // Velocity-adaptive alpha:
    // Low velocity -> low alpha (strong smoothing)
    // High velocity -> high alpha (instant tracking)
    final velocityRatio = (velocity / velocityThreshold).clamp(0.0, 1.0);
    final alpha = minAlpha + (maxAlpha - minAlpha) * velocityRatio;

    final tl = _smoothOffset(_smoothedCorners!.topLeft, rawCorners.topLeft, alpha);
    final tr = _smoothOffset(_smoothedCorners!.topRight, rawCorners.topRight, alpha);
    final br = _smoothOffset(_smoothedCorners!.bottomRight, rawCorners.bottomRight, alpha);
    final bl = _smoothOffset(_smoothedCorners!.bottomLeft, rawCorners.bottomLeft, alpha);

    _smoothedCorners = CropQuadCorners(
      topLeft: tl,
      topRight: tr,
      bottomRight: br,
      bottomLeft: bl,
    );

    return _smoothedCorners;
  }

  Offset _smoothOffset(Offset current, Offset target, double alpha) {
    return Offset(
      current.dx + (target.dx - current.dx) * alpha,
      current.dy + (target.dy - current.dy) * alpha,
    );
  }

  double _computeMaxCornerDelta(CropQuadCorners a, CropQuadCorners b) {
    final d1 = (a.topLeft - b.topLeft).distance;
    final d2 = (a.topRight - b.topRight).distance;
    final d3 = (a.bottomRight - b.bottomRight).distance;
    final d4 = (a.bottomLeft - b.bottomLeft).distance;
    return math.max(math.max(d1, d2), math.max(d3, d4));
  }
}
