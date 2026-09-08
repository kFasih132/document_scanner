import 'dart:typed_data';
import 'detection_box.dart';
import 'oriented_detection_box.dart';

/// Single cropped object detection with image thumbnail and metadata
class YoloDetectedCrop {
  final String label;
  final double confidence;
  final int classIndex;
  final Uint8List croppedBytes;
  final DetectionBox? box;
  final OrientedDetectionBox? orientedBox;

  const YoloDetectedCrop({
    required this.label,
    required this.confidence,
    required this.classIndex,
    required this.croppedBytes,
    this.box,
    this.orientedBox,
  });
}

/// Comprehensive output package containing detection boxes, optional crops, and annotated image
class YoloDetectionResult {
  /// Standard 2D bounding boxes
  final List<DetectionBox> boxes;

  /// 4-Point diagonal / oriented bounding boxes
  final List<OrientedDetectionBox> orientedBoxes;

  /// Cropped thumbnails for each detected object
  final List<YoloDetectedCrop> crops;

  /// Full-resolution original image with drawn bounding boxes / diagonal polygons (if requested)
  final Uint8List? annotatedImageBytes;

  /// Inference time in milliseconds
  final int inferenceTimeMs;

  /// Discrete Laplacian variance sharpness score of the input frame
  final double sharpnessScore;

  /// Absolute file path of the cached frame on which detection was performed
  final String? cachedImagePath;

  const YoloDetectionResult({
    this.boxes = const [],
    this.orientedBoxes = const [],
    this.crops = const [],
    this.annotatedImageBytes,
    this.inferenceTimeMs = 0,
    this.sharpnessScore = 0.0,
    this.cachedImagePath,
  });

  bool get isEmpty => boxes.isEmpty && orientedBoxes.isEmpty;
  bool get isNotEmpty => !isEmpty;
  int get totalDetections => boxes.length + orientedBoxes.length;

  /// Creates an empty result
  factory YoloDetectionResult.empty() => const YoloDetectionResult();
}
