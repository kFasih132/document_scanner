import 'dart:math' as math;
import 'point_2d.dart';

/// Represents a 4-point oriented / diagonal bounding box (Quadrilateral / YOLO-Pose).
/// The points [p1, p2, p3, p4] represent the 4 ordered vertices of the quadrilateral.
class OrientedDetectionBox {
  final String label;
  final double confidence;
  final int classIndex;

  /// Exactly 4 ordered vertices: Top-Left, Top-Right, Bottom-Right, Bottom-Left
  final List<Point2D> points;

  /// Optional bounding box envelope around the 4 points
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const OrientedDetectionBox({
    required this.label,
    required this.confidence,
    required this.classIndex,
    required this.points,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  }) : assert(points.length == 4, 'OrientedDetectionBox must have exactly 4 points');

  Point2D get p1 => points[0];
  Point2D get p2 => points[1];
  Point2D get p3 => points[2];
  Point2D get p4 => points[3];

  /// Center point (centroid) of the 4 vertices
  Point2D get center {
    final cx = (p1.x + p2.x + p3.x + p4.x) / 4.0;
    final cy = (p1.y + p2.y + p3.y + p4.y) / 4.0;
    return Point2D(x: cx, y: cy);
  }

  /// Calculates the area of the 4-point quadrilateral using the Shoelace formula
  double get polygonArea {
    final s1 = (p1.x * p2.y) + (p2.x * p3.y) + (p3.x * p4.y) + (p4.x * p1.y);
    final s2 = (p1.y * p2.x) + (p2.y * p3.x) + (p3.y * p4.x) + (p4.y * p1.x);
    return 0.5 * (s1 - s2).abs();
  }

  /// Estimated tilt angle in radians relative to horizontal axis
  double get angleRadians {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    return math.atan2(dy, dx);
  }

  /// Estimated tilt angle in degrees
  double get angleDegrees => angleRadians * (180.0 / math.pi);

  /// Scales normalized [0.0 - 1.0] coordinates to canvas or image dimensions
  OrientedDetectionBox toAbsolute(double width, double height) {
    return OrientedDetectionBox(
      label: label,
      confidence: confidence,
      classIndex: classIndex,
      points: points.map((p) => p.scale(width, height)).toList(growable: false),
      x1: x1 * width,
      y1: y1 * height,
      x2: x2 * width,
      y2: y2 * height,
    );
  }

  /// Normalizes absolute pixel coordinates to [0.0 - 1.0]
  OrientedDetectionBox toNormalized(double width, double height) {
    if (width <= 0 || height <= 0) return this;
    return OrientedDetectionBox(
      label: label,
      confidence: confidence,
      classIndex: classIndex,
      points: points
          .map((p) => Point2D(
                x: (p.x / width).clamp(0.0, 1.0),
                y: (p.y / height).clamp(0.0, 1.0),
                confidence: p.confidence,
              ))
          .toList(growable: false),
      x1: (x1 / width).clamp(0.0, 1.0),
      y1: (y1 / height).clamp(0.0, 1.0),
      x2: (x2 / width).clamp(0.0, 1.0),
      y2: (y2 / height).clamp(0.0, 1.0),
    );
  }

  /// Rotates normalized [0.0 - 1.0] coordinates clockwise by the given degrees
  OrientedDetectionBox rotate(int degrees) {
    if (degrees == 0 || degrees % 360 == 0) return this;

    Point2D rotatePoint(Point2D p) {
      double nx = p.x;
      double ny = p.y;
      
      int normalizedDegrees = ((degrees % 360) + 360) % 360;
      if (normalizedDegrees == 90) {
        nx = 1.0 - p.y;
        ny = p.x;
      } else if (normalizedDegrees == 180) {
        nx = 1.0 - p.x;
        ny = 1.0 - p.y;
      } else if (normalizedDegrees == 270) {
        nx = p.y;
        ny = 1.0 - p.x;
      }
      return Point2D(x: nx, y: ny, confidence: p.confidence);
    }

    final rotatedPoints = points.map(rotatePoint).toList(growable: false);

    return OrientedDetectionBox.fromPoints(
      label: label,
      confidence: confidence,
      classIndex: classIndex,
      points: rotatedPoints,
    );
  }

  /// Factory helper that computes the envelope [x1, y1, x2, y2] automatically from the 4 points
  factory OrientedDetectionBox.fromPoints({
    required String label,
    required double confidence,
    required int classIndex,
    required List<Point2D> points,
  }) {
    assert(points.length == 4);
    double minX = points[0].x;
    double minY = points[0].y;
    double maxX = points[0].x;
    double maxY = points[0].y;

    for (int i = 1; i < 4; i++) {
      if (points[i].x < minX) minX = points[i].x;
      if (points[i].y < minY) minY = points[i].y;
      if (points[i].x > maxX) maxX = points[i].x;
      if (points[i].y > maxY) maxY = points[i].y;
    }

    return OrientedDetectionBox(
      label: label,
      confidence: confidence,
      classIndex: classIndex,
      points: points,
      x1: minX,
      y1: minY,
      x2: maxX,
      y2: maxY,
    );
  }
}
