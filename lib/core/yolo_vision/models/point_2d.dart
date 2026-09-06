import 'dart:math' as math;

/// Represents a 2D coordinate point with optional confidence, normalized or absolute.
class Point2D {
  final double x;
  final double y;
  final double confidence;

  const Point2D({
    required this.x,
    required this.y,
    this.confidence = 1.0,
  });

  /// Euclidean distance to another point
  double distanceTo(Point2D other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Scales point coordinates by given multipliers
  Point2D scale(double sx, double sy) {
    return Point2D(
      x: x * sx,
      y: y * sy,
      confidence: confidence,
    );
  }

  /// Clamps coordinates to a [min, max] range (usually [0.0, 1.0])
  Point2D clamp([double min = 0.0, double max = 1.0]) {
    return Point2D(
      x: x.clamp(min, max),
      y: y.clamp(min, max),
      confidence: confidence,
    );
  }

  @override
  String toString() => 'Point2D(x: ${x.toStringAsFixed(3)}, y: ${y.toStringAsFixed(3)}, conf: ${confidence.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Point2D &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(x, y, confidence);
}
