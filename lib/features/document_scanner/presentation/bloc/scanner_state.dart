import 'package:equatable/equatable.dart';

import '../../../../core/yolo_vision/models/yolo_model_config.dart';
import '../../domain/models/scanned_document.dart';

enum ScannerStatus {
  initial,
  loading,
  cameraReady,
  capturing,
  processing,
  cropReady,
  cropSuccess,
  previewReady,
  savedSuccess,
  pdfExporting,
  pdfExportSuccess,
  error,
}

enum ScannerModelOption {
  v1Fp32(
    id: 'notes_v1_pose',
    title: 'V1 (FP32)',
    subtitle: '10.3 MB Full Precision (Recommended)',
    assetPath: 'assets/models/notes-v1.tflite',
    badge: '10 MB',
  ),
  v4Fp32(
    id: 'notes_v4_pose',
    title: 'V4 (FP32)',
    subtitle: '10.3 MB Full Precision (Recommended)',
    assetPath: 'assets/models/v4.tflite',
    badge: '10 MB',
  ),
  v2W8A16(
    id: 'notes-v2-n-w8a16',
    title: 'V2 (W8A16)',
    subtitle: '3.1 MB Fast (Experimental)',
    assetPath: 'assets/models/notes-v2-n-w8a16.tflite',
    badge: '3 MB',
  );

  final String id;
  final String title;
  final String subtitle;
  final String assetPath;
  final String badge;

  const ScannerModelOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.assetPath,
    required this.badge,
  });
}

// =============================================================================
// SUB-STATE 1: Scanner Feedback & Lifecycle Status
// =============================================================================

class ScannerFeedbackState extends Equatable {
  final ScannerStatus status;
  final String? statusMessage;
  final String? errorMessage;

  const ScannerFeedbackState({
    this.status = ScannerStatus.initial,
    this.statusMessage,
    this.errorMessage,
  });

  ScannerFeedbackState copyWith({
    ScannerStatus? status,
    String? statusMessage,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ScannerFeedbackState(
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, statusMessage, errorMessage];
}

// =============================================================================
// SUB-STATE 2: Camera Controls & Operating Mode
// =============================================================================

class CameraSettingsState extends Equatable {
  final bool isCameraInitialized;
  final bool isFlashOn;
  final bool isAutoCaptureEnabled;
  final ScanMode activeScanMode;

  const CameraSettingsState({
    this.isCameraInitialized = false,
    this.isFlashOn = false,
    this.isAutoCaptureEnabled = true,
    this.activeScanMode = ScanMode.document,
  });

  CameraSettingsState copyWith({
    bool? isCameraInitialized,
    bool? isFlashOn,
    bool? isAutoCaptureEnabled,
    ScanMode? activeScanMode,
  }) {
    return CameraSettingsState(
      isCameraInitialized: isCameraInitialized ?? this.isCameraInitialized,
      isFlashOn: isFlashOn ?? this.isFlashOn,
      isAutoCaptureEnabled: isAutoCaptureEnabled ?? this.isAutoCaptureEnabled,
      activeScanMode: activeScanMode ?? this.activeScanMode,
    );
  }

  @override
  List<Object?> get props => [
    isCameraInitialized,
    isFlashOn,
    isAutoCaptureEnabled,
    activeScanMode,
  ];
}

// =============================================================================
// SUB-STATE 3: Live Real-Time Vision & Tracking (High-Frequency Stream)
// =============================================================================

class LiveVisionState extends Equatable {
  final List<CropQuadCorners> liveDetectedCornersList;
  final bool isDocumentLocked;
  final double autoCaptureProgress;
  final double liveSharpnessScore;

  const LiveVisionState({
    this.liveDetectedCornersList = const [],
    this.isDocumentLocked = false,
    this.autoCaptureProgress = 0.0,
    this.liveSharpnessScore = 0.0,
  });

  CropQuadCorners? get liveDetectedCorners =>
      liveDetectedCornersList.isNotEmpty ? liveDetectedCornersList.first : null;

  LiveVisionState copyWith({
    List<CropQuadCorners>? liveDetectedCornersList,
    CropQuadCorners? liveDetectedCorners,
    bool clearLiveCorners = false,
    bool? isDocumentLocked,
    double? autoCaptureProgress,
    double? liveSharpnessScore,
  }) {
    List<CropQuadCorners> resolvedLiveCorners;
    if (clearLiveCorners) {
      resolvedLiveCorners = const [];
    } else if (liveDetectedCornersList != null) {
      resolvedLiveCorners = liveDetectedCornersList;
    } else if (liveDetectedCorners != null) {
      resolvedLiveCorners = [liveDetectedCorners];
    } else {
      resolvedLiveCorners = this.liveDetectedCornersList;
    }

    return LiveVisionState(
      liveDetectedCornersList: resolvedLiveCorners,
      isDocumentLocked: isDocumentLocked ?? this.isDocumentLocked,
      autoCaptureProgress: autoCaptureProgress ?? this.autoCaptureProgress,
      liveSharpnessScore: liveSharpnessScore ?? this.liveSharpnessScore,
    );
  }

  @override
  List<Object?> get props => [
    liveDetectedCornersList,
    isDocumentLocked,
    autoCaptureProgress,
    liveSharpnessScore,
  ];
}

// =============================================================================
// SUB-STATE 4: Frame Cache & Staging for Cropping
// =============================================================================

class FrameCacheState extends Equatable {
  final String? latestCachedFramePath;
  final List<CropQuadCorners> latestCachedFrameCornersList;

  const FrameCacheState({
    this.latestCachedFramePath,
    this.latestCachedFrameCornersList = const [],
  });

  CropQuadCorners? get latestCachedFrameCorners =>
      latestCachedFrameCornersList.isNotEmpty
      ? latestCachedFrameCornersList.first
      : null;

  FrameCacheState copyWith({
    String? latestCachedFramePath,
    List<CropQuadCorners>? latestCachedFrameCornersList,
    CropQuadCorners? latestCachedFrameCorners,
  }) {
    List<CropQuadCorners> resolvedCachedCorners;
    if (latestCachedFrameCornersList != null) {
      resolvedCachedCorners = latestCachedFrameCornersList;
    } else if (latestCachedFrameCorners != null) {
      resolvedCachedCorners = [latestCachedFrameCorners];
    } else {
      resolvedCachedCorners = this.latestCachedFrameCornersList;
    }

    return FrameCacheState(
      latestCachedFramePath:
          latestCachedFramePath ?? this.latestCachedFramePath,
      latestCachedFrameCornersList: resolvedCachedCorners,
    );
  }

  @override
  List<Object?> get props => [
    latestCachedFramePath,
    latestCachedFrameCornersList,
  ];
}

// =============================================================================
// SUB-STATE 5: Batch Document Session & Persistence
// =============================================================================

class BatchDocumentState extends Equatable {
  final List<ScannedPage> capturedPages;
  final int selectedPageIndex;
  final List<ScannedDocument> recentDocuments;
  final String? editingDocumentId;
  final String? lastExportedPdfPath;

  const BatchDocumentState({
    this.capturedPages = const [],
    this.selectedPageIndex = 0,
    this.recentDocuments = const [],
    this.editingDocumentId,
    this.lastExportedPdfPath,
  });

  ScannedPage? get currentPage {
    if (capturedPages.isEmpty) return null;
    if (selectedPageIndex < 0 || selectedPageIndex >= capturedPages.length) {
      return capturedPages.last;
    }
    return capturedPages[selectedPageIndex];
  }

  int get pageCount => capturedPages.length;

  BatchDocumentState copyWith({
    List<ScannedPage>? capturedPages,
    int? selectedPageIndex,
    List<ScannedDocument>? recentDocuments,
    String? editingDocumentId,
    bool clearEditingDocumentId = false,
    String? lastExportedPdfPath,
  }) {
    return BatchDocumentState(
      capturedPages: capturedPages ?? this.capturedPages,
      selectedPageIndex: selectedPageIndex ?? this.selectedPageIndex,
      recentDocuments: recentDocuments ?? this.recentDocuments,
      editingDocumentId: clearEditingDocumentId
          ? null
          : (editingDocumentId ?? this.editingDocumentId),
      lastExportedPdfPath: lastExportedPdfPath ?? this.lastExportedPdfPath,
    );
  }

  @override
  List<Object?> get props => [
    capturedPages,
    selectedPageIndex,
    recentDocuments,
    editingDocumentId,
    lastExportedPdfPath,
  ];
}

// =============================================================================
// SUB-STATE 6: YOLO Model Configuration & Hardware Delegate
// =============================================================================

class ModelConfigState extends Equatable {
  final ScannerModelOption activeModel;
  final double confThreshold;
  final double iouThreshold;
  final YoloHardwareDelegate hardwareDelegate;
  final bool isModelLoaded;

  const ModelConfigState({
    this.activeModel = ScannerModelOption.v1Fp32,
    this.confThreshold = 0.35,
    this.iouThreshold = 0.45,
    this.hardwareDelegate = YoloHardwareDelegate.cpu,
    this.isModelLoaded = false,
  });

  ModelConfigState copyWith({
    ScannerModelOption? activeModel,
    double? confThreshold,
    double? iouThreshold,
    YoloHardwareDelegate? hardwareDelegate,
    bool? isModelLoaded,
  }) {
    return ModelConfigState(
      activeModel: activeModel ?? this.activeModel,
      confThreshold: confThreshold ?? this.confThreshold,
      iouThreshold: iouThreshold ?? this.iouThreshold,
      hardwareDelegate: hardwareDelegate ?? this.hardwareDelegate,
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
    );
  }

  @override
  List<Object?> get props => [
    activeModel,
    confThreshold,
    iouThreshold,
    hardwareDelegate,
    isModelLoaded,
  ];
}

// =============================================================================
// ROOT COMPOSITE STATE: ScannerState
// =============================================================================

class ScannerState extends Equatable {
  final ScannerFeedbackState feedback;
  final CameraSettingsState camera;
  final LiveVisionState vision;
  final FrameCacheState cache;
  final BatchDocumentState batch;
  final ModelConfigState model;

  const ScannerState({
    this.feedback = const ScannerFeedbackState(),
    this.camera = const CameraSettingsState(),
    this.vision = const LiveVisionState(),
    this.cache = const FrameCacheState(),
    this.batch = const BatchDocumentState(),
    this.model = const ModelConfigState(),
  });

  // ---------------------------------------------------------------------------
  // Backward-Compatible Convenience Getters
  // ---------------------------------------------------------------------------

  // Feedback getters
  ScannerStatus get status => feedback.status;
  String? get statusMessage => feedback.statusMessage;
  String? get errorMessage => feedback.errorMessage;

  // Camera settings getters
  bool get isCameraInitialized => camera.isCameraInitialized;
  bool get isFlashOn => camera.isFlashOn;
  bool get isAutoCaptureEnabled => camera.isAutoCaptureEnabled;
  ScanMode get activeScanMode => camera.activeScanMode;

  // Live vision tracking getters
  List<CropQuadCorners> get liveDetectedCornersList =>
      vision.liveDetectedCornersList;
  CropQuadCorners? get liveDetectedCorners => vision.liveDetectedCorners;
  bool get isDocumentLocked => vision.isDocumentLocked;
  double get autoCaptureProgress => vision.autoCaptureProgress;
  double get liveSharpnessScore => vision.liveSharpnessScore;

  // Frame cache getters
  String? get latestCachedFramePath => cache.latestCachedFramePath;
  List<CropQuadCorners> get latestCachedFrameCornersList =>
      cache.latestCachedFrameCornersList;
  CropQuadCorners? get latestCachedFrameCorners =>
      cache.latestCachedFrameCorners;

  // Batch document session getters
  List<ScannedPage> get capturedPages => batch.capturedPages;
  int get selectedPageIndex => batch.selectedPageIndex;
  List<ScannedDocument> get recentDocuments => batch.recentDocuments;
  String? get editingDocumentId => batch.editingDocumentId;
  String? get lastExportedPdfPath => batch.lastExportedPdfPath;
  ScannedPage? get currentPage => batch.currentPage;
  int get pageCount => batch.pageCount;

  // Model config getters
  ScannerModelOption get activeModel => model.activeModel;
  double get confThreshold => model.confThreshold;
  double get iouThreshold => model.iouThreshold;
  YoloHardwareDelegate get hardwareDelegate => model.hardwareDelegate;
  bool get isModelLoaded => model.isModelLoaded;

  // ---------------------------------------------------------------------------
  // copyWith supporting both sub-state updates and direct convenience parameters
  // ---------------------------------------------------------------------------

  ScannerState copyWith({
    // Sub-state objects
    ScannerFeedbackState? feedback,
    CameraSettingsState? camera,
    LiveVisionState? vision,
    FrameCacheState? cache,
    BatchDocumentState? batch,
    ModelConfigState? model,

    // Feedback convenience overrides
    ScannerStatus? status,
    String? statusMessage,
    String? errorMessage,
    bool clearErrorMessage = false,

    // Camera convenience overrides
    bool? isCameraInitialized,
    bool? isFlashOn,
    bool? isAutoCaptureEnabled,
    ScanMode? activeScanMode,

    // Vision convenience overrides
    List<CropQuadCorners>? liveDetectedCornersList,
    CropQuadCorners? liveDetectedCorners,
    bool clearLiveCorners = false,
    bool? isDocumentLocked,
    double? autoCaptureProgress,
    double? liveSharpnessScore,

    // Frame cache convenience overrides
    String? latestCachedFramePath,
    List<CropQuadCorners>? latestCachedFrameCornersList,
    CropQuadCorners? latestCachedFrameCorners,

    // Batch document convenience overrides
    List<ScannedPage>? capturedPages,
    int? selectedPageIndex,
    List<ScannedDocument>? recentDocuments,
    String? editingDocumentId,
    bool clearEditingDocumentId = false,
    String? lastExportedPdfPath,

    // Model config convenience overrides
    ScannerModelOption? activeModel,
    double? confThreshold,
    double? iouThreshold,
    YoloHardwareDelegate? hardwareDelegate,
    bool? isModelLoaded,
  }) {
    // 1. Resolve Feedback Sub-State
    final updatedFeedback =
        feedback ??
        this.feedback.copyWith(
          status: status,
          statusMessage: statusMessage,
          errorMessage: errorMessage,
          clearErrorMessage: clearErrorMessage,
        );

    // 2. Resolve Camera Sub-State
    final updatedCamera =
        camera ??
        this.camera.copyWith(
          isCameraInitialized: isCameraInitialized,
          isFlashOn: isFlashOn,
          isAutoCaptureEnabled: isAutoCaptureEnabled,
          activeScanMode: activeScanMode,
        );

    // 3. Resolve Vision Sub-State
    final updatedVision =
        vision ??
        this.vision.copyWith(
          liveDetectedCornersList: liveDetectedCornersList,
          liveDetectedCorners: liveDetectedCorners,
          clearLiveCorners: clearLiveCorners,
          isDocumentLocked: isDocumentLocked,
          autoCaptureProgress: autoCaptureProgress,
          liveSharpnessScore: liveSharpnessScore,
        );

    // 4. Resolve Cache Sub-State
    final updatedCache =
        cache ??
        this.cache.copyWith(
          latestCachedFramePath: latestCachedFramePath,
          latestCachedFrameCornersList: latestCachedFrameCornersList,
          latestCachedFrameCorners: latestCachedFrameCorners,
        );

    // 5. Resolve Batch Sub-State
    final updatedBatch =
        batch ??
        this.batch.copyWith(
          capturedPages: capturedPages,
          selectedPageIndex: selectedPageIndex,
          recentDocuments: recentDocuments,
          editingDocumentId: editingDocumentId,
          clearEditingDocumentId: clearEditingDocumentId,
          lastExportedPdfPath: lastExportedPdfPath,
        );

    // 6. Resolve Model Sub-State
    final updatedModel =
        model ??
        this.model.copyWith(
          activeModel: activeModel,
          confThreshold: confThreshold,
          iouThreshold: iouThreshold,
          hardwareDelegate: hardwareDelegate,
          isModelLoaded: isModelLoaded,
        );

    return ScannerState(
      feedback: updatedFeedback,
      camera: updatedCamera,
      vision: updatedVision,
      cache: updatedCache,
      batch: updatedBatch,
      model: updatedModel,
    );
  }

  @override
  List<Object?> get props => [feedback, camera, vision, cache, batch, model];
}
