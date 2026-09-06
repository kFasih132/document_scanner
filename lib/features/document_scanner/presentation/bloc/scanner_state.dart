import 'package:equatable/equatable.dart';
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

class ScannerState extends Equatable {
  final ScannerStatus status;
  final bool isCameraInitialized;
  final bool isFlashOn;
  final bool isAutoCaptureEnabled;
  final ScanMode activeScanMode;
  final List<ScannedPage> capturedPages;
  final int selectedPageIndex;
  final List<ScannedDocument> recentDocuments;
  final String? editingDocumentId;
  final String? lastExportedPdfPath;
  final String? errorMessage;
  final String? statusMessage;
  final CropQuadCorners? liveDetectedCorners;
  final bool isModelLoaded;

  const ScannerState({
    this.status = ScannerStatus.initial,
    this.isCameraInitialized = false,
    this.isFlashOn = false,
    this.isAutoCaptureEnabled = true,
    this.activeScanMode = ScanMode.document,
    this.capturedPages = const [],
    this.selectedPageIndex = 0,
    this.recentDocuments = const [],
    this.editingDocumentId,
    this.lastExportedPdfPath,
    this.errorMessage,
    this.statusMessage,
    this.liveDetectedCorners,
    this.isModelLoaded = false,
  });

  ScannedPage? get currentPage {
    if (capturedPages.isEmpty) return null;
    if (selectedPageIndex < 0 || selectedPageIndex >= capturedPages.length) {
      return capturedPages.last;
    }
    return capturedPages[selectedPageIndex];
  }

  int get pageCount => capturedPages.length;

  ScannerState copyWith({
    ScannerStatus? status,
    bool? isCameraInitialized,
    bool? isFlashOn,
    bool? isAutoCaptureEnabled,
    ScanMode? activeScanMode,
    List<ScannedPage>? capturedPages,
    int? selectedPageIndex,
    List<ScannedDocument>? recentDocuments,
    String? editingDocumentId,
    bool clearEditingDocumentId = false,
    String? lastExportedPdfPath,
    String? errorMessage,
    String? statusMessage,
    CropQuadCorners? liveDetectedCorners,
    bool clearLiveCorners = false,
    bool? isModelLoaded,
  }) {
    return ScannerState(
      status: status ?? this.status,
      isCameraInitialized: isCameraInitialized ?? this.isCameraInitialized,
      isFlashOn: isFlashOn ?? this.isFlashOn,
      isAutoCaptureEnabled: isAutoCaptureEnabled ?? this.isAutoCaptureEnabled,
      activeScanMode: activeScanMode ?? this.activeScanMode,
      capturedPages: capturedPages ?? this.capturedPages,
      selectedPageIndex: selectedPageIndex ?? this.selectedPageIndex,
      recentDocuments: recentDocuments ?? this.recentDocuments,
      editingDocumentId: clearEditingDocumentId
          ? null
          : (editingDocumentId ?? this.editingDocumentId),
      lastExportedPdfPath: lastExportedPdfPath ?? this.lastExportedPdfPath,
      errorMessage: errorMessage,
      statusMessage: statusMessage ?? this.statusMessage,
      liveDetectedCorners: clearLiveCorners
          ? null
          : (liveDetectedCorners ?? this.liveDetectedCorners),
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
    );
  }

  @override
  List<Object?> get props => [
        status,
        isCameraInitialized,
        isFlashOn,
        isAutoCaptureEnabled,
        activeScanMode,
        capturedPages,
        selectedPageIndex,
        recentDocuments,
        editingDocumentId,
        lastExportedPdfPath,
        errorMessage,
        statusMessage,
        liveDetectedCorners,
        isModelLoaded,
      ];
}
