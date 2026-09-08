import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/yolo_vision/models/yolo_model_config.dart';
import '../../../../core/yolo_vision/models/yolo_model_type.dart';
import '../../../../core/yolo_vision/services/auto_capture_decision_engine.dart';
import '../../../../core/yolo_vision/services/temporal_corner_smoother.dart';
import '../../../../core/yolo_vision/services/yolo_isolate_worker.dart';
import '../../domain/models/scanned_document.dart';
import '../../domain/services/document_post_processing_service.dart';
import '../../domain/services/image_crop_service.dart';
import '../../domain/services/local_document_storage_service.dart';
import '../../domain/services/pdf_export_service.dart';
import 'scanner_event.dart';
import 'scanner_state.dart';

class ScannerBloc extends Bloc<ScannerEvent, ScannerState> {
  final LocalDocumentStorageService _storageService;
  final PdfExportService _pdfExportService;
  final ImageCropService _cropService;
  final DocumentPostProcessingService _postProcessingService;

  final YoloIsolateWorker _yoloWorker = YoloIsolateWorker();
  final TemporalCornerSmoother _cornerSmoother = TemporalCornerSmoother();
  final AutoCaptureDecisionEngine _autoCaptureEngine =
      AutoCaptureDecisionEngine();

  bool _isWorkerInitialized = false;
  bool _isModelLoaded = false;
  bool _isDisposingCamera = false;
  bool _isInitializingCamera = false;
  bool _isProcessingFrame = false;
  bool _isCameraActive = false;
  int _cameraSessionId = 0;
  int _missedDetectionCount = 0;
  double _lastSharpnessScore = 0.0;
  bool _isCurrentInstanceCaptured = false;
  List<CropQuadCorners> _lastCapturedCornersList = [];
  String? _cacheDirectoryPath;
  String? _lastCachedFramePath;
  CropQuadCorners? _lastCachedCorners;
  List<CropQuadCorners> _lastCachedCornersList = [];

  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];

  CameraController? get cameraController => _cameraController;
  bool get isCameraActive => _isCameraActive;
  DocumentPostProcessingService get postProcessingService =>
      _postProcessingService;

  ScannerBloc({
    LocalDocumentStorageService? storageService,
    PdfExportService? pdfExportService,
    ImageCropService? cropService,
    DocumentPostProcessingService? postProcessingService,
  }) : _storageService = storageService ?? LocalDocumentStorageService(),
       _postProcessingService =
           postProcessingService ?? DocumentPostProcessingService(),
       _pdfExportService =
           pdfExportService ??
           PdfExportService(postProcessingService: postProcessingService),
       _cropService = cropService ?? ImageCropService(),
       super(const ScannerState()) {
    on<LoadSavedDocumentsEvent>(_onLoadSavedDocuments);
    on<InitializeCameraEvent>(_onInitializeCamera);
    on<DisposeCameraEvent>(_onDisposeCamera);
    on<OpenDocumentForEditingEvent>(_onOpenDocumentForEditing);
    on<SwitchScanModeEvent>(_onSwitchScanMode);
    on<ToggleFlashEvent>(_onToggleFlash);
    on<ToggleAutoCaptureEvent>(_onToggleAutoCapture);
    on<CapturePageEvent>(_onCapturePage);
    on<SelectPageForEditingEvent>(_onSelectPageForEditing);
    on<UpdateCropCornerEvent>(_onUpdateCropCorner);
    on<ApplyCropEvent>(_onApplyCrop);
    on<ApplyFilterEvent>(_onApplyFilter);
    on<RotatePageEvent>(_onRotatePage);
    on<DeletePageEvent>(_onDeletePage);
    on<SaveDocumentEvent>(_onSaveDocument);
    on<SharePdfEvent>(_onSharePdf);
    on<ExportPdfEvent>(_onExportPdf);
    on<DeleteDocumentEvent>(_onDeleteDocument);
    on<ResetScannerEvent>(_onResetScanner);
    on<LiveCornersDetectedEvent>(_onLiveCornersDetected);
    on<ClearLiveCornersEvent>(_onClearLiveCorners);
    on<SwitchScannerModelEvent>(_onSwitchScannerModel);
    on<UpdateScannerConfigEvent>(_onUpdateScannerConfig);
    on<ResetScannerConfigEvent>(_onResetScannerConfig);
  }

  Future<void> _onInitializeCamera(
    InitializeCameraEvent event,
    Emitter<ScannerState> emit,
  ) async {
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;

    // Wait if another thread or screen transition is currently disposing the camera
    while (_isDisposingCamera) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _cameraSessionId++;
    final int sessionToken = _cameraSessionId;
    _isCameraActive = true;
    _isProcessingFrame = false;

    // Reset instance-based capture lockout
    _isCurrentInstanceCaptured = false;
    _lastCapturedCornersList = [];

    // If camera controller is already initialized and valid, reuse it smoothly
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        _cacheDirectoryPath = '${appDir.path}/doc_scanner_storage/cache';
        final dir = Directory(_cacheDirectoryPath!);
        if (!dir.existsSync()) dir.createSync(recursive: true);
      } catch (_) {}
      emit(
        state.copyWith(
          status: ScannerStatus.cameraReady,
          isCameraInitialized: true,
          statusMessage: 'Align document within borders',
        ),
      );
      await _startImageStreamIfNeeded();
      _isInitializingCamera = false;
      return;
    }

    emit(
      state.copyWith(
        status: ScannerStatus.loading,
        isCameraInitialized: false,
        statusMessage: 'Initializing camera...',
      ),
    );

    // Safely release any lingering or unclosed controller first to avoid native hardware lockup
    if (_cameraController != null) {
      try {
        final oldController = _cameraController;
        _cameraController = null;
        if (oldController != null && oldController.value.isStreamingImages) {
          try {
            await oldController.stopImageStream();
          } catch (_) {}
        }
        await oldController?.dispose();
      } catch (e) {
        debugPrint('Error disposing prior camera controller: $e');
      }
      _cameraController = null;
    }

    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isNotEmpty) {
        final backCamera = _availableCameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => _availableCameras.first,
        );

        final newController = CameraController(
          backCamera,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid
              ? ImageFormatGroup.yuv420
              : ImageFormatGroup.bgra8888,
        );

        _cameraController = newController;
        await newController.initialize();

        // Check if camera was disposed while awaiting initialization
        if (!_isCameraActive || _cameraSessionId != sessionToken) {
          try {
            await newController.dispose();
          } catch (_) {}
          _cameraController = null;
          return;
        }

        // Ensure flash is off upon clean init
        try {
          await newController.setFlashMode(FlashMode.off);
        } catch (_) {}

        // Ensure cache directory exists for live frame caching
        try {
          final appDir = await getApplicationDocumentsDirectory();
          _cacheDirectoryPath = '${appDir.path}/doc_scanner_storage/cache';
          final dir = Directory(_cacheDirectoryPath!);
          if (!dir.existsSync()) dir.createSync(recursive: true);
        } catch (_) {}

        emit(
          state.copyWith(
            status: ScannerStatus.cameraReady,
            isCameraInitialized: true,
            isFlashOn: false,
            statusMessage: 'Align document within borders',
          ),
        );

        // Initialize YOLO isolate worker and load model
        await _initYoloModel(emit);

        // Start real-time image stream for auto-detection
        await _startImageStreamIfNeeded();
      } else {
        // Fallback for emulator / desktop environments without physical camera
        emit(
          state.copyWith(
            status: ScannerStatus.cameraReady,
            isCameraInitialized: false,
            statusMessage: 'Hardware camera simulated',
          ),
        );
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      _cameraController = null;
      emit(
        state.copyWith(
          status: ScannerStatus.cameraReady,
          isCameraInitialized: false,
          statusMessage: 'Camera simulated (Hardware: $e)',
        ),
      );
    } finally {
      _isInitializingCamera = false;
    }
  }

  Future<bool> _loadYoloModelInIsolate({
    required ScannerModelOption modelOption,
    required YoloHardwareDelegate delegate,
    required Emitter<ScannerState> emit,
  }) async {
    _isModelLoaded = false;
    try {
      if (!_isWorkerInitialized) {
        _isWorkerInitialized = await _yoloWorker.initialize();
      }
      if (!_isWorkerInitialized) return false;

      final config = YoloModelConfig(
        modelId: modelOption.id,
        assetPath: modelOption.assetPath,
        labels: const ['document'],
        modelType: YoloModelType.pose4Points,
        delegate: delegate,
        inputWidth: 768,
        inputHeight: 768,
        isNmsFree: false,
      );

      final loaded = await _yoloWorker.loadModel(config);
      if (loaded) {
        _isModelLoaded = true;
        emit(
          state.copyWith(
            activeModel: modelOption,
            hardwareDelegate: delegate,
            isModelLoaded: true,
            statusMessage:
                '${modelOption.title} (${delegate.name.toUpperCase()}) loaded',
          ),
        );
        debugPrint(
          '[ScannerBloc] ${modelOption.title} (${modelOption.assetPath}) with ${delegate.name} loaded successfully in isolate',
        );
        return true;
      } else {
        emit(
          state.copyWith(statusMessage: 'Failed to load ${modelOption.title}'),
        );
        return false;
      }
    } catch (e) {
      debugPrint('[ScannerBloc] _loadYoloModelInIsolate error: $e');
      emit(state.copyWith(statusMessage: 'Error loading ${modelOption.title}'));
      return false;
    }
  }

  Future<void> _initYoloModel(Emitter<ScannerState> emit) async {
    if (_isModelLoaded) return;
    await _loadYoloModelInIsolate(
      modelOption: state.activeModel,
      delegate: state.hardwareDelegate,
      emit: emit,
    );
  }

  Future<void> _onSwitchScannerModel(
    SwitchScannerModelEvent event,
    Emitter<ScannerState> emit,
  ) async {
    if (state.activeModel == event.model && _isModelLoaded) return;

    emit(
      state.copyWith(
        activeModel: event.model,
        isModelLoaded: false,
        statusMessage: 'Loading ${event.model.title}...',
      ),
    );

    await _loadYoloModelInIsolate(
      modelOption: event.model,
      delegate: state.hardwareDelegate,
      emit: emit,
    );
  }

  Future<void> _onUpdateScannerConfig(
    UpdateScannerConfigEvent event,
    Emitter<ScannerState> emit,
  ) async {
    final newConf = event.confThreshold ?? state.confThreshold;
    final newIou = event.iouThreshold ?? state.iouThreshold;
    final newDelegate = event.hardwareDelegate ?? state.hardwareDelegate;
    final newModel = event.model ?? state.activeModel;

    final delegateChanged = newDelegate != state.hardwareDelegate;
    final modelChanged = newModel != state.activeModel;

    emit(
      state.copyWith(
        confThreshold: newConf,
        iouThreshold: newIou,
        hardwareDelegate: newDelegate,
        activeModel: newModel,
      ),
    );

    if (delegateChanged || modelChanged) {
      emit(
        state.copyWith(
          isModelLoaded: false,
          statusMessage: 'Applying settings & reloading model...',
        ),
      );
      await _loadYoloModelInIsolate(
        modelOption: newModel,
        delegate: newDelegate,
        emit: emit,
      );
    }
  }

  Future<void> _onResetScannerConfig(
    ResetScannerConfigEvent event,
    Emitter<ScannerState> emit,
  ) async {
    const defaultConf = 0.25;
    const defaultIou = 0.45;
    const defaultDelegate = YoloHardwareDelegate.cpu;
    const defaultModel = ScannerModelOption.v1Fp32;

    final delegateChanged = state.hardwareDelegate != defaultDelegate;
    final modelChanged = state.activeModel != defaultModel;

    emit(
      state.copyWith(
        confThreshold: defaultConf,
        iouThreshold: defaultIou,
        hardwareDelegate: defaultDelegate,
        activeModel: defaultModel,
      ),
    );

    if (delegateChanged || modelChanged) {
      emit(
        state.copyWith(
          isModelLoaded: false,
          statusMessage: 'Resetting model to V1 FP32 CPU...',
        ),
      );
      await _loadYoloModelInIsolate(
        modelOption: defaultModel,
        delegate: defaultDelegate,
        emit: emit,
      );
    }
  }

  Future<void> _startImageStreamIfNeeded() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_isCameraActive ||
        _isDisposingCamera) {
      return;
    }
    if (_cameraController!.value.isStreamingImages) {
      return;
    }

    final int sessionToken = _cameraSessionId;

    try {
      await _cameraController!.startImageStream((CameraImage image) {
        if (!_isCameraActive ||
            _isDisposingCamera ||
            _cameraSessionId != sessionToken ||
            _cameraController == null ||
            !_cameraController!.value.isInitialized) {
          return;
        }

        // Run ML whenever worker isolate is ready (continuous ~15-20 FPS)
        if (_isProcessingFrame ||
            !_isModelLoaded ||
            !_isCameraActive ||
            _cameraSessionId != sessionToken) {
          return;
        }

        final rotationDegrees =
            _cameraController?.description.sensorOrientation ?? 90;

        final isYuv =
            image.format.group == ImageFormatGroup.yuv420 ||
            image.format.group == ImageFormatGroup.nv21;
        final yPlane = image.planes[0].bytes;
        final width = image.width;
        final height = image.height;
        final yRowStride = image.planes[0].bytesPerRow;

        final uPlane = image.planes.length > 1 ? image.planes[1].bytes : null;
        final vPlane = image.planes.length > 2 ? image.planes[2].bytes : null;
        final bgra = !isYuv && image.planes.isNotEmpty
            ? image.planes[0].bytes
            : null;
        final uvRowStride = image.planes.length > 1
            ? image.planes[1].bytesPerRow
            : 0;
        final uvPixelStride = image.planes.length > 1
            ? (image.planes[1].bytesPerPixel ?? 1)
            : 1;

        _isProcessingFrame = true;

        _runPeriodicMlInference(
          sessionToken: sessionToken,
          yPlane: yPlane,
          uPlane: uPlane,
          vPlane: vPlane,
          bgra: bgra,
          width: width,
          height: height,
          yRowStride: yRowStride,
          uvRowStride: uvRowStride,
          uvPixelStride: uvPixelStride,
          isYuv: isYuv,
          rotationDegrees: rotationDegrees,
        ).whenComplete(() {
          _isProcessingFrame = false;
        });
      });
    } catch (e) {
      debugPrint('[ScannerBloc] startImageStream error: $e');
    }
  }

  Future<void> _runPeriodicMlInference({
    required int sessionToken,
    required Uint8List yPlane,
    Uint8List? uPlane,
    Uint8List? vPlane,
    Uint8List? bgra,
    required int width,
    required int height,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required bool isYuv,
    required int rotationDegrees,
  }) async {
    if (!_isModelLoaded ||
        !_isCameraActive ||
        _cameraSessionId != sessionToken ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final result = await _yoloWorker.processFrame(
        yPlaneBytes: yPlane,
        uPlaneBytes: uPlane,
        vPlaneBytes: vPlane,
        bgraBytes: bgra,
        width: width,
        height: height,
        yRowStride: yRowStride,
        uvRowStride: uvRowStride,
        uvPixelStride: uvPixelStride,
        isYuv: isYuv,
        confThreshold: state.confThreshold,
        iouThreshold: state.iouThreshold,
        rotationDegrees: rotationDegrees,
        cacheDirectoryPath: _cacheDirectoryPath,
      );

      // Verify camera and session are still active after async isolate execution
      if (!_isCameraActive ||
          _cameraSessionId != sessionToken ||
          _cameraController == null) {
        return;
      }

      if (result != null) {
        _lastSharpnessScore = result.sharpnessScore;
        if (result.cachedImagePath != null) {
          _lastCachedFramePath = result.cachedImagePath;
        }
      }

      final List<CropQuadCorners> rawCornersList = [];
      if (result != null && result.orientedBoxes.isNotEmpty) {
        for (final ob in result.orientedBoxes) {
          rawCornersList.add(
            CropQuadCorners.fromPoints([
              Offset(ob.p1.x, ob.p1.y),
              Offset(ob.p2.x, ob.p2.y),
              Offset(ob.p3.x, ob.p3.y),
              Offset(ob.p4.x, ob.p4.y),
            ]),
          );
        }
      } else if (result != null && result.boxes.isNotEmpty) {
        for (final b in result.boxes) {
          rawCornersList.add(
            CropQuadCorners(
              topLeft: Offset(b.x1, b.y1),
              topRight: Offset(b.x2, b.y1),
              bottomRight: Offset(b.x2, b.y2),
              bottomLeft: Offset(b.x1, b.y2),
            ),
          );
        }
      }

      // Suppress duplicate/overlapping predictions for the same document
      final List<CropQuadCorners> deduplicatedCornersList = [];
      for (final candidate in rawCornersList) {
        bool isDuplicate = false;
        for (final existing in deduplicatedCornersList) {
          final dist = (candidate.center - existing.center).distance;
          if (dist < 0.18) {
            isDuplicate = true;
            break;
          }
        }
        if (!isDuplicate) {
          deduplicatedCornersList.add(candidate);
        }
      }

      _lastCachedCornersList = deduplicatedCornersList;
      _lastCachedCorners =
          deduplicatedCornersList.isNotEmpty ? deduplicatedCornersList.first : null;

      if (!_isCameraActive || _cameraSessionId != sessionToken) {
        return;
      }

      if (deduplicatedCornersList.isNotEmpty) {
        _missedDetectionCount = 0;

        // Instance lockout check: has the document moved or was a new page placed?
        if (_isCurrentInstanceCaptured && _lastCapturedCornersList.isNotEmpty) {
          bool moved = false;
          if (_lastCapturedCornersList.length != deduplicatedCornersList.length) {
            moved = true;
          } else {
            for (int i = 0; i < deduplicatedCornersList.length; i++) {
              final shift = _computeMaxCornerDelta(
                _lastCapturedCornersList[i],
                deduplicatedCornersList[i],
              );
              if (shift > 0.28) {
                moved = true;
                break;
              }
            }
          }

          if (moved) {
            _isCurrentInstanceCaptured = false;
            _lastCapturedCornersList = [];
          } else {
            final smoothedList =
                _cornerSmoother.processMultiple(deduplicatedCornersList);
            final displayList =
                smoothedList.isNotEmpty ? smoothedList : deduplicatedCornersList;
            final count = displayList.length;
            add(
              LiveCornersDetectedEvent(
                corners: displayList.first,
                cornersList: displayList,
                isDocumentLocked: true,
                autoCaptureProgress: 1.0,
                sharpnessScore: _lastSharpnessScore,
                statusMessage: count > 1
                    ? '$count pages already captured • Move to next page'
                    : 'Page already captured • Move to next page',
              ),
            );
            return;
          }
        }

        if (!_isCurrentInstanceCaptured &&
            _isCameraActive &&
            _cameraSessionId == sessionToken) {
          final smoothedList =
              _cornerSmoother.processMultiple(deduplicatedCornersList);

          if (smoothedList.isNotEmpty) {
            _lastCachedCornersList = smoothedList;
            _lastCachedCorners = smoothedList.first;

            final evaluation = _autoCaptureEngine.evaluateMultiple(
              cornersList: smoothedList,
              sharpnessScore: _lastSharpnessScore,
              isAutoCaptureEnabled: state.isAutoCaptureEnabled,
            );

            if (evaluation.shouldCapture && !_isCurrentInstanceCaptured) {
              dev.log(
                '📸 [ScannerBloc] Auto-capture criteria met (${smoothedList.length} docs)! Snapping...',
                name: 'YOLO',
              );
              add(const CapturePageEvent());
            }

            add(
              LiveCornersDetectedEvent(
                corners: smoothedList.first,
                cornersList: smoothedList,
                isDocumentLocked: evaluation.isLocked,
                autoCaptureProgress: evaluation.lockProgress,
                sharpnessScore: _lastSharpnessScore,
                statusMessage: evaluation.statusReason,
              ),
            );
          }
        }
      } else {
        // No detection in this frame: pass empty list to smoother to apply temporal persistence
        final smoothedList = _cornerSmoother.processMultiple(const []);
        _missedDetectionCount++;

        if (smoothedList.isNotEmpty &&
            _isCameraActive &&
            _cameraSessionId == sessionToken) {
          add(
            LiveCornersDetectedEvent(
              corners: smoothedList.first,
              cornersList: smoothedList,
              isDocumentLocked: false,
              autoCaptureProgress: 0.0,
              sharpnessScore: _lastSharpnessScore,
              statusMessage: 'Align document within borders',
            ),
          );
        } else {
          if (_missedDetectionCount >= 2) {
            _isCurrentInstanceCaptured = false;
            _lastCapturedCornersList = [];
          }
          if (_missedDetectionCount >= 4 &&
              _isCameraActive &&
              _cameraSessionId == sessionToken) {
            _cornerSmoother.reset();
            _autoCaptureEngine.reset();
            add(const ClearLiveCornersEvent());
          }
        }
      }
    } catch (e) {
      debugPrint('[ScannerBloc] _runPeriodicMlInference error: $e');
    }
  }

  double _computeMaxCornerDelta(CropQuadCorners a, CropQuadCorners b) {
    final d1 = (a.topLeft - b.topLeft).distance;
    final d2 = (a.topRight - b.topRight).distance;
    final d3 = (a.bottomRight - b.bottomRight).distance;
    final d4 = (a.bottomLeft - b.bottomLeft).distance;
    return math.max(math.max(d1, d2), math.max(d3, d4));
  }

  void _onLiveCornersDetected(
    LiveCornersDetectedEvent event,
    Emitter<ScannerState> emit,
  ) {
    emit(
      state.copyWith(
        vision: state.vision.copyWith(
          liveDetectedCornersList: event.cornersList,
          liveDetectedCorners: event.corners,
          isDocumentLocked: event.isDocumentLocked,
          autoCaptureProgress: event.autoCaptureProgress,
          liveSharpnessScore: event.sharpnessScore,
        ),
        feedback: state.feedback.copyWith(
          statusMessage: event.statusMessage ??
              (event.isDocumentLocked ? 'Document locked' : 'Document detected'),
        ),
      ),
    );
  }

  void _onClearLiveCorners(
    ClearLiveCornersEvent event,
    Emitter<ScannerState> emit,
  ) {
    if (state.liveDetectedCornersList.isNotEmpty || state.isDocumentLocked) {
      _autoCaptureEngine.reset();
      _cornerSmoother.reset();
      // _visualTracker.reset();
      emit(
        state.copyWith(
          vision: const LiveVisionState(),
          feedback: state.feedback.copyWith(
            statusMessage: 'Align document within borders',
          ),
        ),
      );
    }
  }

  Future<void> _onDisposeCamera(
    DisposeCameraEvent event,
    Emitter<ScannerState> emit,
  ) async {
    _isDisposingCamera = true;
    _isCameraActive = false;
    _cameraSessionId++; // Invalidate all existing frame tasks and isolate callbacks immediately
    _isProcessingFrame = false;
    _isCurrentInstanceCaptured = false;
    _lastCapturedCornersList = [];
    // _visualTracker.reset();
    _cornerSmoother.reset();
    _autoCaptureEngine.reset();
    _missedDetectionCount = 0;

    try {
      if (_cameraController != null) {
        final controllerToDispose = _cameraController;
        _cameraController = null;
        if (controllerToDispose != null &&
            controllerToDispose.value.isStreamingImages) {
          try {
            await controllerToDispose.stopImageStream();
          } catch (e) {
            debugPrint('[ScannerBloc] stopImageStream error: $e');
          }
        }
        try {
          await controllerToDispose?.dispose();
        } catch (e) {
          debugPrint('[ScannerBloc] controller.dispose error: $e');
        }
      }
    } catch (e) {
      debugPrint('Camera disposal error: $e');
    } finally {
      _cameraController = null;
      _isDisposingCamera = false;
    }
    emit(
      state.copyWith(
        isCameraInitialized: false,
        isFlashOn: false,
        clearLiveCorners: true,
        isDocumentLocked: false,
        autoCaptureProgress: 0.0,
        liveSharpnessScore: 0.0,
        status: state.capturedPages.isNotEmpty
            ? ScannerStatus.previewReady
            : ScannerStatus.initial,
        statusMessage: 'Idle',
      ),
    );
  }

  void _onOpenDocumentForEditing(
    OpenDocumentForEditingEvent event,
    Emitter<ScannerState> emit,
  ) {
    emit(
      state.copyWith(
        capturedPages: List<ScannedPage>.from(event.document.pages),
        editingDocumentId: event.document.id,
        selectedPageIndex: event.document.pages.isNotEmpty
            ? event.document.pages.length - 1
            : 0,
        status: ScannerStatus.previewReady,
        statusMessage: 'Loaded ${event.document.title}',
      ),
    );
  }

  void _onSwitchScanMode(
    SwitchScanModeEvent event,
    Emitter<ScannerState> emit,
  ) {
    emit(
      state.copyWith(
        activeScanMode: event.mode,
        statusMessage: 'Mode switched to ${event.mode.label}',
      ),
    );
  }

  Future<void> _onToggleFlash(
    ToggleFlashEvent event,
    Emitter<ScannerState> emit,
  ) async {
    final nextFlash = !state.isFlashOn;
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _cameraController!.setFlashMode(
          nextFlash ? FlashMode.torch : FlashMode.off,
        );
      }
    } catch (e) {
      debugPrint('Flash toggle error: $e');
    }
    emit(state.copyWith(isFlashOn: nextFlash));
  }

  void _onToggleAutoCapture(
    ToggleAutoCaptureEvent event,
    Emitter<ScannerState> emit,
  ) {
    emit(state.copyWith(isAutoCaptureEnabled: !state.isAutoCaptureEnabled));
  }

  Future<void> _onCapturePage(
    CapturePageEvent event,
    Emitter<ScannerState> emit,
  ) async {
    emit(
      state.copyWith(
        status: ScannerStatus.capturing,
        isDocumentLocked: false,
        autoCaptureProgress: 0.0,
      ),
    );

    _autoCaptureEngine.reset();
    _cornerSmoother.reset();

    String capturedPath = '';
    CropQuadCorners? targetCorners;

    // 1. First priority: Use the cached frame that the model actually predicted on!
    // This gives zero shutter lag, identical field-of-view, and pixel-perfect corner alignment.
    if (_lastCachedFramePath != null &&
        File(_lastCachedFramePath!).existsSync() &&
        _lastCachedCorners != null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final rawDir = Directory('${appDir.path}/doc_scanner_storage/raw');
        if (!rawDir.existsSync()) rawDir.createSync(recursive: true);
        final uniquePath =
            '${rawDir.path}/raw_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(_lastCachedFramePath!).copy(uniquePath);
        capturedPath = uniquePath;
        targetCorners = _lastCachedCorners;
        dev.log(
          '🎯 [ScannerBloc] Zero-lag capture: Using model-predicted frame $capturedPath',
          name: 'YOLO',
        );
      } catch (e) {
        debugPrint('[ScannerBloc] Error copying cached frame: $e');
        capturedPath = _lastCachedFramePath!;
        targetCorners = _lastCachedCorners;
      }
    }

    // 2. Fallback: Hardware camera snapshot if no cached frame was available
    if (capturedPath.isEmpty) {
      try {
        if (_cameraController != null &&
            _cameraController!.value.isInitialized) {
          if (_cameraController!.value.isStreamingImages) {
            try {
              await _cameraController!.stopImageStream();
            } catch (_) {}
          }

          final XFile file = await _cameraController!.takePicture();
          capturedPath = file.path;
          targetCorners = state.liveDetectedCorners;
        }
      } catch (e) {
        debugPrint('Snapshot fallback error: $e');
      }
    }

    // High-Accuracy Multi-Object Auto-Crop:
    // Gather all target quads (from cached model detections or live state)
    final List<CropQuadCorners> targetCornersList = [];
    if (_lastCachedCornersList.isNotEmpty) {
      targetCornersList.addAll(_lastCachedCornersList);
    } else if (state.liveDetectedCornersList.isNotEmpty) {
      targetCornersList.addAll(state.liveDetectedCornersList);
    } else if (targetCorners != null) {
      targetCornersList.add(targetCorners);
    }

    final int basePageIndex = state.capturedPages.length;
    final List<ScannedPage> newPages = [];

    if (capturedPath.isNotEmpty && targetCornersList.isNotEmpty) {
      for (int i = 0; i < targetCornersList.length; i++) {
        final corners = targetCornersList[i];
        final pageIdx = basePageIndex + i;
        final cropped = await _cropService.cropImage(
          sourceImagePath: capturedPath,
          topLeft: corners.topLeft,
          topRight: corners.topRight,
          bottomRight: corners.bottomRight,
          bottomLeft: corners.bottomLeft,
        );

        newPages.add(
          ScannedPage(
            id: 'page_${DateTime.now().millisecondsSinceEpoch}_$pageIdx',
            imagePath: cropped ?? capturedPath,
            originalImagePath: capturedPath.isNotEmpty ? capturedPath : null,
            pageIndex: pageIdx,
            cropCorners: cropped != null ? const CropQuadCorners() : corners,
            filter: DocumentFilter.original,
          ),
        );
      }
    } else {
      // Fallback: 0 detections, save full image
      final pageIdx = basePageIndex;
      final fallbackImage = capturedPath.isNotEmpty
          ? capturedPath
          : 'assets/sample_document.png';
      newPages.add(
        ScannedPage(
          id: 'page_${DateTime.now().millisecondsSinceEpoch}_$pageIdx',
          imagePath: fallbackImage,
          originalImagePath: capturedPath.isNotEmpty ? capturedPath : null,
          pageIndex: pageIdx,
          cropCorners: const CropQuadCorners(),
          filter: DocumentFilter.original,
        ),
      );
    }

    // Instance-based Lock: Mark these document instances as captured so they won't detect again
    _isCurrentInstanceCaptured = true;
    _lastCapturedCornersList = List.from(targetCornersList);

    final updatedPages = List<ScannedPage>.from(state.capturedPages)
      ..addAll(newPages);

    final lastPageIndex = updatedPages.length - 1;
    final docsCount = newPages.length;

    emit(
      state.copyWith(
        status: ScannerStatus.cameraReady,
        capturedPages: updatedPages,
        selectedPageIndex: lastPageIndex,
        clearLiveCorners: true,
        isDocumentLocked: false,
        autoCaptureProgress: 0.0,
        statusMessage: docsCount > 1
            ? '$docsCount documents auto-cropped • Ready for next page'
            : 'Page ${lastPageIndex + 1} auto-cropped • Ready for next page',
      ),
    );

    // Resume image streaming only after photo inference and cropping complete
    if (_isCameraActive &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      await _startImageStreamIfNeeded();
    }
  }

  void _onSelectPageForEditing(
    SelectPageForEditingEvent event,
    Emitter<ScannerState> emit,
  ) {
    if (event.pageIndex >= 0 && event.pageIndex < state.capturedPages.length) {
      emit(
        state.copyWith(
          selectedPageIndex: event.pageIndex,
          status: ScannerStatus.previewReady,
        ),
      );
    }
  }

  void _onUpdateCropCorner(
    UpdateCropCornerEvent event,
    Emitter<ScannerState> emit,
  ) {
    if (state.currentPage == null) return;

    final updatedPage = state.currentPage!.copyWith(
      cropCorners: CropQuadCorners(
        topLeft: event.topLeft,
        topRight: event.topRight,
        bottomRight: event.bottomRight,
        bottomLeft: event.bottomLeft,
      ),
    );

    final updatedList = List<ScannedPage>.from(state.capturedPages);
    updatedList[state.selectedPageIndex] = updatedPage;

    emit(
      state.copyWith(
        capturedPages: updatedList,
        status: ScannerStatus.cropReady,
      ),
    );
  }

  Future<void> _onApplyCrop(
    ApplyCropEvent event,
    Emitter<ScannerState> emit,
  ) async {
    if (state.currentPage == null) return;

    emit(
      state.copyWith(
        status: ScannerStatus.processing,
        statusMessage: 'Cropping document...',
      ),
    );

    final originalPage = state.currentPage!;
    final croppedPath = await _cropService.cropImage(
      sourceImagePath: originalPage.imagePath,
      topLeft: event.topLeft,
      topRight: event.topRight,
      bottomRight: event.bottomRight,
      bottomLeft: event.bottomLeft,
      rotationDegrees: originalPage.rotationDegrees,
    );

    if (croppedPath != null) {
      final updatedPage = originalPage.copyWith(
        imagePath: croppedPath,
        rotationDegrees: 0,
        cropCorners: const CropQuadCorners(),
      );

      final updatedList = List<ScannedPage>.from(state.capturedPages);
      updatedList[state.selectedPageIndex] = updatedPage;

      emit(
        state.copyWith(
          capturedPages: updatedList,
          status: ScannerStatus.cropSuccess,
          statusMessage: 'Crop applied successfully',
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: ScannerStatus.previewReady,
          errorMessage: 'Failed to crop image: image file not accessible',
        ),
      );
    }
  }

  void _onApplyFilter(ApplyFilterEvent event, Emitter<ScannerState> emit) {
    if (state.currentPage == null) return;

    final updatedPage = state.currentPage!.copyWith(filter: event.filter);
    final updatedList = List<ScannedPage>.from(state.capturedPages);
    updatedList[state.selectedPageIndex] = updatedPage;

    emit(
      state.copyWith(
        capturedPages: updatedList,
        status: ScannerStatus.previewReady,
      ),
    );
  }

  void _onRotatePage(RotatePageEvent event, Emitter<ScannerState> emit) {
    final targetIndex = event.pageIndex ?? state.selectedPageIndex;
    if (state.capturedPages.isEmpty ||
        targetIndex < 0 ||
        targetIndex >= state.capturedPages.length) {
      return;
    }

    final targetPage = state.capturedPages[targetIndex];
    final newDegrees = (targetPage.rotationDegrees + 90) % 360;
    final updatedPage = targetPage.copyWith(
      rotationDegrees: newDegrees,
    );
    final updatedList = List<ScannedPage>.from(state.capturedPages);
    updatedList[targetIndex] = updatedPage;

    emit(
      state.copyWith(
        capturedPages: updatedList,
        selectedPageIndex: targetIndex,
      ),
    );
  }

  void _onDeletePage(DeletePageEvent event, Emitter<ScannerState> emit) {
    if (event.pageIndex < 0 || event.pageIndex >= state.capturedPages.length) {
      return;
    }

    final updatedList = List<ScannedPage>.from(state.capturedPages)
      ..removeAt(event.pageIndex);
    final nextIndex = updatedList.isEmpty
        ? 0
        : (state.selectedPageIndex >= updatedList.length
              ? updatedList.length - 1
              : state.selectedPageIndex);

    emit(
      state.copyWith(
        capturedPages: updatedList,
        selectedPageIndex: nextIndex,
        status: updatedList.isEmpty
            ? ScannerStatus.cameraReady
            : ScannerStatus.previewReady,
      ),
    );
  }

  Future<void> _onLoadSavedDocuments(
    LoadSavedDocumentsEvent event,
    Emitter<ScannerState> emit,
  ) async {
    try {
      final docs = await _storageService.loadAllDocuments();
      emit(
        state.copyWith(
          recentDocuments: docs,
          isCameraInitialized: false,
          clearLiveCorners: true,
          isDocumentLocked: false,
          autoCaptureProgress: 0.0,
          liveSharpnessScore: 0.0,
          statusMessage: 'Idle',
        ),
      );
    } catch (e) {
      debugPrint('Error loading saved documents in bloc: $e');
    }
  }

  Future<void> _onSaveDocument(
    SaveDocumentEvent event,
    Emitter<ScannerState> emit,
  ) async {
    if (state.capturedPages.isEmpty) return;

    emit(
      state.copyWith(
        status: ScannerStatus.processing,
        statusMessage: 'Saving document and generating PDF...',
      ),
    );

    try {
      ScannedDocument docToSave;

      // Check if updating an existing document
      if (state.editingDocumentId != null) {
        final existingIndex = state.recentDocuments.indexWhere(
          (doc) => doc.id == state.editingDocumentId,
        );
        if (existingIndex != -1) {
          final existingDoc = state.recentDocuments[existingIndex];
          docToSave = existingDoc.copyWith(
            title: event.title.trim().isNotEmpty
                ? event.title.trim()
                : existingDoc.title,
            pages: List<ScannedPage>.from(state.capturedPages),
          );
        } else {
          docToSave = ScannedDocument(
            id: state.editingDocumentId!,
            title: event.title.trim().isNotEmpty
                ? event.title.trim()
                : ScannedDocument.generateDefaultTitle(),
            createdAt: DateTime.now(),
            pages: List<ScannedPage>.from(state.capturedPages),
            scanMode: state.activeScanMode,
          );
        }
      } else {
        // Create brand new document
        docToSave = ScannedDocument(
          id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
          title: event.title.trim().isNotEmpty
              ? event.title.trim()
              : ScannedDocument.generateDefaultTitle(),
          createdAt: DateTime.now(),
          pages: List<ScannedPage>.from(state.capturedPages),
          scanMode: state.activeScanMode,
        );
      }

      // Step 1: Save document images and metadata persistently to local storage
      final persistedDoc = await _storageService.saveDocument(docToSave);

      // Step 2: Generate real PDF file from persisted pages and save to device disk
      final pdfFile = await _pdfExportService.generateAndSavePdf(persistedDoc);

      // Step 3: Link generated PDF path with document metadata
      final finalDoc = persistedDoc.copyWith(pdfPath: pdfFile.path);
      await _storageService.saveDocument(finalDoc);

      // Step 4: Refresh saved documents list from local disk
      final allDocs = await _storageService.loadAllDocuments();

      emit(
        state.copyWith(
          status: ScannerStatus.savedSuccess,
          recentDocuments: allDocs,
          capturedPages: const [],
          selectedPageIndex: 0,
          clearEditingDocumentId: true,
          lastExportedPdfPath: pdfFile.path,
          statusMessage: 'Saved locally as ${finalDoc.title}.pdf',
        ),
      );
    } catch (e) {
      debugPrint('Error saving document locally: $e');
      emit(
        state.copyWith(
          status: ScannerStatus.error,
          errorMessage: 'Failed to save document: $e',
        ),
      );
    }
  }

  Future<void> _onSharePdf(
    SharePdfEvent event,
    Emitter<ScannerState> emit,
  ) async {
    emit(
      state.copyWith(
        status: ScannerStatus.pdfExporting,
        statusMessage: 'Generating PDF for sharing...',
      ),
    );

    try {
      ScannedDocument docToShare;

      if (event.document != null) {
        docToShare = event.document!;
      } else if (state.capturedPages.isNotEmpty) {
        final title = event.title?.trim().isNotEmpty == true
            ? event.title!.trim()
            : ScannedDocument.generateDefaultTitle();
        docToShare = ScannedDocument(
          id: 'temp_share_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          createdAt: DateTime.now(),
          pages: List<ScannedPage>.from(state.capturedPages),
          scanMode: state.activeScanMode,
        );
      } else {
        emit(
          state.copyWith(
            status: ScannerStatus.error,
            errorMessage: 'No document or pages available to share',
          ),
        );
        return;
      }

      // Generate or reuse PDF
      File pdfFile;
      if (docToShare.pdfPath != null &&
          await File(docToShare.pdfPath!).exists()) {
        pdfFile = File(docToShare.pdfPath!);
      } else {
        pdfFile = await _pdfExportService.generateAndSavePdf(docToShare);
      }

      // Open native system share dialog
      await _pdfExportService.sharePdfFile(
        pdfFile: pdfFile,
        title: docToShare.title,
      );

      emit(
        state.copyWith(
          status: state.capturedPages.isNotEmpty
              ? ScannerStatus.previewReady
              : ScannerStatus.initial,
          lastExportedPdfPath: pdfFile.path,
          statusMessage: 'Ready',
        ),
      );
    } catch (e) {
      debugPrint('Error sharing PDF: $e');
      emit(
        state.copyWith(
          status: ScannerStatus.error,
          errorMessage: 'Failed to share PDF: $e',
        ),
      );
    }
  }

  Future<void> _onExportPdf(
    ExportPdfEvent event,
    Emitter<ScannerState> emit,
  ) async {
    emit(
      state.copyWith(
        status: ScannerStatus.pdfExporting,
        statusMessage: 'Exporting PDF to local storage...',
      ),
    );

    try {
      final pdfFile = await _pdfExportService.generateAndSavePdf(
        event.document,
      );
      final updatedDoc = event.document.copyWith(pdfPath: pdfFile.path);
      await _storageService.saveDocument(updatedDoc);

      final allDocs = await _storageService.loadAllDocuments();

      emit(
        state.copyWith(
          status: ScannerStatus.pdfExportSuccess,
          recentDocuments: allDocs,
          lastExportedPdfPath: pdfFile.path,
          statusMessage: 'PDF saved at: ${pdfFile.path}',
        ),
      );
    } catch (e) {
      debugPrint('Error exporting PDF: $e');
      emit(
        state.copyWith(
          status: ScannerStatus.error,
          errorMessage: 'Failed to export PDF: $e',
        ),
      );
    }
  }

  Future<void> _onDeleteDocument(
    DeleteDocumentEvent event,
    Emitter<ScannerState> emit,
  ) async {
    try {
      await _storageService.deleteDocument(event.documentId);
      final allDocs = await _storageService.loadAllDocuments();

      emit(
        state.copyWith(
          recentDocuments: allDocs,
          statusMessage: 'Document deleted successfully',
        ),
      );
    } catch (e) {
      debugPrint('Error deleting document: $e');
      emit(
        state.copyWith(
          status: ScannerStatus.error,
          errorMessage: 'Failed to delete document: $e',
        ),
      );
    }
  }

  void _onResetScanner(ResetScannerEvent event, Emitter<ScannerState> emit) {
    _isCurrentInstanceCaptured = false;
    _lastCapturedCornersList = [];
    _cornerSmoother.reset();
    _autoCaptureEngine.reset();
    emit(
      state.copyWith(
        status: ScannerStatus.cameraReady,
        capturedPages: const [],
        selectedPageIndex: 0,
        clearEditingDocumentId: true,
        statusMessage: 'Ready for scanning',
      ),
    );
  }

  @override
  Future<void> close() async {
    await _yoloWorker.dispose();
    if (_cameraController != null) {
      try {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
        await _cameraController!.dispose();
      } catch (_) {}
    }
    return super.close();
  }
}
