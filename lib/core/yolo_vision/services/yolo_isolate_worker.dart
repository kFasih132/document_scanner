import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/yolo_detection_result.dart';
import '../models/yolo_isolate_commands.dart';
import '../models/yolo_model_config.dart';
import '../models/yolo_model_type.dart';
import 'fast_tensor_converter.dart';
import 'yolo_vision_service.dart';

/// Background worker managing TFLite inference in a dedicated OS isolate.
/// Supports high-framerate camera streaming with zero-allocation tensor conversion,
/// automated frame dropping, and both Standard YOLO & 4-Point Pose models.
class YoloIsolateWorker {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isProcessing = false;

  bool get isInitialized => _isInitialized && !_isDisposed;
  bool get isProcessing => _isProcessing;

  /// Spawns the worker isolate and establishes two-way communication port
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isDisposed = false;

    try {
      final rootToken = RootIsolateToken.instance;
      if (rootToken == null) {
        debugPrint('[YoloWorker] RootIsolateToken is null');
        return false;
      }

      _receivePort = ReceivePort();
      final completer = Completer<SendPort>();

      _receivePort!.listen((message) {
        if (message is SendPort && !completer.isCompleted) {
          completer.complete(message);
        }
      });

      _isolate = await Isolate.spawn(
        _isolateEntryPoint,
        _receivePort!.sendPort,
        debugName: 'YoloVisionWorkerIsolate',
      );

      _sendPort = await completer.future.timeout(const Duration(seconds: 4));

      final handshakePort = ReceivePort();
      _sendPort!.send(
        YoloInitCommand(
          rootIsolateToken: rootToken,
          replyPort: handshakePort.sendPort,
        ),
      );

      await handshakePort.first.timeout(const Duration(seconds: 4));
      handshakePort.close();

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('[YoloWorker] initialize error: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Sends a model loading command to the background isolate.
  Future<bool> loadModel(YoloModelConfig config) async {
    if (!_isInitialized || _sendPort == null || _isDisposed) return false;

    Uint8List modelBytes;
    try {
      if (config.modelBytes != null) {
        modelBytes = config.modelBytes!;
      } else if (config.filePath != null) {
        modelBytes = await File(config.filePath!).readAsBytes();
      } else if (config.assetPath != null) {
        final assetData = await rootBundle.load(config.assetPath!);
        modelBytes = assetData.buffer.asUint8List(
          assetData.offsetInBytes,
          assetData.lengthInBytes,
        );
      } else {
        return false;
      }
    } catch (e) {
      debugPrint('[YoloWorker] loadModel bytes error: $e');
      return false;
    }

    final replyPort = ReceivePort();
    try {
      _sendPort!.send(
        YoloLoadModelCommand(
          config: config,
          modelBytes: modelBytes,
          replyPort: replyPort.sendPort,
        ),
      );

      final result = await replyPort.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );

      return result is bool ? result : false;
    } catch (e) {
      debugPrint('[YoloWorker] loadModel isolate error: $e');
      return false;
    } finally {
      replyPort.close();
    }
  }

  /// Dispatches a live camera frame to the background isolate.
  /// If isolate is currently busy, it immediately drops the frame to keep camera smooth.
  Future<YoloDetectionResult?> processFrame({
    required Uint8List yPlaneBytes,
    Uint8List? uPlaneBytes,
    Uint8List? vPlaneBytes,
    Uint8List? bgraBytes,
    required int width,
    required int height,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required bool isYuv,
    required double confThreshold,
    required double iouThreshold,
    int rotationDegrees = 0,
  }) async {
    if (!_isInitialized || _sendPort == null || _isDisposed || _isProcessing) {
      return null;
    }

    _isProcessing = true;
    final responsePort = ReceivePort();

    try {
      _sendPort!.send(
        YoloFrameCommand(
          yPlaneBytes: yPlaneBytes,
          uPlaneBytes: uPlaneBytes,
          vPlaneBytes: vPlaneBytes,
          bgraBytes: bgraBytes,
          width: width,
          height: height,
          yRowStride: yRowStride,
          uvRowStride: uvRowStride,
          uvPixelStride: uvPixelStride,
          isYuv: isYuv,
          confThreshold: confThreshold,
          iouThreshold: iouThreshold,
          rotationDegrees: rotationDegrees,
          replyPort: responsePort.sendPort,
        ),
      );

      final result = await responsePort.first.timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );

      return result is YoloDetectionResult ? result : null;
    } catch (e) {
      debugPrint('[YoloWorker] processFrame error: $e');
      return null;
    } finally {
      responsePort.close();
      _isProcessing = false;
    }
  }

  /// Runs full offline or high-res capture prediction on an image file
  Future<YoloDetectionResult?> predictFile(
    String imagePath, {
    required double confThreshold,
    required double iouThreshold,
    bool generateAnnotatedImage = true,
  }) async {
    if (!_isInitialized || _sendPort == null || _isDisposed) return null;

    final responsePort = ReceivePort();
    try {
      _sendPort!.send(
        YoloPredictFileCommand(
          imagePath: imagePath,
          confThreshold: confThreshold,
          iouThreshold: iouThreshold,
          generateAnnotatedImage: generateAnnotatedImage,
          replyPort: responsePort.sendPort,
        ),
      );

      final result = await responsePort.first.timeout(
        const Duration(seconds: 25),
        onTimeout: () => null,
      );

      return result is YoloDetectionResult ? result : null;
    } catch (e) {
      debugPrint('[YoloWorker] predictFile error: $e');
      return null;
    } finally {
      responsePort.close();
    }
  }

  /// Shuts down the background isolate and releases native TFLite memory
  Future<void> dispose() async {
    _isDisposed = true;
    _isInitialized = false;

    if (_sendPort != null) {
      try {
        _sendPort!.send(YoloDisposeCommand());
      } catch (_) {}
      _sendPort = null;
    }

    if (_receivePort != null) {
      _receivePort!.close();
      _receivePort = null;
    }

    if (_isolate != null) {
      _isolate!.kill(priority: Isolate.beforeNextEvent);
      _isolate = null;
    }
  }

  // ===========================================================================
  // BACKGROUND ISOLATE RUNTIME ENGINE
  // ===========================================================================

  static void _isolateEntryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    Interpreter? interpreter;
    YoloModelConfig? currentConfig;

    isolateReceivePort.listen((dynamic message) async {
      // 1. Root binary messenger setup
      if (message is YoloInitCommand) {
        BackgroundIsolateBinaryMessenger.ensureInitialized(
          message.rootIsolateToken,
        );
        message.replyPort.send(true);
        return;
      }

      // 2. Model loading
      if (message is YoloLoadModelCommand) {
        if (currentConfig?.modelId == message.config.modelId &&
            interpreter != null) {
          message.replyPort.send(true);
          return;
        }

        interpreter?.close();
        bool success = false;
        try {
          final options = InterpreterOptions()..threads = 4;
          
          try {
            if (Platform.isAndroid) {
              options.addDelegate(GpuDelegateV2());
            } else if (Platform.isIOS) {
              options.addDelegate(GpuDelegate());
            }
          } catch (e) {
            dev.log('⚠️ [YOLO Worker] Could not attach GPU Delegate, falling back to NNAPI: $e', name: 'YOLO');
            options.useNnApiForAndroid = true;
          }

          try {
            interpreter = Interpreter.fromBuffer(
              message.modelBytes,
              options: options,
            );
            dev.log(
              '🚀 [YOLO Worker] Interpreter initialized with GPU/NNAPI & 4 threads',
              name: 'YOLO',
            );
          } catch (e) {
            // Fallback to multithreaded CPU if device hardware delegate fails
            dev.log(
              '⚠️ [YOLO Worker] Hardware delegate fallback to multithreaded CPU: $e',
              name: 'YOLO',
            );
            final cpuOptions = InterpreterOptions()..threads = 4;
            interpreter = Interpreter.fromBuffer(
              message.modelBytes,
              options: cpuOptions,
            );
          }

          currentConfig = message.config;
          success = true;
        } catch (e) {
          debugPrint('[YoloWorkerIsolate] Interpreter.fromBuffer error: $e');
          interpreter = null;
          currentConfig = null;
        }
        message.replyPort.send(success);
        return;
      }

      // 3. Live camera frame inference
      if (message is YoloFrameCommand) {
        if (interpreter == null || currentConfig == null) {
          message.replyPort.send(YoloDetectionResult.empty());
          return;
        }

        try {
          final config = currentConfig!;
          final inputShape = interpreter!.getInputTensor(0).shape;
          final isNCHW = inputShape.length == 4 && inputShape[1] == 3;
          final targetH = isNCHW
              ? inputShape[2]
              : (inputShape.length == 4 ? inputShape[1] : config.inputHeight);
          final targetW = isNCHW
              ? inputShape[3]
              : (inputShape.length == 4 ? inputShape[2] : config.inputWidth);

          final floatBuffer = FastTensorConverter.frameToFloat32Buffer(
            yPlaneBytes: message.yPlaneBytes,
            uPlaneBytes: message.uPlaneBytes,
            vPlaneBytes: message.vPlaneBytes,
            bgraBytes: message.bgraBytes,
            srcW: message.width,
            srcH: message.height,
            yRowStride: message.yRowStride,
            uvRowStride: message.uvRowStride,
            uvPixelStride: message.uvPixelStride,
            isYuv: message.isYuv,
            targetW: targetW,
            targetH: targetH,
            isNCHW: isNCHW,
          );

          final inputTensor = FastTensorConverter.bufferToNestedTensor(
            buffer: floatBuffer,
            targetW: targetW,
            targetH: targetH,
            isNCHW: isNCHW,
          );

          final outputShape = interpreter!.getOutputTensor(0).shape;
          final totalElements = outputShape.reduce((a, b) => a * b);
          final output = List.filled(totalElements, 0.0).reshape(outputShape);

          final stopwatch = Stopwatch()..start();
          interpreter!.run(inputTensor, output);
          stopwatch.stop();

          if (config.modelType == YoloModelType.pose4Points) {
            final candidates = YoloVisionService.parsePose4PointDetections(
              output: output,
              outputShape: outputShape,
              inputWidth: targetW,
              inputHeight: targetH,
              confThreshold: message.confThreshold,
              labels: config.labels,
              numKeypoints: config.numKeypoints,
              keypointDim: config.keypointDim,
            );

            final selected = YoloVisionService.applyOrientedNms(
              candidates,
              iouThreshold: message.iouThreshold,
              isNmsFree: config.isNmsFree,
            );

            dev.log(
              '⚡ [YOLO Worker] Pose inference: ${stopwatch.elapsedMilliseconds}ms | candidates=${candidates.length} | selected=${selected.length}',
              name: 'YOLO',
            );

            // Normalize coordinates to [0.0 - 1.0] and rotate them to match the camera preview orientation
            final normalized = selected
                .map(
                  (b) => b
                      .toNormalized(targetW.toDouble(), targetH.toDouble())
                      .rotate(message.rotationDegrees),
                )
                .toList();

            message.replyPort.send(
              YoloDetectionResult(
                orientedBoxes: normalized,
                inferenceTimeMs: stopwatch.elapsedMilliseconds,
              ),
            );
          } else {
            final candidates = YoloVisionService.parseStandardDetections(
              output: output,
              outputShape: outputShape,
              inputWidth: targetW,
              inputHeight: targetH,
              confThreshold: message.confThreshold,
              labels: config.labels,
            );

            final selected = YoloVisionService.applyNms(
              candidates,
              iouThreshold: message.iouThreshold,
              isNmsFree: config.isNmsFree,
            );

            final normalized = selected
                .map(
                  (b) => b.toNormalized(targetW.toDouble(), targetH.toDouble()),
                )
                .toList();

            message.replyPort.send(
              YoloDetectionResult(
                boxes: normalized,
                inferenceTimeMs: stopwatch.elapsedMilliseconds,
              ),
            );
          }
        } catch (e) {
          debugPrint('[YoloWorkerIsolate] frame error: $e');
          message.replyPort.send(YoloDetectionResult.empty());
        }
        return;
      }

      // 4. Offline / Full-resolution image file prediction
      if (message is YoloPredictFileCommand) {
        if (interpreter == null || currentConfig == null) {
          message.replyPort.send(null);
          return;
        }

        try {
          final config = currentConfig!;
          final bytes = await File(message.imagePath).readAsBytes();
          final originalImage = img.decodeImage(bytes);
          if (originalImage == null) {
            message.replyPort.send(null);
            return;
          }

          final inputShape = interpreter!.getInputTensor(0).shape;
          final (
            inputBuffer,
            inputW,
            inputH,
          ) = YoloVisionService.prepareImageInput(
            original: originalImage,
            inputShape: inputShape,
          );

          final outputShape = interpreter!.getOutputTensor(0).shape;
          final totalElements = outputShape.reduce((a, b) => a * b);
          final output = List.filled(totalElements, 0.0).reshape(outputShape);

          final stopwatch = Stopwatch()..start();
          interpreter!.run(inputBuffer, output);
          stopwatch.stop();

          if (config.modelType == YoloModelType.pose4Points) {
            final candidates = YoloVisionService.parsePose4PointDetections(
              output: output,
              outputShape: outputShape,
              inputWidth: inputW,
              inputHeight: inputH,
              confThreshold: message.confThreshold,
              labels: config.labels,
              numKeypoints: config.numKeypoints,
              keypointDim: config.keypointDim,
            );

            final selected = YoloVisionService.applyOrientedNms(
              candidates,
              iouThreshold: message.iouThreshold,
              isNmsFree: config.isNmsFree,
            );

            final result = YoloVisionService.buildAnnotatedResult(
              originalImage: originalImage,
              inputWidth: inputW,
              inputHeight: inputH,
              orientedBoxes: selected,
              generateAnnotatedImage: message.generateAnnotatedImage,
            );

            message.replyPort.send(result);
          } else {
            final candidates = YoloVisionService.parseStandardDetections(
              output: output,
              outputShape: outputShape,
              inputWidth: inputW,
              inputHeight: inputH,
              confThreshold: message.confThreshold,
              labels: config.labels,
            );

            final selected = YoloVisionService.applyNms(
              candidates,
              iouThreshold: message.iouThreshold,
              isNmsFree: config.isNmsFree,
            );

            final result = YoloVisionService.buildAnnotatedResult(
              originalImage: originalImage,
              inputWidth: inputW,
              inputHeight: inputH,
              standardBoxes: selected,
              generateAnnotatedImage: message.generateAnnotatedImage,
            );

            message.replyPort.send(result);
          }
        } catch (e) {
          debugPrint('[YoloWorkerIsolate] predictFile error: $e');
          message.replyPort.send(null);
        }
        return;
      }

      // 5. Clean disposal
      if (message is YoloDisposeCommand) {
        interpreter?.close();
        interpreter = null;
        currentConfig = null;
        isolateReceivePort.close();
        return;
      }
    });
  }
}
