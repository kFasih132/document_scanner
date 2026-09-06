import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/scanned_document.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import 'document_preview_screen.dart';

class DocumentCropScreen extends StatefulWidget {
  const DocumentCropScreen({super.key});

  @override
  State<DocumentCropScreen> createState() => _DocumentCropScreenState();
}

class _DocumentCropScreenState extends State<DocumentCropScreen> {
  // Local quad offsets in normalized coordinates (0.0 to 1.0)
  Offset _tl = const Offset(0.08, 0.12);
  Offset _tr = const Offset(0.92, 0.12);
  Offset _br = const Offset(0.92, 0.88);
  Offset _bl = const Offset(0.08, 0.88);

  Size _imagePixelSize = const Size(3, 4);
  bool _isLoadingSize = true;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<ScannerBloc>().state;
    if (state.currentPage != null) {
      _tl = state.currentPage!.cropCorners.topLeft;
      _tr = state.currentPage!.cropCorners.topRight;
      _br = state.currentPage!.cropCorners.bottomRight;
      _bl = state.currentPage!.cropCorners.bottomLeft;
      _loadImageSize(state.currentPage!.imagePath);
    }
  }

  Future<void> _loadImageSize(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final decoded = await decodeImageFromList(bytes);
        if (mounted) {
          setState(() {
            _imagePixelSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
            _isLoadingSize = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Error loading image dimensions: $e');
    }
    if (mounted) {
      setState(() => _isLoadingSize = false);
    }
  }

  void _onCornerDrag(CornerType corner, Offset normalizedDelta, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    setState(() {
      final dx = normalizedDelta.dx / size.width;
      final dy = normalizedDelta.dy / size.height;

      switch (corner) {
        case CornerType.topLeft:
          _tl = Offset(
            (_tl.dx + dx).clamp(0.0, _tr.dx - 0.05),
            (_tl.dy + dy).clamp(0.0, _bl.dy - 0.05),
          );
          break;
        case CornerType.topRight:
          _tr = Offset(
            (_tr.dx + dx).clamp(_tl.dx + 0.05, 1.0),
            (_tr.dy + dy).clamp(0.0, _br.dy - 0.05),
          );
          break;
        case CornerType.bottomRight:
          _br = Offset(
            (_br.dx + dx).clamp(_bl.dx + 0.05, 1.0),
            (_br.dy + dy).clamp(_tr.dy + 0.05, 1.0),
          );
          break;
        case CornerType.bottomLeft:
          _bl = Offset(
            (_bl.dx + dx).clamp(0.0, _br.dx - 0.05),
            (_bl.dy + dy).clamp(_tl.dy + 0.05, 1.0),
          );
          break;
      }
    });
  }

  void _resetCorners() {
    setState(() {
      _tl = const Offset(0.05, 0.05);
      _tr = const Offset(0.95, 0.05);
      _br = const Offset(0.95, 0.95);
      _bl = const Offset(0.05, 0.95);
    });
  }

  void _saveAndProceed() {
    if (_isCropping) return;
    setState(() => _isCropping = true);
    context.read<ScannerBloc>().add(
          ApplyCropEvent(
            topLeft: _tl,
            topRight: _tr,
            bottomRight: _br,
            bottomLeft: _bl,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Adjust Border'),
        actions: [
          TextButton(
            onPressed: _isCropping ? null : _resetCorners,
            child: const Text(
              'Reset',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: BlocConsumer<ScannerBloc, ScannerState>(
        listener: (context, state) {
          // Navigate back only when a crop has just successfully completed
          if (state.status == ScannerStatus.cropSuccess) {
            setState(() => _isCropping = false);
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const DocumentPreviewScreen(),
                ),
              );
            }
          } else if (state.errorMessage != null && _isCropping) {
            setState(() => _isCropping = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!)),
            );
          }
        },
        builder: (context, state) {
          final page = state.currentPage;
          if (page == null) {
            return const Center(
              child: Text(
                'No page selected',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final bool isRotatedLandscape = (page.rotationDegrees % 180 != 0);
          final double imageAspect = (_imagePixelSize.width > 0 && _imagePixelSize.height > 0)
              ? (isRotatedLandscape
                  ? (_imagePixelSize.height / _imagePixelSize.width)
                  : (_imagePixelSize.width / _imagePixelSize.height))
              : (3 / 4);

          return Stack(
            children: [
              Column(
                children: [
                  // Interactive Canvas Area constrained precisely to image aspect ratio
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: _isLoadingSize
                          ? const Center(child: CircularProgressIndicator(color: Colors.white))
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                return Center(
                                  child: AspectRatio(
                                    aspectRatio: imageAspect,
                                    child: LayoutBuilder(
                                      builder: (context, imageBoxConstraints) {
                                        final canvasSize = Size(
                                          imageBoxConstraints.maxWidth,
                                          imageBoxConstraints.maxHeight,
                                        );

                                        return Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            // Base Image
                                            Positioned.fill(
                                              child: CropImageCanvas(page: page),
                                            ),

                                            // Custom Painter Polygon & Shading
                                            Positioned.fill(
                                              child: CustomPaint(
                                                painter: CropQuadPainter(
                                                  topLeft: _tl,
                                                  topRight: _tr,
                                                  bottomRight: _br,
                                                  bottomLeft: _bl,
                                                ),
                                              ),
                                            ),

                                            // 4 Interactive Drag Handles
                                            DraggableCornerHandle(
                                              normalizedPos: _tl,
                                              corner: CornerType.topLeft,
                                              canvasSize: canvasSize,
                                              onDrag: (delta) => _onCornerDrag(
                                                CornerType.topLeft,
                                                delta,
                                                canvasSize,
                                              ),
                                            ),
                                            DraggableCornerHandle(
                                              normalizedPos: _tr,
                                              corner: CornerType.topRight,
                                              canvasSize: canvasSize,
                                              onDrag: (delta) => _onCornerDrag(
                                                CornerType.topRight,
                                                delta,
                                                canvasSize,
                                              ),
                                            ),
                                            DraggableCornerHandle(
                                              normalizedPos: _br,
                                              corner: CornerType.bottomRight,
                                              canvasSize: canvasSize,
                                              onDrag: (delta) => _onCornerDrag(
                                                CornerType.bottomRight,
                                                delta,
                                                canvasSize,
                                              ),
                                            ),
                                            DraggableCornerHandle(
                                              normalizedPos: _bl,
                                              corner: CornerType.bottomLeft,
                                              canvasSize: canvasSize,
                                              onDrag: (delta) => _onCornerDrag(
                                                CornerType.bottomLeft,
                                                delta,
                                                canvasSize,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),

                  // Bottom Action Bar
                  CropBottomToolbar(
                    onRotate: () => context.read<ScannerBloc>().add(const RotatePageEvent()),
                    onConfirm: _saveAndProceed,
                    theme: theme,
                  ),
                ],
              ),

              // Loading overlay when crop is computing
              if (_isCropping)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: AppSpacing.md),
                        Text(
                          'Cropping image...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class CropImageCanvas extends StatelessWidget {
  final ScannedPage page;

  const CropImageCanvas({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    final bool isLocal = File(page.imagePath).existsSync();

    return RotatedBox(
      quarterTurns: (page.rotationDegrees ~/ 90),
      child: isLocal
          ? Image.file(
              File(page.imagePath),
              fit: BoxFit.fill,
            )
          : Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: AppSpacing.roundedMd,
                border: Border.all(color: Colors.white24),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.document_scanner, size: 64, color: Colors.white38),
                    SizedBox(height: AppSpacing.sm),
                    Text(
                      'Document Preview',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class DraggableCornerHandle extends StatelessWidget {
  final Offset normalizedPos;
  final CornerType corner;
  final Size canvasSize;
  final ValueChanged<Offset> onDrag;

  const DraggableCornerHandle({
    super.key,
    required this.normalizedPos,
    required this.corner,
    required this.canvasSize,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    final pixelX = normalizedPos.dx * canvasSize.width;
    final pixelY = normalizedPos.dy * canvasSize.height;

    return Positioned(
      left: pixelX - 22,
      top: pixelY - 22,
      child: GestureDetector(
        onPanUpdate: (details) => onDrag(details.delta),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CropQuadPainter extends CustomPainter {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  CropQuadPainter({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Offset(topLeft.dx * size.width, topLeft.dy * size.height);
    final p2 = Offset(topRight.dx * size.width, topRight.dy * size.height);
    final p3 = Offset(bottomRight.dx * size.width, bottomRight.dy * size.height);
    final p4 = Offset(bottomLeft.dx * size.width, bottomLeft.dy * size.height);

    // Scrim overlay around selected quad
    final bgPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final quadPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    final overlayPath = Path.combine(PathOperation.difference, bgPath, quadPath);
    canvas.drawPath(
      overlayPath,
      Paint()..color = AppColors.cropOverlayScrim,
    );

    // Border line
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(quadPath, borderPaint);

    // 3x3 Grid inside the quad
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 2; i++) {
      final t = i / 3.0;
      final topPt = Offset.lerp(p1, p2, t)!;
      final bottomPt = Offset.lerp(p4, p3, t)!;
      canvas.drawLine(topPt, bottomPt, gridPaint);

      final leftPt = Offset.lerp(p1, p4, t)!;
      final rightPt = Offset.lerp(p2, p3, t)!;
      canvas.drawLine(leftPt, rightPt, gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CropQuadPainter oldDelegate) =>
      oldDelegate.topLeft != topLeft ||
      oldDelegate.topRight != topRight ||
      oldDelegate.bottomRight != bottomRight ||
      oldDelegate.bottomLeft != bottomLeft;
}

class CropBottomToolbar extends StatelessWidget {
  final VoidCallback onRotate;
  final VoidCallback onConfirm;
  final ThemeData theme;

  const CropBottomToolbar({
    super.key,
    required this.onRotate,
    required this.onConfirm,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: onRotate,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
              icon: const Icon(Icons.rotate_right_rounded),
              label: const Text('Rotate'),
            ),
            FilledButton.icon(
              onPressed: onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text(
                'Done',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
