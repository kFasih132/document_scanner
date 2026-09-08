import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/scanned_document.dart';

/// Production service providing Sauvola local adaptive binarization,
/// shadow/illumination compensation (Magic Color), and contrast enhancement.
/// All heavy transforms run off-thread via [compute] to preserve 60 FPS UI rendering.
class DocumentPostProcessingService {
  /// Applies [filter] to the image at [sourceImagePath] in a background isolate.
  /// Returns the absolute path of the newly saved processed image.
  Future<String?> applyFilter({
    required String sourceImagePath,
    required DocumentFilter filter,
  }) async {
    if (filter == DocumentFilter.original) {
      return sourceImagePath;
    }

    try {
      final file = File(sourceImagePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final appDir = await getApplicationDocumentsDirectory();
      final outputDir = Directory('${appDir.path}/doc_scanner_storage/filtered');
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final outPath = '${outputDir.path}/filtered_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final processedBytes = await compute(_filterWorker, {
        'bytes': bytes,
        'filter': filter.name,
      });

      if (processedBytes == null) return null;

      final outFile = File(outPath);
      await outFile.writeAsBytes(processedBytes);
      return outPath;
    } catch (e) {
      debugPrint('[DocumentPostProcessingService] error: $e');
      return null;
    }
  }

  /// Top-level worker running inside background isolate
  static Uint8List? _filterWorker(Map<String, dynamic> params) {
    final Uint8List rawBytes = params['bytes'] as Uint8List;
    final String filterName = params['filter'] as String;

    img.Image? image = img.decodeImage(rawBytes);
    if (image == null) return null;

    image = img.bakeOrientation(image);

    switch (filterName) {
      case 'blackAndWhite':
        image = _sauvolaBinarization(image);
        break;
      case 'magicColor':
        image = _flattenIlluminationAndEnhance(image);
        break;
      case 'grayscale':
        image = _enhanceGrayscale(image);
        break;
      default:
        break;
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }

  /// O(1) Sauvola Local Adaptive Thresholding using Integral Images.
  /// Converts shadowed and unevenly illuminated documents into crisp, pure black & white text.
  /// Formula: T(x, y) = m(x, y) * (1 + k * (s(x, y) / R - 1))
  static img.Image _sauvolaBinarization(
    img.Image src, {
    int windowSize = 25,
    double k = 0.20,
    double r = 128.0,
  }) {
    final w = src.width;
    final h = src.height;
    final halfWin = windowSize ~/ 2;

    // Convert to grayscale luminance array
    final lum = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      final rowOffset = y * w;
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        lum[rowOffset + x] = ((p.r * 299 + p.g * 587 + p.b * 114) ~/ 1000).clamp(0, 255);
      }
    }

    // Build Integral Image II and Integral Squared Image II2
    // II(x, y) = sum of all pixels (0,0) to (x,y)
    final int stride = w + 1;
    final ii = Float64List((w + 1) * (h + 1));
    final ii2 = Float64List((w + 1) * (h + 1));

    for (int y = 0; y < h; y++) {
      double rowSum = 0.0;
      double rowSumSq = 0.0;
      final lumRow = y * w;
      final iiRow = (y + 1) * stride;
      final prevIiRow = y * stride;

      for (int x = 0; x < w; x++) {
        final v = lum[lumRow + x].toDouble();
        rowSum += v;
        rowSumSq += v * v;

        ii[iiRow + x + 1] = ii[prevIiRow + x + 1] + rowSum;
        ii2[iiRow + x + 1] = ii2[prevIiRow + x + 1] + rowSumSq;
      }
    }

    final out = img.Image(width: w, height: h);

    // Apply Sauvola threshold per pixel in O(1)
    for (int y = 0; y < h; y++) {
      final y1 = math.max(0, y - halfWin);
      final y2 = math.min(h - 1, y + halfWin);
      final lumRow = y * w;

      for (int x = 0; x < w; x++) {
        final x1 = math.max(0, x - halfWin);
        final x2 = math.min(w - 1, x + halfWin);

        final area = (x2 - x1 + 1) * (y2 - y1 + 1);

        // O(1) sum calculation using 4 corners of integral image
        final sum = ii[(y2 + 1) * stride + (x2 + 1)] -
            ii[y1 * stride + (x2 + 1)] -
            ii[(y2 + 1) * stride + x1] +
            ii[y1 * stride + x1];

        final sumSq = ii2[(y2 + 1) * stride + (x2 + 1)] -
            ii2[y1 * stride + (x2 + 1)] -
            ii2[(y2 + 1) * stride + x1] +
            ii2[y1 * stride + x1];

        final mean = sum / area;
        final variance = (sumSq / area) - (mean * mean);
        final stdDev = variance > 0 ? math.sqrt(variance) : 0.0;

        // Sauvola formula
        final threshold = mean * (1.0 + k * ((stdDev / r) - 1.0));
        final pixelVal = lum[lumRow + x];

        final binaryVal = pixelVal < threshold ? 0 : 255;
        out.setPixelRgb(x, y, binaryVal, binaryVal, binaryVal);
      }
    }

    return out;
  }

  /// Illumination Compensation & Contrast Flattening (Magic Color).
  /// Removes hand/phone shadows by estimating background lighting and dividing pixel values.
  static img.Image _flattenIlluminationAndEnhance(img.Image src) {
    final w = src.width;
    final h = src.height;

    // 1. Create downsampled thumbnail to capture low-frequency illumination map
    const int thumbW = 160;
    final thumbH = math.max(1, (h * (thumbW / w)).round());
    final thumb = img.copyResize(src, width: thumbW, height: thumbH);

    // Apply strong blur on thumbnail to extract pure lighting gradient
    final blurredThumb = img.gaussianBlur(thumb, radius: 12);

    final out = img.Image(width: w, height: h);
    final xRatio = thumbW / w;
    final yRatio = thumbH / h;

    for (int y = 0; y < h; y++) {
      final ty = (y * yRatio).toInt().clamp(0, thumbH - 1);

      for (int x = 0; x < w; x++) {
        final tx = (x * xRatio).toInt().clamp(0, thumbW - 1);
        final orig = src.getPixel(x, y);
        final ill = blurredThumb.getPixel(tx, ty);

        // Normalize reflectance R = I / L
        final illLum = math.max(25, (ill.r * 299 + ill.g * 587 + ill.b * 114) ~/ 1000);

        final r = ((orig.r / illLum) * 235.0).round().clamp(0, 255);
        final g = ((orig.g / illLum) * 235.0).round().clamp(0, 255);
        final b = ((orig.b / illLum) * 235.0).round().clamp(0, 255);

        // Slightly stretch contrast for high readability
        out.setPixelRgb(x, y, r, g, b);
      }
    }

    return out;
  }

  /// High-contrast Grayscale
  static img.Image _enhanceGrayscale(img.Image src) {
    final grayscale = img.grayscale(src);
    return img.adjustColor(grayscale, contrast: 1.25, brightness: 1.05);
  }
}
