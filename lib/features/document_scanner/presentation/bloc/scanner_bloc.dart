import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/yolo_vision/models/yolo_model_config.dart';
import '../../../../core/yolo_vision/models/yolo_model_type.dart';
import '../../../../core/yolo_vision/services/yolo_isolate_worker.dart';
import '../../domain/models/scanned_document.dart';
import '../../domain/services/image_crop_service.dart';
import '../../domain/services/local_document_storage_service.dart';
import '../../domain/services/pdf_export_service.dart';
import 'scanner_event.dart';
import 'scanner_state.dart';

class ScannerBloc extends Bloc<ScannerEvent, ScannerState> {
  final LocalDocumentStorageService _storageService;
  final PdfExportService _pdfExportService;
  final ImageCropService _cropService;

  final YoloIsolateWorker _yoloWorker = YoloIsolateWorker();
  bool _isWorkerInitialized = false;
  bool _isModelLoaded = false;
  bool _isDisposingCamera = false;
  bool _isInitializingCamera = false;
  bool _isProcessingFrame = false;
  int _missedDetectionCount = 0;
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);

  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];

  CameraController? get cameraController => _cameraController;

  ScannerBloc({
    LocalDocumentStorageService? storageService,
    PdfExportService? pdfExportService,
    ImageCropService? cropService,
  }) : _storageService = storageService ?? LocalDocumentStorageService(),
       _pdfExportService = pdfExportService ?? PdfExportService(),
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

    // If camera controller is already initialized and valid, reuse it smoothly
    if (_cameraController != null && _cameraController!.value.isInitialized) {
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

        // Ensure flash is off upon clean init
        try {
          await newController.setFlashMode(FlashMode.off);
        } catch (_) {}

        emit(
          state.copyWith(
            status: ScannerStatus.cameraReady,
            isCameraInitialized: true,
            isFlashOn: false,
            statusMessage: 'Align document within borders',
          ),
        );

        // Initialize YOLO isolate worker and load notes-v1.tflite
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

  Future<void> _initYoloModel(Emitter<ScannerState> emit) async {
    if (_isModelLoaded) return;
    try {
      if (!_isWorkerInitialized) {
        _isWorkerInitialized = await _yoloWorker.initialize();
      }
      if (!_isWorkerInitialized) return;

      const config = YoloModelConfig(
        modelId: 'notes_v1_pose',
        assetPath: 'assets/models/notes-v1.tflite',
        labels: ['document'],
        modelType: YoloModelType.pose4Points,
        inputWidth: 768,
        inputHeight: 768,
        isNmsFree: true,
        defaultConfThreshold: 0.25,
        defaultIouThreshold: 0.45,
        numKeypoints: 4,
        keypointDim: 3,
      );

      final loaded = await _yoloWorker.loadModel(config);
      if (loaded) {
        _isModelLoaded = true;
        emit(state.copyWith(isModelLoaded: true));
        debugPrint(
          '[ScannerBloc] notes-v1.tflite loaded successfully in isolate',
        );
      }
    } catch (e) {
      debugPrint('[ScannerBloc] _initYoloModel error: $e');
    }
  }

  Future<void> _startImageStreamIfNeeded() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_cameraController!.value.isStreamingImages) {
      return;
    }

    try {
      await _cameraController!.startImageStream((CameraImage image) {
        final now = DateTime.now();
        if (_isProcessingFrame ||
            now.difference(_lastFrameTime).inMilliseconds < 90) {
          return;
        }
        _isProcessingFrame = true;
        _lastFrameTime = now;

        final rotationDegrees = _cameraController?.description.sensorOrientation ?? 90;
        _processCameraImage(image, rotationDegrees)
            .then((_) {
              _isProcessingFrame = false;
            })
            .catchError((e) {
              _isProcessingFrame = false;
            });
      });
    } catch (e) {
      debugPrint('[ScannerBloc] startImageStream error: $e');
    }
  }

  Future<void> _processCameraImage(CameraImage image, int rotationDegrees) async {
    if (!_isModelLoaded ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final isYuv =
          image.format.group == ImageFormatGroup.yuv420 ||
          image.format.group == ImageFormatGroup.nv21;
      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes.length > 1 ? image.planes[1].bytes : null;
      final vPlane = image.planes.length > 2 ? image.planes[2].bytes : null;
      final bgra = !isYuv && image.planes.isNotEmpty
          ? image.planes[0].bytes
          : null;

      final result = await _yoloWorker.processFrame(
        yPlaneBytes: yPlane,
        uPlaneBytes: uPlane,
        vPlaneBytes: vPlane,
        bgraBytes: bgra,
        width: image.width,
        height: image.height,
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes.length > 1 ? image.planes[1].bytesPerRow : 0,
        uvPixelStride: image.planes.length > 1
            ? (image.planes[1].bytesPerPixel ?? 1)
            : 1,
        isYuv: isYuv,
        confThreshold: 0.25,
        iouThreshold: 0.45,
        rotationDegrees: rotationDegrees,
      );

      if (result != null && result.orientedBoxes.isNotEmpty) {
        _missedDetectionCount = 0;
        final ob = result.orientedBoxes.first;
        dev.log(
          '✨ [ScannerBloc] 📄 Quad Corners: conf=${ob.confidence.toStringAsFixed(3)} '
          'p1=(${ob.p1.x.toStringAsFixed(2)}, ${ob.p1.y.toStringAsFixed(2)}) '
          'p2=(${ob.p2.x.toStringAsFixed(2)}, ${ob.p2.y.toStringAsFixed(2)}) '
          'p3=(${ob.p3.x.toStringAsFixed(2)}, ${ob.p3.y.toStringAsFixed(2)}) '
          'p4=(${ob.p4.x.toStringAsFixed(2)}, ${ob.p4.y.toStringAsFixed(2)})',
          name: 'YOLO',
        );
        final detectedCorners = CropQuadCorners(
          topLeft: Offset(ob.p1.x, ob.p1.y),
          topRight: Offset(ob.p2.x, ob.p2.y),
          bottomRight: Offset(ob.p3.x, ob.p3.y),
          bottomLeft: Offset(ob.p4.x, ob.p4.y),
        );
        add(LiveCornersDetectedEvent(detectedCorners));
      } else {
        _missedDetectionCount++;
        // Keep live corners visible for up to 2 empty frames so overlay doesn't flicker away
        if (_missedDetectionCount >= 2) {
          add(const ClearLiveCornersEvent());
        }
      }
    } catch (e) {
      debugPrint('[ScannerBloc] _processCameraImage error: $e');
    }
  }

  void _onLiveCornersDetected(
    LiveCornersDetectedEvent event,
    Emitter<ScannerState> emit,
  ) {
    dev.log('🟢 [ScannerBloc] State updated with liveDetectedCorners', name: 'YOLO');
    emit(
      state.copyWith(
        liveDetectedCorners: event.corners,
        statusMessage: 'Document detected',
      ),
    );
  }

  void _onClearLiveCorners(
    ClearLiveCornersEvent event,
    Emitter<ScannerState> emit,
  ) {
    if (state.liveDetectedCorners != null) {
      dev.log('⚪ [ScannerBloc] Clearing liveDetectedCorners', name: 'YOLO');
      emit(
        state.copyWith(
          clearLiveCorners: true,
          statusMessage: 'Align document within borders',
        ),
      );
    }
  }

  Future<void> _onDisposeCamera(
    DisposeCameraEvent event,
    Emitter<ScannerState> emit,
  ) async {
    _isDisposingCamera = true;
    try {
      if (_cameraController != null) {
        final controllerToDispose = _cameraController;
        _cameraController = null;
        if (controllerToDispose != null &&
            controllerToDispose.value.isStreamingImages) {
          try {
            await controllerToDispose.stopImageStream();
          } catch (_) {}
        }
        await controllerToDispose?.dispose();
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
        status: state.capturedPages.isNotEmpty
            ? ScannerStatus.previewReady
            : ScannerStatus.initial,
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
    emit(state.copyWith(status: ScannerStatus.capturing));

    String capturedPath = '';
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        if (_cameraController!.value.isStreamingImages) {
          try {
            await _cameraController!.stopImageStream();
          } catch (_) {}
        }

        final XFile file = await _cameraController!.takePicture();
        capturedPath = file.path;

        // Resume live streaming if still active
        await _startImageStreamIfNeeded();
      }
    } catch (e) {
      debugPrint('Snapshot error: $e');
    }

    // Auto-populate crop corners with detected corners if available
    final newPageIndex = state.capturedPages.length;
    final pageCorners = state.liveDetectedCorners ?? const CropQuadCorners();

    final newPage = ScannedPage(
      id: 'page_${DateTime.now().millisecondsSinceEpoch}_$newPageIndex',
      imagePath: capturedPath.isNotEmpty
          ? capturedPath
          : 'assets/sample_document.png',
      pageIndex: newPageIndex,
      cropCorners: pageCorners,
      filter: DocumentFilter.magicColor,
    );

    final updatedPages = List<ScannedPage>.from(state.capturedPages)
      ..add(newPage);

    emit(
      state.copyWith(
        status: ScannerStatus.cameraReady,
        capturedPages: updatedPages,
        selectedPageIndex: newPageIndex,
        statusMessage: state.liveDetectedCorners != null
            ? 'Page ${newPageIndex + 1} captured (Auto-detected)'
            : 'Page ${newPageIndex + 1} captured',
      ),
    );
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
    if (state.currentPage == null) return;

    final newDegrees = (state.currentPage!.rotationDegrees + 90) % 360;
    final updatedPage = state.currentPage!.copyWith(
      rotationDegrees: newDegrees,
    );
    final updatedList = List<ScannedPage>.from(state.capturedPages);
    updatedList[state.selectedPageIndex] = updatedPage;

    emit(state.copyWith(capturedPages: updatedList));
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
      emit(state.copyWith(recentDocuments: docs));
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
                : 'Scan ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
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
              : 'Scan ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
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
            : 'Scan_${DateTime.now().day}_${DateTime.now().month}_${DateTime.now().year}';
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
