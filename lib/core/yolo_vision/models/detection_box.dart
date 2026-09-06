import 'dart:math' as math;

/// Represents a standard 2D axis-aligned bounding box.
/// Coordinates (x1, y1, x2, y2) can be normalized [0.0 - 1.0] or pixel values.
class DetectionBox {
  final String label;
  final double confidence;
  final int classIndex;

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const DetectionBox({
    required this.label,
    required this.confidence,
    required this.classIndex,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  double get width => math.max(0.0, x2 - x1);
  double get height => math.max(0.0, y2 - y1);
  double get area => width * height;
  double get centerX => x1 + (width / 2.0);
  double get centerY => y1 + (height / 2.0);

  /// Scales normalized coordinates [0.0 - 1.0] to a given canvas/image size
  DetectionBox toAbsolute(double width, double height) {
    return DetectionBox(
      label: label,
      confidence: confidence,
      classIndex: classIndex,
      x1: x1 * width,
      y1: y1 * height,
      x2: x2 * width,
      y2: y2 * height,
    );
  }

  /// Scales absolute pixel coordinates to normalized [0.0 - 1.0]
  DetectionBox toNormalized(double width, double height) {
    if (width <= 0 || height <= 0) return this;
    return DetectionBox(
      label: label,
      confidence: confidence,
      classIndex: classIndex,
      x1: (x1 / width).clamp(0.0, 1.0),
      y1: (y1 / height).clamp(0.0, 1.0),
      x2: (x2 / width).clamp(0.0, 1.0),
      y2: (y2 / height).clamp(0.0, 1.0),
    );
  }

  /// Calculates Intersection over Union (IoU) with another box
  double calculateIou(DetectionBox other) {
    final ix1 = math.max(x1, other.x1);
    final iy1 = math.max(y1, other.y1);
    final ix2 = math.min(x2, other.x2);
    final iy2 = math.min(y2, other.y2);

    final intersection = math.max(0.0, ix2 - ix1) * math.max(0.0, iy2 - iy1);
    final union = area + other.area - intersection;
    return union <= 0.0 ? 0.0 : intersection / union;
  }
}
