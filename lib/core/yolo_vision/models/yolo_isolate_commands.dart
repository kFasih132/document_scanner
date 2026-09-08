import 'dart:isolate';
import 'package:flutter/services.dart';
import 'yolo_model_config.dart';

/// Sealed base class for commands passed across the Isolate boundary
abstract class YoloIsolateCommand {}

/// Initializes BackgroundIsolateBinaryMessenger with the root token
class YoloInitCommand extends YoloIsolateCommand {
  final RootIsolateToken rootIsolateToken;
  final SendPort replyPort;

  YoloInitCommand({
    required this.rootIsolateToken,
    required this.replyPort,
  });
}

/// Loads a model into the isolate's TFLite Interpreter
class YoloLoadModelCommand extends YoloIsolateCommand {
  final YoloModelConfig config;
  final Uint8List modelBytes;
  final SendPort replyPort;

  YoloLoadModelCommand({
    required this.config,
    required this.modelBytes,
    required this.replyPort,
  });
}

/// Dispatches raw camera frame planes for zero-copy live inference
class YoloFrameCommand extends YoloIsolateCommand {
  final Uint8List yPlaneBytes;
  final Uint8List? uPlaneBytes;
  final Uint8List? vPlaneBytes;
  final Uint8List? bgraBytes;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final bool isYuv;
  final double confThreshold;
  final double iouThreshold;
  final int rotationDegrees;
  final String? cacheDirectoryPath;
  final SendPort replyPort;

  YoloFrameCommand({
    required this.yPlaneBytes,
    this.uPlaneBytes,
    this.vPlaneBytes,
    this.bgraBytes,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.isYuv,
    required this.confThreshold,
    required this.iouThreshold,
    this.rotationDegrees = 0,
    this.cacheDirectoryPath,
    required this.replyPort,
  });
}

/// Runs full offline or high-res capture prediction on an image file
class YoloPredictFileCommand extends YoloIsolateCommand {
  final String imagePath;
  final double confThreshold;
  final double iouThreshold;
  final bool generateAnnotatedImage;
  final SendPort replyPort;

  YoloPredictFileCommand({
    required this.imagePath,
    required this.confThreshold,
    required this.iouThreshold,
    this.generateAnnotatedImage = true,
    required this.replyPort,
  });
}

/// Gracefully disposes interpreter and shuts down isolate
class YoloDisposeCommand extends YoloIsolateCommand {}
