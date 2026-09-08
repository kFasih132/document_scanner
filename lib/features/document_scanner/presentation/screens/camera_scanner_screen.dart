import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive_layout.dart';
import '../../domain/models/scanned_document.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import '../widgets/batch_thumbnail_tray.dart';
import '../widgets/camera_controls_header.dart';
import '../widgets/camera_shutter_button.dart';
import '../widgets/camera_viewfinder.dart';
import 'document_preview_screen.dart';

class CameraScannerScreen extends StatefulWidget {
  const CameraScannerScreen({super.key});

  /// Safely disposes camera hardware and halts all YOLO predictions before
  /// displaying a full-screen image view (crop/preview), then cleanly re-initializes
  /// the camera and resumes predictions upon return.
  static Future<void> openFullScreenView(
    BuildContext context,
    Widget destinationScreen,
  ) async {
    final bloc = context.read<ScannerBloc>();
    // Halt YOLO predictions and release camera hardware
    bloc.add(const DisposeCameraEvent());

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => destinationScreen),
    );

    // ONLY re-initialize camera if the CameraScannerScreen route is STILL ACTIVE at the top of the stack!
    if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
      bloc.add(const InitializeCameraEvent());
    }
  }

  @override
  State<CameraScannerScreen> createState() => _CameraScannerScreenState();
}

class _CameraScannerScreenState extends State<CameraScannerScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize hardware camera when entering screen
    context.read<ScannerBloc>().add(const InitializeCameraEvent());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Release hardware camera immediately upon leaving screen
    context.read<ScannerBloc>().add(const DisposeCameraEvent());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (!mounted) return;
    final bloc = context.read<ScannerBloc>();
    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused) {
      bloc.add(const DisposeCameraEvent());
    } else if (lifecycleState == AppLifecycleState.resumed) {
      bloc.add(const InitializeCameraEvent());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        // Cleanly release hardware camera and halt predictions on pop
        context.read<ScannerBloc>().add(const DisposeCameraEvent());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: BlocConsumer<ScannerBloc, ScannerState>(
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            }
          },
          builder: (context, state) {
            final bloc = context.read<ScannerBloc>();

            return ResponsiveLayout(
              mobile: MobileCameraLayout(state: state, bloc: bloc),
              tablet7Inch: TabletCameraLayout(state: state, bloc: bloc),
              tablet10Inch: TabletCameraLayout(state: state, bloc: bloc),
            );
          },
        ),
      ),
    );
  }
}

class MobileCameraLayout extends StatelessWidget {
  final ScannerState state;
  final ScannerBloc bloc;

  const MobileCameraLayout({
    super.key,
    required this.state,
    required this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Camera Viewfinder (Main Area)
        Positioned.fill(
          child: CameraViewfinder(
            controller: bloc.cameraController,
            isInitialized: state.isCameraInitialized,
            statusMessage: state.statusMessage ?? 'Align document',
            liveCornersList: state.liveDetectedCornersList,
            liveCorners: state.liveDetectedCorners,
            isLocked: state.isDocumentLocked,
            lockProgress: state.autoCaptureProgress,
          ),
        ),

        // Top Controls Header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: CameraControlsHeader(
            isFlashOn: state.isFlashOn,
            isAutoCapture: state.isAutoCaptureEnabled,
            activeModel: state.activeModel,
            onSelectModel: (model) => bloc.add(SwitchScannerModelEvent(model)),
            isModelLoading: !state.isModelLoaded,
            onClose: () {
              bloc.add(const DisposeCameraEvent());
              Navigator.pop(context);
            },
            onToggleFlash: () => bloc.add(const ToggleFlashEvent()),
            onToggleAutoCapture: () => bloc.add(const ToggleAutoCaptureEvent()),
          ),
        ),

        // Status & Guidance Badge — Positioned safely BELOW Top Controls Header
        Positioned(
          top: MediaQuery.of(context).padding.top + 64,
          left: AppSpacing.md,
          right: AppSpacing.md,
          child: Center(
            child: ViewfinderStatusBadge(
              message: state.statusMessage ?? 'Align document within borders',
              isLocked: state.isDocumentLocked,
            ),
          ),
        ),

        // Bottom Controls Container
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: MobileBottomBar(state: state, bloc: bloc),
        ),
      ],
    );
  }
}

class MobileBottomBar extends StatelessWidget {
  final ScannerState state;
  final ScannerBloc bloc;

  const MobileBottomBar({super.key, required this.state, required this.bloc});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black, Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Batch captured thumbnails tray
            if (state.capturedPages.isNotEmpty) ...[
              BatchThumbnailTray(
                pages: state.capturedPages,
                onPageTapped: (index) {
                  bloc.add(SelectPageForEditingEvent(index));
                  CameraScannerScreen.openFullScreenView(
                    context,
                    DocumentPreviewScreen(initialPageIndex: index),
                  );
                },
                onReviewAll: () {
                  CameraScannerScreen.openFullScreenView(
                    context,
                    const DocumentPreviewScreen(initialPageIndex: 0),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            // Capture Shutter Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Recent Captured Thumbnail Preview Button
                  RecentCaptureThumbnailButton(
                    lastPage: state.capturedPages.isNotEmpty
                        ? state.capturedPages.last
                        : null,
                    pageCount: state.pageCount,
                    onTap: () {
                      if (state.capturedPages.isNotEmpty) {
                        final lastIdx = state.capturedPages.length - 1;
                        bloc.add(SelectPageForEditingEvent(lastIdx));
                        CameraScannerScreen.openFullScreenView(
                          context,
                          DocumentPreviewScreen(initialPageIndex: lastIdx),
                        );
                      }
                    },
                  ),

                  // Shutter Button
                  CameraShutterButton(
                    isCapturing: state.status == ScannerStatus.capturing,
                    pageCount: state.pageCount,
                    onCapture: () => bloc.add(const CapturePageEvent()),
                  ),

                  // Finish / Proceed Button
                  CameraProceedButton(
                    enabled: state.capturedPages.isNotEmpty,
                    onPressed: () {
                      CameraScannerScreen.openFullScreenView(
                        context,
                        const DocumentPreviewScreen(initialPageIndex: 0),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class TabletCameraLayout extends StatelessWidget {
  final ScannerState state;
  final ScannerBloc bloc;

  const TabletCameraLayout({
    super.key,
    required this.state,
    required this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Main Viewfinder Area
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              Positioned.fill(
                child: CameraViewfinder(
                  controller: bloc.cameraController,
                  isInitialized: state.isCameraInitialized,
                  statusMessage: state.statusMessage ?? 'Align document',
                  liveCornersList: state.liveDetectedCornersList,
                  liveCorners: state.liveDetectedCorners,
                  isLocked: state.isDocumentLocked,
                  lockProgress: state.autoCaptureProgress,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: CameraControlsHeader(
                  isFlashOn: state.isFlashOn,
                  isAutoCapture: state.isAutoCaptureEnabled,
                  activeModel: state.activeModel,
                  onSelectModel: (model) =>
                      bloc.add(SwitchScannerModelEvent(model)),
                  isModelLoading: !state.isModelLoaded,
                  onClose: () {
                    bloc.add(const DisposeCameraEvent());
                    Navigator.pop(context);
                  },
                  onToggleFlash: () => bloc.add(const ToggleFlashEvent()),
                  onToggleAutoCapture: () =>
                      bloc.add(const ToggleAutoCaptureEvent()),
                ),
              ),
              // Prominent Status & Guidance Badge — Positioned safely BELOW Top Controls Header
              Positioned(
                top: MediaQuery.of(context).padding.top + 64,
                left: AppSpacing.md,
                right: AppSpacing.md,
                child: Center(
                  child: ViewfinderStatusBadge(
                    message: state.statusMessage ?? 'Align document within borders',
                    isLocked: state.isDocumentLocked,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Tablet Dedicated Side Control Panel
        Expanded(
          flex: 1,
          child: Container(
            color: AppColors.darkSurfaceContainer,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.lg,
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const Icon(
                    Icons.document_scanner_rounded,
                    size: 40,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Document Scan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const Spacer(),

                  // Shutter
                  CameraShutterButton(
                    isCapturing: state.status == ScannerStatus.capturing,
                    pageCount: state.pageCount,
                    onCapture: () => bloc.add(const CapturePageEvent()),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Finish Button
                  if (state.capturedPages.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () {
                        CameraScannerScreen.openFullScreenView(
                          context,
                          const DocumentPreviewScreen(initialPageIndex: 0),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.scannerLaser,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(48),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppSpacing.roundedMd,
                        ),
                      ),
                      icon: const Icon(Icons.check_rounded),
                      label: Text('Review (${state.pageCount})'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RecentCaptureThumbnailButton extends StatelessWidget {
  final ScannedPage? lastPage;
  final int pageCount;
  final VoidCallback onTap;

  const RecentCaptureThumbnailButton({
    super.key,
    required this.lastPage,
    required this.pageCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (lastPage == null) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 2),
        ),
      );
    }

    final bool isLocalFile = File(lastPage!.imagePath).existsSync();

    return Tooltip(
      message: 'View scanned pages ($pageCount)',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: AppSpacing.roundedFull,
                child: isLocalFile
                    ? Image.file(File(lastPage!.imagePath), fit: BoxFit.cover)
                    : Container(
                        color: Colors.white24,
                        child: const Icon(
                          Icons.article_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
              ),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$pageCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CameraProceedButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const CameraProceedButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Proceed to review',
      child: Material(
        color: enabled ? Colors.white : Colors.white12,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: enabled ? Colors.black : Colors.white24,
              size: AppSpacing.iconMd,
            ),
          ),
        ),
      ),
    );
  }
}
