import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Service responsible for performing physical image cropping and perspective
/// warp transformations on scanned document pages.
///
/// For quad crops the service computes a perspective transform (homography)
/// so that skewed / diagonal document shapes are correctly rectified into a
/// flat rectangle — rather than just cutting an axis-aligned bounding box.
class ImageCropService {
  /// Crops and perspective-warps an image file based on normalized quad corners
  /// (each value in the 0.0–1.0 range relative to the image dimensions).
  ///
  /// Returns the absolute path of the newly created output image file, or
  /// `null` on failure.
  Future<String?> cropImage({
    required String sourceImagePath,
    required Offset topLeft,
    required Offset topRight,
    required Offset bottomRight,
    required Offset bottomLeft,
    int rotationDegrees = 0,
  }) async {
    try {
      final sourceFile = File(sourceImagePath);
      if (!await sourceFile.exists()) {
        debugPrint(
          'ImageCropService: Source image does not exist: $sourceImagePath',
        );
        return null;
      }

      final bytes = await sourceFile.readAsBytes();
      final appDir = await getApplicationDocumentsDirectory();
      final croppedDir = Directory('${appDir.path}/doc_scanner_storage/cropped');
      if (!await croppedDir.exists()) {
        await croppedDir.create(recursive: true);
      }

      final fileName = 'cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final croppedFile = File('${croppedDir.path}/$fileName');

      // Execute heavy perspective warp and bilinear sampling in background isolate
      final croppedBytes = await compute(_warpWorker, {
        'bytes': bytes,
        'tl_dx': topLeft.dx,
        'tl_dy': topLeft.dy,
        'tr_dx': topRight.dx,
        'tr_dy': topRight.dy,
        'br_dx': bottomRight.dx,
        'br_dy': bottomRight.dy,
        'bl_dx': bottomLeft.dx,
        'bl_dy': bottomLeft.dy,
        'rotation': rotationDegrees,
      });

      if (croppedBytes == null) return null;

      await croppedFile.writeAsBytes(croppedBytes);
      debugPrint('ImageCropService: cropped successfully → ${croppedFile.path}');
      return croppedFile.path;
    } catch (e, stack) {
      debugPrint('ImageCropService error: $e\n$stack');
      return null;
    }
  }

  static Uint8List? _warpWorker(Map<String, dynamic> params) {
    final Uint8List rawBytes = params['bytes'] as Uint8List;
    final double tlDx = params['tl_dx'] as double;
    final double tlDy = params['tl_dy'] as double;
    final double trDx = params['tr_dx'] as double;
    final double trDy = params['tr_dy'] as double;
    final double brDx = params['br_dx'] as double;
    final double brDy = params['br_dy'] as double;
    final double blDx = params['bl_dx'] as double;
    final double blDy = params['bl_dy'] as double;
    final int rotationDegrees = params['rotation'] as int;

    img.Image? decoded = img.decodeImage(rawBytes);
    if (decoded == null) return null;

    // Do NOT rotate before crop: crop directly on the native frame coordinates
    final srcW = decoded.width.toDouble();
    final srcH = decoded.height.toDouble();

    final p0 = Offset(tlDx * srcW, tlDy * srcH); // TL
    final p1 = Offset(trDx * srcW, trDy * srcH); // TR
    final p2 = Offset(brDx * srcW, brDy * srcH); // BR
    final p3 = Offset(blDx * srcW, blDy * srcH); // BL

    final topWidth = (p1 - p0).distance;
    final bottomWidth = (p2 - p3).distance;
    final leftHeight = (p3 - p0).distance;
    final rightHeight = (p2 - p1).distance;

    final outW = math.max(1, ((topWidth + bottomWidth) / 2).round());
    final outH = math.max(1, ((leftHeight + rightHeight) / 2).round());

    final h = _computeHomography(
      srcPoints: [p0, p1, p2, p3],
      dstW: outW.toDouble(),
      dstH: outH.toDouble(),
    );

    final output = img.Image(width: outW, height: outH);

    for (int dy = 0; dy < outH; dy++) {
      for (int dx = 0; dx < outW; dx++) {
        final src = _applyHomography(h, dx.toDouble(), dy.toDouble());
        final sx = src.dx;
        final sy = src.dy;

        if (sx < 0 || sy < 0 || sx >= srcW || sy >= srcH) {
          output.setPixelRgba(dx, dy, 255, 255, 255, 255);
          continue;
        }

        final x0 = sx.floor().clamp(0, decoded.width - 1);
        final y0 = sy.floor().clamp(0, decoded.height - 1);
        final x1 = (x0 + 1).clamp(0, decoded.width - 1);
        final y1 = (y0 + 1).clamp(0, decoded.height - 1);
        final fx = sx - x0;
        final fy = sy - y0;

        final c00 = decoded.getPixel(x0, y0);
        final c10 = decoded.getPixel(x1, y0);
        final c01 = decoded.getPixel(x0, y1);
        final c11 = decoded.getPixel(x1, y1);

        int lerpChannel(num a, num b, double t) =>
            (a + (b - a) * t).round().clamp(0, 255);

        final r = lerpChannel(
          lerpChannel(c00.r, c10.r, fx),
          lerpChannel(c01.r, c11.r, fx),
          fy,
        );
        final g = lerpChannel(
          lerpChannel(c00.g, c10.g, fx),
          lerpChannel(c01.g, c11.g, fx),
          fy,
        );
        final b = lerpChannel(
          lerpChannel(c00.b, c10.b, fx),
          lerpChannel(c01.b, c11.b, fx),
          fy,
        );

        output.setPixelRgba(dx, dy, r, g, b, 255);
      }
    }

    img.Image result = output;
    if (rotationDegrees % 360 != 0) {
      result = img.copyRotate(result, angle: rotationDegrees.toDouble());
    }

    return Uint8List.fromList(img.encodeJpg(result, quality: 92));
  }

  // ---------------------------------------------------------------------------
  // Perspective homography helpers
  // ---------------------------------------------------------------------------

  /// Computes the 3×3 homography matrix H (stored as a flat 9-element list)
  /// mapping destination rectangle [0,dstW] × [0,dstH] → source quad
  /// [p0=TL, p1=TR, p2=BR, p3=BL].
  static List<double> _computeHomography({
    required List<Offset> srcPoints, // [TL, TR, BR, BL] in source pixels
    required double dstW,
    required double dstH,
  }) {
    final dstPts = [
      const Offset(0, 0),
      Offset(dstW, 0),
      Offset(dstW, dstH),
      Offset(0, dstH),
    ];

    // Build 8×8 system A·h = b (8 unknowns, h8 = 1 normalised).
    final A = List.generate(8, (_) => List<double>.filled(8, 0.0));
    final bVec = List<double>.filled(8, 0.0);

    for (int i = 0; i < 4; i++) {
      final sx = srcPoints[i].dx;
      final sy = srcPoints[i].dy;
      final dx = dstPts[i].dx;
      final dy = dstPts[i].dy;

      // Row 2i: sx = (h0·dx + h1·dy + h2) / (h6·dx + h7·dy + 1)
      A[2 * i][0] = dx;
      A[2 * i][1] = dy;
      A[2 * i][2] = 1;
      A[2 * i][3] = 0;
      A[2 * i][4] = 0;
      A[2 * i][5] = 0;
      A[2 * i][6] = -sx * dx;
      A[2 * i][7] = -sx * dy;
      bVec[2 * i] = sx;

      // Row 2i+1: sy = (h3·dx + h4·dy + h5) / (h6·dx + h7·dy + 1)
      A[2 * i + 1][0] = 0;
      A[2 * i + 1][1] = 0;
      A[2 * i + 1][2] = 0;
      A[2 * i + 1][3] = dx;
      A[2 * i + 1][4] = dy;
      A[2 * i + 1][5] = 1;
      A[2 * i + 1][6] = -sy * dx;
      A[2 * i + 1][7] = -sy * dy;
      bVec[2 * i + 1] = sy;
    }

    final h = _gaussianElimination(A, bVec);
    return [...h, 1.0];
  }

  /// Applies homography H to a destination point (dx, dy) and returns the source point.
  static Offset _applyHomography(List<double> h, double dx, double dy) {
    final w = h[6] * dx + h[7] * dy + h[8];
    if (w.abs() < 1e-10) return const Offset(0, 0);
    final sx = (h[0] * dx + h[1] * dy + h[2]) / w;
    final sy = (h[3] * dx + h[4] * dy + h[5]) / w;
    return Offset(sx, sy);
  }

  /// Solves A·x = b via partial-pivot Gaussian elimination.
  static List<double> _gaussianElimination(
    List<List<double>> A,
    List<double> b,
  ) {
    final n = b.length;
    // Augmented matrix [A | b].
    final m = List.generate(
      n,
      (i) => [...A[i], b[i]],
    );

    for (int col = 0; col < n; col++) {
      // Partial pivot.
      int maxRow = col;
      double maxVal = m[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        if (m[row][col].abs() > maxVal) {
          maxVal = m[row][col].abs();
          maxRow = row;
        }
      }
      final tmp = m[col];
      m[col] = m[maxRow];
      m[maxRow] = tmp;

      if (m[col][col].abs() < 1e-12) continue; // Singular / near-singular

      for (int row = col + 1; row < n; row++) {
        final factor = m[row][col] / m[col][col];
        for (int k = col; k <= n; k++) {
          m[row][k] -= factor * m[col][k];
        }
      }
    }

    // Back-substitution.
    final x = List<double>.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      if (m[i][i].abs() < 1e-12) continue;
      x[i] = m[i][n];
      for (int j = i + 1; j < n; j++) {
        x[i] -= m[i][j] * x[j];
      }
      x[i] /= m[i][i];
    }
    return x;
  }
}
