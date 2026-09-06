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
      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint(
          'ImageCropService: Failed to decode image: $sourceImagePath',
        );
        return null;
      }

      // Bake EXIF orientation so pixel coordinates match the visual display.
      decoded = img.bakeOrientation(decoded);

      final srcW = decoded.width.toDouble();
      final srcH = decoded.height.toDouble();

      // Convert normalised corners to pixel coordinates.
      final p0 = Offset(topLeft.dx * srcW, topLeft.dy * srcH); // TL
      final p1 = Offset(topRight.dx * srcW, topRight.dy * srcH); // TR
      final p2 = Offset(bottomRight.dx * srcW, bottomRight.dy * srcH); // BR
      final p3 = Offset(bottomLeft.dx * srcW, bottomLeft.dy * srcH); // BL

      // Determine output size: average of the four side lengths.
      final topWidth = (p1 - p0).distance;
      final bottomWidth = (p2 - p3).distance;
      final leftHeight = (p3 - p0).distance;
      final rightHeight = (p2 - p1).distance;

      final outW =
          math.max(1, ((topWidth + bottomWidth) / 2).round());
      final outH =
          math.max(1, ((leftHeight + rightHeight) / 2).round());

      // Compute the 3×3 perspective homography matrix H that maps each
      // destination pixel (dx, dy) → source pixel (sx, sy).
      // We solve using the Direct Linear Transform on the 4 corner correspondences.
      final h = _computeHomography(
        srcPoints: [p0, p1, p2, p3],
        dstW: outW.toDouble(),
        dstH: outH.toDouble(),
      );

      // Allocate output image and fill via inverse mapping.
      final output = img.Image(width: outW, height: outH);

      for (int dy = 0; dy < outH; dy++) {
        for (int dx = 0; dx < outW; dx++) {
          // Apply H to get the source coordinates.
          final src = _applyHomography(h, dx.toDouble(), dy.toDouble());
          final sx = src.dx;
          final sy = src.dy;

          if (sx < 0 || sy < 0 || sx >= srcW || sy >= srcH) {
            output.setPixelRgba(dx, dy, 255, 255, 255, 255);
            continue;
          }

          // Bilinear interpolation for smooth output.
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

      // Apply any additional rotation requested by the user.
      img.Image result = output;
      if (rotationDegrees % 360 != 0) {
        result = img.copyRotate(result, angle: rotationDegrees.toDouble());
      }

      // Encode to high-quality JPEG.
      final croppedBytes = img.encodeJpg(result, quality: 92);

      // Persist to the app's private documents directory.
      final appDir = await getApplicationDocumentsDirectory();
      final croppedDir =
          Directory('${appDir.path}/doc_scanner_storage/cropped');
      if (!await croppedDir.exists()) {
        await croppedDir.create(recursive: true);
      }

      final fileName = 'cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final croppedFile = File('${croppedDir.path}/$fileName');
      await croppedFile.writeAsBytes(croppedBytes);

      debugPrint(
        'ImageCropService: cropped → ${croppedFile.path} '
        '(${outW}x$outH from ${srcW.toInt()}x${srcH.toInt()})',
      );
      return croppedFile.path;
    } catch (e, stack) {
      debugPrint('ImageCropService error: $e\n$stack');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Perspective homography helpers
  // ---------------------------------------------------------------------------

  /// Computes the 3×3 homography matrix H (stored as a flat 9-element list)
  /// mapping destination rectangle [0,dstW] × [0,dstH] → source quad
  /// [p0=TL, p1=TR, p2=BR, p3=BL].
  ///
  /// Uses the standard 8-DOF DLT formulation and solves with Gaussian
  /// elimination (no external linear-algebra library required).
  List<double> _computeHomography({
    required List<Offset> srcPoints, // [TL, TR, BR, BL] in source pixels
    required double dstW,
    required double dstH,
  }) {
    // Destination corners corresponding to src[0..3]:
    //   dst TL = (0,    0   )
    //   dst TR = (dstW, 0   )
    //   dst BR = (dstW, dstH)
    //   dst BL = (0,    dstH)
    final dstPts = [
      Offset(0, 0),
      Offset(dstW, 0),
      Offset(dstW, dstH),
      Offset(0, dstH),
    ];

    // Build 8×8 system A·h = b  (8 unknowns, h8 = 1 normalised).
    final A = List.generate(8, (_) => List<double>.filled(8, 0.0));
    final bVec = List<double>.filled(8, 0.0);

    for (int i = 0; i < 4; i++) {
      final sx = srcPoints[i].dx;
      final sy = srcPoints[i].dy;
      final dx = dstPts[i].dx;
      final dy = dstPts[i].dy;

      // Row 2i:   sx = (h0·dx + h1·dy + h2) / (h6·dx + h7·dy + 1)
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
    // Append the normalisation constant h8 = 1.
    return [...h, 1.0];
  }

  /// Applies homography H to a destination point (dx, dy) and returns the
  /// corresponding source point.
  Offset _applyHomography(List<double> h, double dx, double dy) {
    final w = h[6] * dx + h[7] * dy + h[8];
    if (w.abs() < 1e-10) return const Offset(0, 0);
    final sx = (h[0] * dx + h[1] * dy + h[2]) / w;
    final sy = (h[3] * dx + h[4] * dy + h[5]) / w;
    return Offset(sx, sy);
  }

  /// Solves A·x = b via partial-pivot Gaussian elimination.
  /// Returns the 8-element solution vector.
  List<double> _gaussianElimination(
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
