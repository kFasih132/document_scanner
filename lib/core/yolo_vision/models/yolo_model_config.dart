import 'dart:typed_data';
import 'yolo_model_type.dart';

/// Available hardware execution delegates for on-device inference
enum YoloHardwareDelegate {
  /// Automatically picks the best accelerator (GPU -> NNAPI -> CPU)
  auto,

  /// Forces GPU Delegate (Vulkan/OpenGL on Android, Metal on iOS)
  gpu,

  /// Forces Android NNAPI / Qualcomm Hexagon / Google Tensor NPU
  nnapi,

  /// Fallback to multi-threaded CPU
  cpu,
}

/// Generic configuration describing a YOLO model and its tensor characteristics.
class YoloModelConfig {
  /// Unique identifier for this model (e.g. 'document_yolo26')
  final String modelId;

  /// Flutter asset path (e.g. 'assets/models/notes-v1.tflite')
  final String? assetPath;

  /// Absolute file system path if loaded dynamically from device storage
  final String? filePath;

  /// Raw byte buffer if loaded directly over network or memory cache
  final Uint8List? modelBytes;

  /// Class labels in exact index order
  final List<String> labels;

  /// Type of detection: standard bounding box vs 4-point pose/quadrilateral
  final YoloModelType modelType;

  /// Preferred hardware acceleration delegate
  final YoloHardwareDelegate delegate;

  /// Expected input tensor width (typically 768, 640, 320, etc.)
  final int inputWidth;

  /// Expected input tensor height (typically 768, 640, 320, etc.)
  final int inputHeight;

  /// Whether tensor layout is Channels-First (NCHW [1, 3, H, W]) or Channels-Last (NHWC [1, H, W, 3])
  final bool isNCHW;

  /// Default confidence threshold
  final double defaultConfThreshold;

  /// Default IoU threshold for Non-Maximum Suppression
  final double defaultIouThreshold;

  /// Number of keypoints if [modelType] == [YoloModelType.pose4Points] (default 4)
  final int numKeypoints;

  /// Elements per keypoint: 3 for [x, y, visibility/conf] or 2 for [x, y]
  final int keypointDim;

  /// True if the architecture is NMS-free (e.g. YOLO26, YOLOv10, RT-DETR)
  /// If true, the pipeline picks the top prediction directly, avoiding redundant O(N^2) IoU loops.
  final bool isNmsFree;

  /// Custom input quantization scale (auto-detected from model if null)
  final double? inputScale;

  /// Custom input quantization zero point (auto-detected from model if null)
  final int? inputZeroPoint;

  const YoloModelConfig({
    required this.modelId,
    this.assetPath,
    this.filePath,
    this.modelBytes,
    required this.labels,
    this.modelType = YoloModelType.standardDetection,
    this.delegate = YoloHardwareDelegate.auto,
    this.inputWidth = 768,
    this.inputHeight = 768,
    this.isNCHW = true,
    this.defaultConfThreshold = 0.25,
    this.defaultIouThreshold = 0.45,
    this.numKeypoints = 4,
    this.keypointDim = 3,
    this.isNmsFree = true,
    this.inputScale,
    this.inputZeroPoint,
  });

  /// Factory constructor for Flutter asset-based models
  factory YoloModelConfig.fromAsset({
    required String modelId,
    required String assetPath,
    required List<String> labels,
    YoloModelType modelType = YoloModelType.standardDetection,
    YoloHardwareDelegate delegate = YoloHardwareDelegate.auto,
    int inputWidth = 768,
    int inputHeight = 768,
    bool isNCHW = true,
    double defaultConfThreshold = 0.25,
    double defaultIouThreshold = 0.45,
    int numKeypoints = 4,
    int keypointDim = 3,
    bool isNmsFree = true,
    double? inputScale,
    int? inputZeroPoint,
  }) {
    return YoloModelConfig(
      modelId: modelId,
      assetPath: assetPath,
      labels: labels,
      modelType: modelType,
      delegate: delegate,
      inputWidth: inputWidth,
      inputHeight: inputHeight,
      isNCHW: isNCHW,
      defaultConfThreshold: defaultConfThreshold,
      defaultIouThreshold: defaultIouThreshold,
      numKeypoints: numKeypoints,
      keypointDim: keypointDim,
      isNmsFree: isNmsFree,
      inputScale: inputScale,
      inputZeroPoint: inputZeroPoint,
    );
  }

  /// Copies config with overridden properties
  YoloModelConfig copyWith({
    String? modelId,
    String? assetPath,
    String? filePath,
    Uint8List? modelBytes,
    List<String>? labels,
    YoloModelType? modelType,
    YoloHardwareDelegate? delegate,
    int? inputWidth,
    int? inputHeight,
    bool? isNCHW,
    double? defaultConfThreshold,
    double? defaultIouThreshold,
    int? numKeypoints,
    int? keypointDim,
    bool? isNmsFree,
    double? inputScale,
    int? inputZeroPoint,
  }) {
    return YoloModelConfig(
      modelId: modelId ?? this.modelId,
      assetPath: assetPath ?? this.assetPath,
      filePath: filePath ?? this.filePath,
      modelBytes: modelBytes ?? this.modelBytes,
      labels: labels ?? this.labels,
      modelType: modelType ?? this.modelType,
      delegate: delegate ?? this.delegate,
      inputWidth: inputWidth ?? this.inputWidth,
      inputHeight: inputHeight ?? this.inputHeight,
      isNCHW: isNCHW ?? this.isNCHW,
      defaultConfThreshold: defaultConfThreshold ?? this.defaultConfThreshold,
      defaultIouThreshold: defaultIouThreshold ?? this.defaultIouThreshold,
      numKeypoints: numKeypoints ?? this.numKeypoints,
      keypointDim: keypointDim ?? this.keypointDim,
      isNmsFree: isNmsFree ?? this.isNmsFree,
      inputScale: inputScale ?? this.inputScale,
      inputZeroPoint: inputZeroPoint ?? this.inputZeroPoint,
    );
  }
}
