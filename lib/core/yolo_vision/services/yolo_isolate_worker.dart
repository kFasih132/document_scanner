import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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
    String? cacheDirectoryPath,
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
          cacheDirectoryPath: cacheDirectoryPath,
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
    List<List<List<double>>>? cachedOutput;
    bool isSwitchingModel = false;

    // Reusable buffer caches outside message loop to eliminate allocations across frames
    Float32List? reusableFloatBuffer;
    Int8List? reusableInt8Buffer;
    Uint8List? reusableUint8Buffer;

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

        isSwitchingModel = true;
        currentConfig = null;
        cachedOutput = null;
        final oldInterpreter = interpreter;
        interpreter = null;
        oldInterpreter?.close();
        bool success = false;
        try {
          final threadCount = Platform.numberOfProcessors.clamp(2, 6);
          final preferredDelegate = message.config.delegate;
          String activeDelegate = 'CPU ($threadCount threads)';

          // Probe model metadata first to identify quantization and tensor layout
          TensorType? detectedInputType;
          TensorType? detectedOutputType;
          List<int>? detectedInputShape;
          List<int>? detectedOutputShape;
          int inputTensorCount = 1;
          int outputTensorCount = 1;

          try {
            final probeOptions = InterpreterOptions()..threads = threadCount;
            final probe = Interpreter.fromBuffer(
              message.modelBytes,
              options: probeOptions,
            );
            final inTensors = probe.getInputTensors();
            final outTensors = probe.getOutputTensors();
            inputTensorCount = inTensors.length;
            outputTensorCount = outTensors.length;
            if (inTensors.isNotEmpty) {
              detectedInputType = inTensors[0].type;
              detectedInputShape = inTensors[0].shape;
            }
            if (outTensors.isNotEmpty) {
              detectedOutputType = outTensors[0].type;
              detectedOutputShape = outTensors[0].shape;
            }
            probe.close();
          } catch (e) {
            dev.log('⚠️ [YOLO Worker] Model probe error: $e', name: 'YOLO');
          }

          final isQuantized = detectedInputType == TensorType.int8 ||
              detectedInputType == TensorType.uint8 ||
              detectedOutputType == TensorType.int8 ||
              detectedOutputType == TensorType.uint8;

          dev.log(
            '🔍 [YOLO Worker] Probed model: inputs=$inputTensorCount ($detectedInputShape, $detectedInputType), '
            'outputs=$outputTensorCount ($detectedOutputShape, $detectedOutputType), isQuantized=$isQuantized',
            name: 'YOLO',
          );

          // Verification helper to ensure candidate interpreter can allocate and execute
          // without "Input tensor X lacks data" or delegate subgraph partitioning issues
          bool testInterpreter(Interpreter interp) {
            try {
              interp.allocateTensors();
              final inTensors = interp.getInputTensors();
              for (final t in inTensors) {
                final size = t.numBytes();
                if (size > 0) {
                  t.setTo(Uint8List(size));
                }
              }
              interp.invoke();
              return true;
            } catch (e) {
              dev.log('⚠️ [YOLO Worker] Delegate test failed: $e', name: 'YOLO');
              return false;
            }
          }

          // 1. Try GPU delegate ONLY if model is NOT INT8/UINT8 quantized
          // (TFLite GPU Delegate V2 does not support 8-bit quantized integer ops)
          if ((preferredDelegate == YoloHardwareDelegate.gpu ||
              (preferredDelegate == YoloHardwareDelegate.auto && !isQuantized))) {
            try {
              final gpuOptions = InterpreterOptions()..threads = threadCount;
              if (Platform.isAndroid) {
                gpuOptions.addDelegate(GpuDelegateV2());
              } else if (Platform.isIOS) {
                gpuOptions.addDelegate(GpuDelegate());
              }
              final candidate = Interpreter.fromBuffer(
                message.modelBytes,
                options: gpuOptions,
              );
              if (testInterpreter(candidate)) {
                interpreter = candidate;
                activeDelegate = Platform.isAndroid
                    ? 'Android GPU Delegate (V2)'
                    : 'iOS Metal GPU Delegate';
              } else {
                candidate.close();
                interpreter = null;
              }
            } catch (e) {
              dev.log('⚠️ [YOLO Worker] GPU delegate init error: $e', name: 'YOLO');
              interpreter = null;
            }
          }

          // 2. Try Android NNAPI if requested or auto on quantized models
          if (interpreter == null &&
              (preferredDelegate == YoloHardwareDelegate.nnapi ||
                  preferredDelegate == YoloHardwareDelegate.auto) &&
              Platform.isAndroid) {
            try {
              final nnapiOptions = InterpreterOptions()
                ..threads = threadCount
                ..useNnApiForAndroid = true;
              final candidate = Interpreter.fromBuffer(
                message.modelBytes,
                options: nnapiOptions,
              );
              if (testInterpreter(candidate)) {
                interpreter = candidate;
                activeDelegate = 'Android NNAPI / NPU Delegate';
              } else {
                candidate.close();
                interpreter = null;
              }
            } catch (e) {
              dev.log('⚠️ [YOLO Worker] NNAPI delegate init error: $e', name: 'YOLO');
              interpreter = null;
            }
          }

          // 3. Fallback to optimized multi-threaded CPU (XNNPACK)
          if (interpreter == null) {
            final cpuOptions = InterpreterOptions()..threads = threadCount;
            activeDelegate = 'CPU ($threadCount threads with XNNPACK)';
            interpreter = Interpreter.fromBuffer(
              message.modelBytes,
              options: cpuOptions,
            );
            interpreter!.allocateTensors();
          }

          final inTensors = interpreter!.getInputTensors();
          final outTensors = interpreter!.getOutputTensors();
          dev.log('🔍 [YOLO Worker] Input tensors count: ${inTensors.length}', name: 'YOLO');
          for (int i = 0; i < inTensors.length; i++) {
            final t = inTensors[i];
            dev.log(
              '🔍 [YOLO Worker] Input[$i]: name="${t.name}", shape=${t.shape}, type=${t.type}, bytes=${t.numBytes()}, scale=${t.params.scale}, zp=${t.params.zeroPoint}',
              name: 'YOLO',
            );
          }
          dev.log('🔍 [YOLO Worker] Output tensors count: ${outTensors.length}', name: 'YOLO');
          for (int i = 0; i < outTensors.length; i++) {
            final t = outTensors[i];
            dev.log(
              '🔍 [YOLO Worker] Output[$i]: name="${t.name}", shape=${t.shape}, type=${t.type}, bytes=${t.numBytes()}',
              name: 'YOLO',
            );
          }

          final inTensor = interpreter!.getInputTensor(0);
          final outTensor = interpreter!.getOutputTensor(0);
          final inType = inTensor.type;
          final outType = outTensor.type;
          final outputShape = outTensor.shape;

          // Pre-allocate cached output 3D array once to eliminate all runtime allocations
          if (outputShape.length == 3) {
            final d0 = outputShape[0];
            final d1 = outputShape[1];
            final d2 = outputShape[2];
            cachedOutput = List.generate(
              d0,
              (_) => List.generate(
                d1,
                (_) => List.filled(d2, 0.0),
              ),
            );
          }

          dev.log(
            '🚀 [YOLO Worker] Ready | Delegate: $activeDelegate | '
            'Input: ${inTensor.shape} ($inType, scale=${inTensor.params.scale}, zp=${inTensor.params.zeroPoint}) | '
            'Output: ${outTensor.shape} ($outType, scale=${outTensor.params.scale}, zp=${outTensor.params.zeroPoint})',
            name: 'YOLO',
          );

          currentConfig = message.config;
          success = true;
        } catch (e) {
          debugPrint('[YoloWorkerIsolate] Interpreter.fromBuffer error: $e');
          interpreter?.close();
          interpreter = null;
          currentConfig = null;
        } finally {
          isSwitchingModel = false;
        }
        message.replyPort.send(success);
        return;
      }

      // 3. Live camera frame inference
      if (message is YoloFrameCommand) {
        if (isSwitchingModel || interpreter == null || currentConfig == null) {
          message.replyPort.send(YoloDetectionResult.empty());
          return;
        }

        try {
          final config = currentConfig!;
          final inTensor = interpreter!.getInputTensor(0);
          final inputShape = inTensor.shape;
          final inputType = inTensor.type;
          final isNCHW = inputShape.length == 4 && inputShape[1] == 3;
          final targetH = isNCHW
              ? inputShape[2]
              : (inputShape.length == 4 ? inputShape[1] : config.inputHeight);
          final targetW = isNCHW
              ? inputShape[3]
              : (inputShape.length == 4 ? inputShape[2] : config.inputWidth);

          // Fast Laplacian variance calculation on Y-plane (sharpness / motion blur check)
          final sharpnessScore = FastTensorConverter.computeLaplacianVariance(
            yPlaneBytes: message.yPlaneBytes,
            srcW: message.width,
            srcH: message.height,
            yRowStride: message.yRowStride,
          );

          final inputScale = config.inputScale ??
              (inTensor.params.scale > 0 ? inTensor.params.scale : 1.0 / 255.0);
          final inputZeroPoint = config.inputZeroPoint ?? inTensor.params.zeroPoint;

          final Uint8List rawInputBytes;

          if (inputType == TensorType.int8) {
            final buf = FastTensorConverter.frameToInt8Buffer(
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
              rotationDegrees: message.rotationDegrees,
              scale: inputScale,
              zeroPoint: inputZeroPoint,
              reusableBuffer: reusableInt8Buffer,
            );
            reusableInt8Buffer = buf;
            rawInputBytes = buf.buffer.asUint8List();
          } else if (inputType == TensorType.uint8) {
            final buf = FastTensorConverter.frameToUint8Buffer(
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
              rotationDegrees: message.rotationDegrees,
              scale: inputScale,
              zeroPoint: inputZeroPoint,
              reusableBuffer: reusableUint8Buffer,
            );
            reusableUint8Buffer = buf;
            rawInputBytes = buf;
          } else {
            // Standard Float32
            final buf = FastTensorConverter.frameToFloat32Buffer(
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
              rotationDegrees: message.rotationDegrees,
              reusableBuffer: reusableFloatBuffer,
            );
            reusableFloatBuffer = buf;
            rawInputBytes = buf.buffer.asUint8List();
          }

          // Feed input tensor buffer properly via TfLiteTensorCopyFromBuffer
          inTensor.setTo(rawInputBytes);

          // Ensure any secondary input tensors are populated if present
          final allInputs = interpreter!.getInputTensors();
          if (allInputs.length > 1) {
            for (int i = 1; i < allInputs.length; i++) {
              final sec = allInputs[i];
              sec.setTo(Uint8List(sec.numBytes()));
            }
          }

          final stopwatch = Stopwatch()..start();
          interpreter!.invoke();
          stopwatch.stop();

          final outTensor = interpreter!.getOutputTensor(0);
          final outputShape = outTensor.shape;
          final outType = outTensor.type;
          final d0 = outputShape[0];
          final d1 = outputShape[1];
          final d2 = outputShape[2];

          final outScale = outTensor.params.scale > 0 ? outTensor.params.scale : 1.0;
          final outZeroPoint = outTensor.params.zeroPoint;

          if (cachedOutput == null ||
              cachedOutput!.length != d0 ||
              cachedOutput![0].length != d1 ||
              cachedOutput![0][0].length != d2) {
            cachedOutput = List.generate(
              d0,
              (_) => List.generate(d1, (_) => List.filled(d2, 0.0)),
            );
          }

          if (outType == TensorType.int8) {
            final flatInt8 = outTensor.data.buffer.asInt8List();
            for (int j = 0; j < d1; j++) {
              final row = cachedOutput![0][j];
              final rowOffset = j * d2;
              for (int k = 0; k < d2; k++) {
                row[k] = ((flatInt8[rowOffset + k] - outZeroPoint) * outScale);
              }
            }
          } else if (outType == TensorType.uint8) {
            final flatUint8 = outTensor.data;
            for (int j = 0; j < d1; j++) {
              final row = cachedOutput![0][j];
              final rowOffset = j * d2;
              for (int k = 0; k < d2; k++) {
                row[k] = ((flatUint8[rowOffset + k] - outZeroPoint) * outScale);
              }
            }
          } else {
            final flatFloat = outTensor.data.buffer.asFloat32List();
            for (int j = 0; j < d1; j++) {
              final row = cachedOutput![0][j];
              final rowOffset = j * d2;
              for (int k = 0; k < d2; k++) {
                row[k] = flatFloat[rowOffset + k];
              }
            }
          }

          final dynamic output = cachedOutput;

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
              '⚡ [YOLO Worker] Pose: ${stopwatch.elapsedMilliseconds}ms | '
              'sharpness=${sharpnessScore.toStringAsFixed(1)} | '
              'cands=${candidates.length} | selected=${selected.length}',
              name: 'YOLO',
            );

            // The tensor was already sampled in upright camera orientation.
            // Normalize coordinates to [0.0 - 1.0] in upright space.
            final normalized = selected
                .map(
                  (b) => b.toNormalized(targetW.toDouble(), targetH.toDouble()),
                )
                .toList();

            // Cache the exact frame on which the model made its prediction
            String? cachedPath;
            if (selected.isNotEmpty && message.cacheDirectoryPath != null) {
              try {
                final jpegBytes = FastTensorConverter.frameToUprightJpeg(
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
                  rotationDegrees: message.rotationDegrees,
                );
                if (jpegBytes != null) {
                  final dir = Directory(message.cacheDirectoryPath!);
                  if (!dir.existsSync()) dir.createSync(recursive: true);
                  final file = File('${dir.path}/cached_detected_frame.jpg');
                  file.writeAsBytesSync(jpegBytes);
                  cachedPath = file.path;
                }
              } catch (e) {
                dev.log('⚠️ [YOLO Worker] Frame cache error: $e', name: 'YOLO');
              }
            }

            message.replyPort.send(
              YoloDetectionResult(
                orientedBoxes: normalized,
                inferenceTimeMs: stopwatch.elapsedMilliseconds,
                sharpnessScore: sharpnessScore,
                cachedImagePath: cachedPath,
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
                sharpnessScore: sharpnessScore,
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
        if (isSwitchingModel || interpreter == null || currentConfig == null) {
          message.replyPort.send(null);
          return;
        }

        try {
          final config = currentConfig!;
          final bytes = await File(message.imagePath).readAsBytes();
          img.Image? decoded = img.decodeImage(bytes);
          if (decoded == null) {
            message.replyPort.send(null);
            return;
          }
          final originalImage = img.bakeOrientation(decoded);

          final inTensor = interpreter!.getInputTensor(0);
          final inType = inTensor.type;
          final inputShape = inTensor.shape;
          final (
            inputBuffer,
            inputW,
            inputH,
          ) = YoloVisionService.prepareImageInput(
            original: originalImage,
            inputShape: inputShape,
          );

          final outTensor = interpreter!.getOutputTensor(0);
          final outputShape = outTensor.shape;
          final outType = outTensor.type;

          final stopwatch = Stopwatch()..start();

          if (inType == TensorType.int8 || inType == TensorType.uint8) {
            final isNCHW = inputShape.length == 4 && inputShape[1] == 3;
            final inScale = config.inputScale ??
                (inTensor.params.scale > 0 ? inTensor.params.scale : 1.0 / 255.0);
            final inZeroPoint = config.inputZeroPoint ?? inTensor.params.zeroPoint;

            final totalInputBytes = inputW * inputH * 3;
            final flatBytes = Uint8List(totalInputBytes);
            final resized = img.copyResize(originalImage, width: inputW, height: inputH);
            final channelSize = inputW * inputH;

            for (int y = 0; y < inputH; y++) {
              final yRow = y * inputW;
              for (int x = 0; x < inputW; x++) {
                final p = resized.getPixel(x, y);
                final rVal = inType == TensorType.int8
                    ? ((p.r / 255.0) / inScale + inZeroPoint).round().clamp(-128, 127)
                    : ((p.r / 255.0) / inScale + inZeroPoint).round().clamp(0, 255);
                final gVal = inType == TensorType.int8
                    ? ((p.g / 255.0) / inScale + inZeroPoint).round().clamp(-128, 127)
                    : ((p.g / 255.0) / inScale + inZeroPoint).round().clamp(0, 255);
                final bVal = inType == TensorType.int8
                    ? ((p.b / 255.0) / inScale + inZeroPoint).round().clamp(-128, 127)
                    : ((p.b / 255.0) / inScale + inZeroPoint).round().clamp(0, 255);

                if (isNCHW) {
                  final idx = yRow + x;
                  flatBytes[idx] = rVal & 0xFF;
                  flatBytes[channelSize + idx] = gVal & 0xFF;
                  flatBytes[(channelSize * 2) + idx] = bVal & 0xFF;
                } else {
                  final idx = (yRow + x) * 3;
                  flatBytes[idx] = rVal & 0xFF;
                  flatBytes[idx + 1] = gVal & 0xFF;
                  flatBytes[idx + 2] = bVal & 0xFF;
                }
              }
            }
            inTensor.setTo(flatBytes);
            interpreter!.invoke();
          } else {
            inTensor.setTo(inputBuffer);
            interpreter!.invoke();
          }
          stopwatch.stop();

          final d0 = outputShape[0];
          final d1 = outputShape[1];
          final d2 = outputShape[2];
          final outScale = outTensor.params.scale > 0 ? outTensor.params.scale : 1.0;
          final outZeroPoint = outTensor.params.zeroPoint;

          final fileOutput = List.generate(
            d0,
            (_) => List.generate(d1, (_) => List.filled(d2, 0.0)),
          );

          if (outType == TensorType.int8) {
            final flatInt8 = outTensor.data.buffer.asInt8List();
            for (int j = 0; j < d1; j++) {
              final row = fileOutput[0][j];
              final rowOffset = j * d2;
              for (int k = 0; k < d2; k++) {
                row[k] = ((flatInt8[rowOffset + k] - outZeroPoint) * outScale);
              }
            }
          } else if (outType == TensorType.uint8) {
            final flatUint8 = outTensor.data;
            for (int j = 0; j < d1; j++) {
              final row = fileOutput[0][j];
              final rowOffset = j * d2;
              for (int k = 0; k < d2; k++) {
                row[k] = ((flatUint8[rowOffset + k] - outZeroPoint) * outScale);
              }
            }
          } else {
            final flatFloat = outTensor.data.buffer.asFloat32List();
            for (int j = 0; j < d1; j++) {
              final row = fileOutput[0][j];
              final rowOffset = j * d2;
              for (int k = 0; k < d2; k++) {
                row[k] = flatFloat[rowOffset + k];
              }
            }
          }

          final output = fileOutput;

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

            final normalized = selected
                .map(
                  (b) => b.toNormalized(inputW.toDouble(), inputH.toDouble()),
                )
                .toList();

            final result = YoloVisionService.buildAnnotatedResult(
              originalImage: originalImage,
              inputWidth: inputW,
              inputHeight: inputH,
              orientedBoxes: selected,
              generateAnnotatedImage: message.generateAnnotatedImage,
            );

            message.replyPort.send(
              YoloDetectionResult(
                boxes: result.boxes,
                orientedBoxes: normalized,
                crops: result.crops,
                annotatedImageBytes: result.annotatedImageBytes,
                inferenceTimeMs: stopwatch.elapsedMilliseconds,
                sharpnessScore: 0.0,
              ),
            );
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

            final normalized = selected
                .map(
                  (b) => b.toNormalized(inputW.toDouble(), inputH.toDouble()),
                )
                .toList();

            final result = YoloVisionService.buildAnnotatedResult(
              originalImage: originalImage,
              inputWidth: inputW,
              inputHeight: inputH,
              standardBoxes: selected,
              generateAnnotatedImage: message.generateAnnotatedImage,
            );

            message.replyPort.send(
              YoloDetectionResult(
                boxes: normalized,
                orientedBoxes: result.orientedBoxes,
                crops: result.crops,
                annotatedImageBytes: result.annotatedImageBytes,
                inferenceTimeMs: stopwatch.elapsedMilliseconds,
                sharpnessScore: 0.0,
              ),
            );
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
