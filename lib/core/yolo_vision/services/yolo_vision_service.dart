import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/detection_box.dart';
import '../models/oriented_detection_box.dart';
import '../models/point_2d.dart';
import '../models/yolo_detection_result.dart';
import '../models/yolo_model_config.dart';

/// Core math, parsing, and execution service for YOLO object and 4-point pose models.
/// Completely decoupled and stateless where possible so it can run on both UI and background isolates.
class YoloVisionService {
  Interpreter? _interpreter;
  YoloModelConfig? _config;

  bool get isModelLoaded => _interpreter != null;
  YoloModelConfig? get currentConfig => _config;

  static final List<img.ColorRgb8> _palette = [
    img.ColorRgb8(0, 122, 255), // Vivid Blue
    img.ColorRgb8(52, 199, 89), // Apple Green
    img.ColorRgb8(255, 149, 0), // Orange
    img.ColorRgb8(255, 59, 48), // Coral Red
    img.ColorRgb8(175, 82, 222), // Purple
    img.ColorRgb8(255, 204, 0), // Yellow
    img.ColorRgb8(88, 86, 214), // Indigo
    img.ColorRgb8(90, 200, 250), // Teal
  ];

  /// Loads model into the local interpreter
  Future<bool> loadModel(YoloModelConfig config) async {
    try {
      _interpreter?.close();

      final options = InterpreterOptions()
        ..useNnApiForAndroid = true
        ..threads = 4;

      try {
        if (config.modelBytes != null) {
          _interpreter = Interpreter.fromBuffer(
            config.modelBytes!,
            options: options,
          );
        } else if (config.filePath != null) {
          _interpreter = Interpreter.fromFile(
            File(config.filePath!),
            options: options,
          );
        } else if (config.assetPath != null) {
          _interpreter = await Interpreter.fromAsset(
            config.assetPath!,
            options: options,
          );
        } else {
          throw ArgumentError('YoloModelConfig has no valid model source');
        }
      } catch (e) {
        // Fallback to CPU with 4 threads
        final cpuOptions = InterpreterOptions()..threads = 4;
        if (config.modelBytes != null) {
          _interpreter = Interpreter.fromBuffer(
            config.modelBytes!,
            options: cpuOptions,
          );
        } else if (config.filePath != null) {
          _interpreter = Interpreter.fromFile(
            File(config.filePath!),
            options: cpuOptions,
          );
        } else if (config.assetPath != null) {
          _interpreter = await Interpreter.fromAsset(
            config.assetPath!,
            options: cpuOptions,
          );
        }
      }

      _config = config;
      return true;
    } catch (e) {
      debugPrint('[YoloVisionService] loadModel error: $e');
      _interpreter = null;
      _config = null;
      return false;
    }
  }

  /// Sets an externally loaded interpreter (useful inside isolates)
  void setInterpreter(Interpreter interpreter, YoloModelConfig config) {
    _interpreter?.close();
    _interpreter = interpreter;
    _config = config;
  }

  /// Prepares image input tensor for inference from an img.Image
  static (dynamic, int, int) prepareImageInput({
    required img.Image original,
    required List<int> inputShape,
    bool forceNCHW = true,
  }) {
    final isNCHW = inputShape.length == 4 && inputShape[1] == 3;
    final targetH = isNCHW
        ? inputShape[2]
        : (inputShape.length == 4 ? inputShape[1] : 768);
    final targetW = isNCHW
        ? inputShape[3]
        : (inputShape.length == 4 ? inputShape[2] : 768);

    final resized = img.copyResize(original, width: targetW, height: targetH);

    if (isNCHW) {
      final buffer = List.generate(
        1,
        (_) => List.generate(
          3,
          (c) => List.generate(
            targetH,
            (y) => List.generate(targetW, (x) {
              final pixel = resized.getPixel(x, y);
              return (c == 0 ? pixel.r : (c == 1 ? pixel.g : pixel.b)) / 255.0;
            }),
          ),
        ),
      );
      return (buffer, targetW, targetH);
    } else {
      final buffer = List.generate(
        1,
        (_) => List.generate(
          targetH,
          (y) => List.generate(targetW, (x) {
            final pixel = resized.getPixel(x, y);
            return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
          }),
        ),
      );
      return (buffer, targetW, targetH);
    }
  }

  /// Parses output tensor for Standard YOLO 2D Object Detection
  static List<DetectionBox> parseStandardDetections({
    required dynamic output,
    required List<int> outputShape,
    required int inputWidth,
    required int inputHeight,
    required double confThreshold,
    required List<String> labels,
  }) {
    final List<DetectionBox> candidates = [];
    if (outputShape.length != 3) return candidates;

    final dim1 = outputShape[1];
    final dim2 = outputShape[2];

    if (dim1 < dim2) {
      // Channels-first: [1, Channels, Anchors]
      final numAnchors = dim2;
      final numClasses = labels.isNotEmpty ? labels.length : (dim1 - 4);

      for (int i = 0; i < numAnchors; i++) {
        double maxScore = 0.0;
        int bestClass = 0;

        for (int c = 0; c < numClasses; c++) {
          final prob = (output[0][4 + c][i] as num).toDouble();
          if (prob > maxScore) {
            maxScore = prob;
            bestClass = c;
          }
        }

        if (maxScore >= confThreshold) {
          double cx = (output[0][0][i] as num).toDouble();
          double cy = (output[0][1][i] as num).toDouble();
          double w = (output[0][2][i] as num).toDouble();
          double h = (output[0][3][i] as num).toDouble();

          if (cx <= 1.0 && cy <= 1.0 && w <= 1.0 && h <= 1.0) {
            cx *= inputWidth;
            cy *= inputHeight;
            w *= inputWidth;
            h *= inputHeight;
          }

          final label = labels.length > bestClass
              ? labels[bestClass]
              : 'Class $bestClass';

          candidates.add(
            DetectionBox(
              label: label,
              confidence: maxScore,
              classIndex: bestClass,
              x1: cx - (w / 2.0),
              y1: cy - (h / 2.0),
              x2: cx + (w / 2.0),
              y2: cy + (h / 2.0),
            ),
          );
        }
      }
    } else {
      // Channels-last: [1, Anchors, Channels]
      final numAnchors = dim1;
      final numChannels = dim2;
      final hasObj = numChannels == 5 + labels.length;
      final offset = hasObj ? 5 : 4;
      final numClasses = numChannels - offset;

      for (int i = 0; i < numAnchors; i++) {
        final row = output[0][i];
        final obj = hasObj ? (row[4] as num).toDouble() : 1.0;

        double maxProb = 0.0;
        int bestClass = 0;

        for (int c = 0; c < numClasses; c++) {
          final prob = (row[offset + c] as num).toDouble();
          if (prob > maxProb) {
            maxProb = prob;
            bestClass = c;
          }
        }

        final score = obj * maxProb;
        if (score >= confThreshold) {
          double cx = (row[0] as num).toDouble();
          double cy = (row[1] as num).toDouble();
          double w = (row[2] as num).toDouble();
          double h = (row[3] as num).toDouble();

          if (cx <= 1.0 && cy <= 1.0 && w <= 1.0 && h <= 1.0) {
            cx *= inputWidth;
            cy *= inputHeight;
            w *= inputWidth;
            h *= inputHeight;
          }

          final label = labels.length > bestClass
              ? labels[bestClass]
              : 'Class $bestClass';

          candidates.add(
            DetectionBox(
              label: label,
              confidence: score,
              classIndex: bestClass,
              x1: cx - (w / 2.0),
              y1: cy - (h / 2.0),
              x2: cx + (w / 2.0),
              y2: cy + (h / 2.0),
            ),
          );
        }
      }
    }

    return candidates;
  }

  /// Parses output tensor for YOLO-Pose with 4 Keypoints (Oriented / Diagonal Quadrilateral).
  static List<OrientedDetectionBox> parsePose4PointDetections({
    required dynamic output,
    required List<int> outputShape,
    required int inputWidth,
    required int inputHeight,
    required double confThreshold,
    required List<String> labels,
    int numKeypoints = 4,
    int keypointDim = 3,
  }) {
    final List<OrientedDetectionBox> candidates = [];
    if (outputShape.length != 3) return candidates;

    final dim1 = outputShape[1];
    final dim2 = outputShape[2];
    final numClasses = labels.isNotEmpty ? labels.length : 1;
    final keypointChannels = numKeypoints * keypointDim;

    // Log once per call for debugging
    bool logged = false;

    if (dim1 < dim2) {
      // Channels-first: [1, Channels, Anchors]
      final numAnchors = dim2;
      final numChannels = dim1;
      final expectedWithoutObj = 4 + numClasses + keypointChannels;
      final hasObj = numChannels > expectedWithoutObj;
      final classOffset = hasObj ? 5 : 4;
      final keypointOffset = classOffset + numClasses;

      dev.log(
        '📐 [YOLO] Channels-FIRST: shape=$outputShape, '
        'numChannels=$numChannels, numClasses=$numClasses, '
        'hasObj=$hasObj, classOffset=$classOffset, keypointOffset=$keypointOffset',
        name: 'YOLO',
      );

      double topScoreInBatch = 0.0;
      for (int i = 0; i < numAnchors; i++) {
        final obj = hasObj ? (output[0][4][i] as num).toDouble() : 1.0;

        double maxClassScore = 0.0;
        int bestClass = 0;

        for (int c = 0; c < numClasses; c++) {
          final prob = (output[0][classOffset + c][i] as num).toDouble();
          if (prob > maxClassScore) {
            maxClassScore = prob;
            bestClass = c;
          }
        }

        // For 1-class models, row[4] is often the direct detection confidence.
        // If obj is valid but class score is 0, use obj; otherwise use obj * classScore.
        final score = (numClasses == 1 && hasObj)
            ? (obj > 0 && maxClassScore == 0
                  ? obj
                  : (obj * (maxClassScore > 0 ? maxClassScore : 1.0)))
            : (obj * maxClassScore);

        if (score > topScoreInBatch) {
          topScoreInBatch = score;
        }

        if (score >= confThreshold) {
          double cx = (output[0][0][i] as num).toDouble();
          double cy = (output[0][1][i] as num).toDouble();
          double w = (output[0][2][i] as num).toDouble();
          double h = (output[0][3][i] as num).toDouble();

          final isNormalized = cx <= 1.0 && cy <= 1.0 && w <= 1.0 && h <= 1.0;
          if (isNormalized) {
            cx *= inputWidth;
            cy *= inputHeight;
            w *= inputWidth;
            h *= inputHeight;
          }

          final points = <Point2D>[];
          for (int k = 0; k < numKeypoints; k++) {
            final idx = keypointOffset + (k * keypointDim);
            double px = (output[0][idx][i] as num).toDouble();
            double py = (output[0][idx + 1][i] as num).toDouble();
            final pconf = keypointDim >= 3
                ? (output[0][idx + 2][i] as num).toDouble()
                : 1.0;

            if (isNormalized || (px <= 1.0 && py <= 1.0)) {
              px *= inputWidth;
              py *= inputHeight;
            }

            points.add(Point2D(x: px, y: py, confidence: pconf));
          }

          if (!logged) {
            dev.log(
              '🎯 [YOLO] DETECTED! score=${score.toStringAsFixed(3)} box=($cx,$cy,$w,$h)\n'
              '   📍 kp0=(${points[0].x.toStringAsFixed(1)}, ${points[0].y.toStringAsFixed(1)})\n'
              '   📍 kp1=(${points[1].x.toStringAsFixed(1)}, ${points[1].y.toStringAsFixed(1)})\n'
              '   📍 kp2=(${points[2].x.toStringAsFixed(1)}, ${points[2].y.toStringAsFixed(1)})\n'
              '   📍 kp3=(${points[3].x.toStringAsFixed(1)}, ${points[3].y.toStringAsFixed(1)})',
              name: 'YOLO',
            );
            logged = true;
          }

          final label = labels.length > bestClass
              ? labels[bestClass]
              : 'Pose $bestClass';

          candidates.add(
            OrientedDetectionBox.fromPoints(
              label: label,
              confidence: score,
              classIndex: bestClass,
              points: points,
            ),
          );
        }
      }
    } else {
      // Channels-last: [1, Anchors, Channels] — our model outputs [1, 300, 18]
      final numAnchors = dim1;
      final numChannels = dim2;
      final expectedWithoutObj = 4 + numClasses + keypointChannels;
      final hasObj = numChannels > expectedWithoutObj;
      final classOffset = hasObj ? 5 : 4;
      final keypointOffset = classOffset + numClasses;

      dev.log(
        '📐 [YOLO] Channels-LAST: shape=$outputShape, '
        'numChannels=$numChannels, numClasses=$numClasses, '
        'hasObj=$hasObj, classOffset=$classOffset, keypointOffset=$keypointOffset',
        name: 'YOLO',
      );

      // Log raw values from first anchor for debugging
      if (numAnchors > 0) {
        final row0 = output[0][0];
        final rawVals = List.generate(
          numChannels < 18 ? numChannels : 18,
          (j) => (row0[j] as num).toDouble().toStringAsFixed(4),
        );
        dev.log('🔍 [YOLO] Raw anchor[0]: $rawVals', name: 'YOLO');
      }

      double topScoreInBatch = 0.0;
      for (int i = 0; i < numAnchors; i++) {
        final row = output[0][i];
        final obj = hasObj ? (row[4] as num).toDouble() : 1.0;

        double maxClassScore = 0.0;
        int bestClass = 0;

        for (int c = 0; c < numClasses; c++) {
          final prob = (row[classOffset + c] as num).toDouble();
          if (prob > maxClassScore) {
            maxClassScore = prob;
            bestClass = c;
          }
        }

        // For 1-class models, row[4] is often the direct detection confidence.
        // If obj is valid but class score is 0, use obj; otherwise use obj * classScore.
        final score = (numClasses == 1 && hasObj)
            ? (obj > 0 && maxClassScore == 0
                  ? obj
                  : (obj * (maxClassScore > 0 ? maxClassScore : 1.0)))
            : (obj * maxClassScore);

        if (score > topScoreInBatch) {
          topScoreInBatch = score;
        }

        if (score >= confThreshold) {
          double cx = (row[0] as num).toDouble();
          double cy = (row[1] as num).toDouble();
          double w = (row[2] as num).toDouble();
          double h = (row[3] as num).toDouble();

          final isNormalized = cx <= 1.0 && cy <= 1.0 && w <= 1.0 && h <= 1.0;
          if (isNormalized) {
            cx *= inputWidth;
            cy *= inputHeight;
            w *= inputWidth;
            h *= inputHeight;
          }

          final points = <Point2D>[];
          for (int k = 0; k < numKeypoints; k++) {
            final idx = keypointOffset + (k * keypointDim);
            double px = (row[idx] as num).toDouble();
            double py = (row[idx + 1] as num).toDouble();
            final pconf = keypointDim >= 3
                ? (row[idx + 2] as num).toDouble()
                : 1.0;

            if (isNormalized || (px <= 1.0 && py <= 1.0)) {
              px *= inputWidth;
              py *= inputHeight;
            }

            points.add(Point2D(x: px, y: py, confidence: pconf));
          }

          if (!logged) {
            dev.log(
              '🎯 [YOLO] DETECTED! score=${score.toStringAsFixed(3)} box=($cx,$cy,$w,$h)\n'
              '   📍 kp0=(${points[0].x.toStringAsFixed(1)}, ${points[0].y.toStringAsFixed(1)})\n'
              '   📍 kp1=(${points[1].x.toStringAsFixed(1)}, ${points[1].y.toStringAsFixed(1)})\n'
              '   📍 kp2=(${points[2].x.toStringAsFixed(1)}, ${points[2].y.toStringAsFixed(1)})\n'
              '   📍 kp3=(${points[3].x.toStringAsFixed(1)}, ${points[3].y.toStringAsFixed(1)})',
              name: 'YOLO',
            );
            logged = true;
          }

          final label = labels.length > bestClass
              ? labels[bestClass]
              : 'Pose $bestClass';

          candidates.add(
            OrientedDetectionBox.fromPoints(
              label: label,
              confidence: score,
              classIndex: bestClass,
              points: points,
            ),
          );
        }
      }

      if (candidates.isEmpty) {
        dev.log(
          'ℹ️ [YOLO] Top confidence in batch: ${topScoreInBatch.toStringAsFixed(4)} (threshold: $confThreshold)',
          name: 'YOLO',
        );
      }
    }

    return candidates;
  }

  /// NMS for standard 2D boxes
  static List<DetectionBox> applyNms(
    List<DetectionBox> boxes, {
    required double iouThreshold,
    bool isNmsFree = false,
  }) {
    if (boxes.isEmpty) return [];
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    if (isNmsFree) return boxes;

    final List<DetectionBox> selected = [];
    for (final box in boxes) {
      bool keep = true;
      for (final s in selected) {
        if (box.calculateIou(s) > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) selected.add(box);
    }
    return selected;
  }

  /// NMS for 4-point diagonal boxes based on envelope IoU
  static List<OrientedDetectionBox> applyOrientedNms(
    List<OrientedDetectionBox> boxes, {
    required double iouThreshold,
    bool isNmsFree = false,
  }) {
    if (boxes.isEmpty) return [];
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    if (isNmsFree) return boxes;

    final List<OrientedDetectionBox> selected = [];
    for (final box in boxes) {
      bool keep = true;
      final boxEnvelope = DetectionBox(
        label: box.label,
        confidence: box.confidence,
        classIndex: box.classIndex,
        x1: box.x1,
        y1: box.y1,
        x2: box.x2,
        y2: box.y2,
      );

      for (final s in selected) {
        final sEnvelope = DetectionBox(
          label: s.label,
          confidence: s.confidence,
          classIndex: s.classIndex,
          x1: s.x1,
          y1: s.y1,
          x2: s.x2,
          y2: s.y2,
        );

        if (boxEnvelope.calculateIou(sEnvelope) > iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) selected.add(box);
    }
    return selected;
  }

  /// Draws bounding boxes / diagonal quadrilaterals onto an img.Image and crops detections
  static YoloDetectionResult buildAnnotatedResult({
    required img.Image originalImage,
    required int inputWidth,
    required int inputHeight,
    List<DetectionBox> standardBoxes = const [],
    List<OrientedDetectionBox> orientedBoxes = const [],
    bool generateAnnotatedImage = true,
  }) {
    final scaleX = originalImage.width / inputWidth;
    final scaleY = originalImage.height / inputHeight;

    img.Image? resultImage;
    if (generateAnnotatedImage) {
      resultImage = img.Image.from(originalImage);
    }

    final crops = <YoloDetectedCrop>[];

    // Process 4-Point Diagonal Boxes
    for (final ob in orientedBoxes) {
      final p1 = ob.p1.scale(scaleX, scaleY);
      final p2 = ob.p2.scale(scaleX, scaleY);
      final p3 = ob.p3.scale(scaleX, scaleY);
      final p4 = ob.p4.scale(scaleX, scaleY);

      final color = _palette[ob.classIndex % _palette.length];

      if (resultImage != null) {
        // Draw the 4 edges of the diagonal polygon
        img.drawLine(
          resultImage,
          x1: p1.x.round(),
          y1: p1.y.round(),
          x2: p2.x.round(),
          y2: p2.y.round(),
          color: color,
          thickness: 4,
        );
        img.drawLine(
          resultImage,
          x1: p2.x.round(),
          y1: p2.y.round(),
          x2: p3.x.round(),
          y2: p3.y.round(),
          color: color,
          thickness: 4,
        );
        img.drawLine(
          resultImage,
          x1: p3.x.round(),
          y1: p3.y.round(),
          x2: p4.x.round(),
          y2: p4.y.round(),
          color: color,
          thickness: 4,
        );
        img.drawLine(
          resultImage,
          x1: p4.x.round(),
          y1: p4.y.round(),
          x2: p1.x.round(),
          y2: p1.y.round(),
          color: color,
          thickness: 4,
        );

        for (final p in [p1, p2, p3, p4]) {
          img.fillCircle(
            resultImage,
            x: p.x.round(),
            y: p.y.round(),
            radius: 6,
            color: img.ColorRgb8(255, 255, 255),
          );
          img.drawCircle(
            resultImage,
            x: p.x.round(),
            y: p.y.round(),
            radius: 6,
            color: color,
          );
        }
      }

      final ex1 = (ob.x1 * scaleX).round().clamp(0, originalImage.width - 1);
      final ey1 = (ob.y1 * scaleY).round().clamp(0, originalImage.height - 1);
      final ex2 = (ob.x2 * scaleX).round().clamp(0, originalImage.width - 1);
      final ey2 = (ob.y2 * scaleY).round().clamp(0, originalImage.height - 1);
      final ew = (ex2 - ex1).clamp(1, originalImage.width - ex1);
      final eh = (ey2 - ey1).clamp(1, originalImage.height - ey1);

      final cropped = img.copyCrop(
        originalImage,
        x: ex1,
        y: ey1,
        width: ew,
        height: eh,
      );

      crops.add(
        YoloDetectedCrop(
          label: ob.label,
          confidence: ob.confidence,
          classIndex: ob.classIndex,
          croppedBytes: Uint8List.fromList(img.encodeJpg(cropped, quality: 90)),
          orientedBox: ob,
        ),
      );
    }

    return YoloDetectionResult(
      boxes: standardBoxes,
      orientedBoxes: orientedBoxes,
      crops: crops,
      annotatedImageBytes: resultImage != null
          ? Uint8List.fromList(img.encodeJpg(resultImage, quality: 90))
          : null,
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _config = null;
  }
}
