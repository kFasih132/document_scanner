import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import '../../../../core/yolo_vision/models/yolo_model_config.dart';
import '../../domain/models/scanned_document.dart';
import 'scanner_state.dart';

abstract class ScannerEvent extends Equatable {
  const ScannerEvent();

  @override
  List<Object?> get props => [];
}

class InitializeCameraEvent extends ScannerEvent {
  const InitializeCameraEvent();
}

class DisposeCameraEvent extends ScannerEvent {
  const DisposeCameraEvent();
}

class OpenDocumentForEditingEvent extends ScannerEvent {
  final ScannedDocument document;
  const OpenDocumentForEditingEvent(this.document);

  @override
  List<Object?> get props => [document];
}

class SwitchScanModeEvent extends ScannerEvent {
  final ScanMode mode;
  const SwitchScanModeEvent(this.mode);

  @override
  List<Object?> get props => [mode];
}

class ToggleFlashEvent extends ScannerEvent {
  const ToggleFlashEvent();
}

class ToggleAutoCaptureEvent extends ScannerEvent {
  const ToggleAutoCaptureEvent();
}

class CapturePageEvent extends ScannerEvent {
  const CapturePageEvent();
}

class SelectPageForEditingEvent extends ScannerEvent {
  final int pageIndex;
  const SelectPageForEditingEvent(this.pageIndex);

  @override
  List<Object?> get props => [pageIndex];
}

class UpdateCropCornerEvent extends ScannerEvent {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const UpdateCropCornerEvent({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  @override
  List<Object?> get props => [topLeft, topRight, bottomRight, bottomLeft];
}

class ApplyCropEvent extends ScannerEvent {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const ApplyCropEvent({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  @override
  List<Object?> get props => [topLeft, topRight, bottomRight, bottomLeft];
}

class ApplyFilterEvent extends ScannerEvent {
  final DocumentFilter filter;
  const ApplyFilterEvent(this.filter);

  @override
  List<Object?> get props => [filter];
}

class RotatePageEvent extends ScannerEvent {
  final int? pageIndex;
  const RotatePageEvent([this.pageIndex]);

  @override
  List<Object?> get props => [pageIndex];
}

class DeletePageEvent extends ScannerEvent {
  final int pageIndex;
  const DeletePageEvent(this.pageIndex);

  @override
  List<Object?> get props => [pageIndex];
}

class SaveDocumentEvent extends ScannerEvent {
  final String title;
  const SaveDocumentEvent(this.title);

  @override
  List<Object?> get props => [title];
}

class LoadSavedDocumentsEvent extends ScannerEvent {
  const LoadSavedDocumentsEvent();
}

class SharePdfEvent extends ScannerEvent {
  final ScannedDocument? document;
  final String? title;

  const SharePdfEvent({this.document, this.title});

  @override
  List<Object?> get props => [document, title];
}

class ExportPdfEvent extends ScannerEvent {
  final ScannedDocument document;

  const ExportPdfEvent(this.document);

  @override
  List<Object?> get props => [document];
}

class DeleteDocumentEvent extends ScannerEvent {
  final String documentId;

  const DeleteDocumentEvent(this.documentId);

  @override
  List<Object?> get props => [documentId];
}

class ResetScannerEvent extends ScannerEvent {
  const ResetScannerEvent();
}

class LiveCornersDetectedEvent extends ScannerEvent {
  final CropQuadCorners corners;
  final List<CropQuadCorners> cornersList;
  final bool isDocumentLocked;
  final double autoCaptureProgress;
  final double sharpnessScore;
  final String? statusMessage;

  LiveCornersDetectedEvent({
    required this.corners,
    List<CropQuadCorners>? cornersList,
    this.isDocumentLocked = false,
    this.autoCaptureProgress = 0.0,
    this.sharpnessScore = 0.0,
    this.statusMessage,
  }) : cornersList = cornersList ?? [corners];

  @override
  List<Object?> get props => [
        corners,
        cornersList,
        isDocumentLocked,
        autoCaptureProgress,
        sharpnessScore,
        statusMessage,
      ];
}

class ClearLiveCornersEvent extends ScannerEvent {
  const ClearLiveCornersEvent();
}

class SwitchScannerModelEvent extends ScannerEvent {
  final ScannerModelOption model;
  const SwitchScannerModelEvent(this.model);

  @override
  List<Object?> get props => [model];
}

class UpdateScannerConfigEvent extends ScannerEvent {
  final double? confThreshold;
  final double? iouThreshold;
  final YoloHardwareDelegate? hardwareDelegate;
  final ScannerModelOption? model;

  const UpdateScannerConfigEvent({
    this.confThreshold,
    this.iouThreshold,
    this.hardwareDelegate,
    this.model,
  });

  @override
  List<Object?> get props => [
        confThreshold,
        iouThreshold,
        hardwareDelegate,
        model,
      ];
}

class ResetScannerConfigEvent extends ScannerEvent {
  const ResetScannerConfigEvent();
}


