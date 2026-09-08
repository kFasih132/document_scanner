import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// High-performance, zero-GC tensor converter for live camera streams.
/// Transforms raw Android YUV420_888 planes or iOS BGRA8888 buffers directly
/// into normalized [0.0 - 1.0] Float32List tensors without creating intermediate
/// Dart Image objects or nested list allocations.
class FastTensorConverter {
  /// Converts raw frame planes directly to a contiguous Float32List buffer.
  ///
  /// Output buffer size:
  /// - `targetW * targetH * 3` floats.
  ///
  /// Format:
  /// - If [isNCHW] is true: Channel-first [R plane, G plane, B plane].
  /// - If [isNCHW] is false: Channel-last [R, G, B, R, G, B, ...].
  static Float32List frameToFloat32Buffer({
    required Uint8List yPlaneBytes,
    Uint8List? uPlaneBytes,
    Uint8List? vPlaneBytes,
    Uint8List? bgraBytes,
    required int srcW,
    required int srcH,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required bool isYuv,
    required int targetW,
    required int targetH,
    required bool isNCHW,
    int rotationDegrees = 0,
    Float32List? reusableBuffer,
  }) {
    final totalFloats = targetW * targetH * 3;
    final out = (reusableBuffer != null && reusableBuffer.length == totalFloats)
        ? reusableBuffer
        : Float32List(totalFloats);

    final isRotated90 = rotationDegrees == 90;
    final isRotated270 = rotationDegrees == 270;
    final isRotated180 = rotationDegrees == 180;
    final isAnyRotation = isRotated90 || isRotated270 || isRotated180;

    final double xRatio;
    final double yRatio;
    if (isRotated90 || isRotated270) {
      xRatio = srcW / targetH;
      yRatio = srcH / targetW;
    } else {
      xRatio = srcW / targetW;
      yRatio = srcH / targetH;
    }
    final channelSize = targetW * targetH;

    if (isYuv && uPlaneBytes != null && vPlaneBytes != null) {
      final uBytes = uPlaneBytes;
      final vBytes = vPlaneBytes;

      for (int y = 0; y < targetH; y++) {
        final yRowIndex = y * targetW;
        final preSrcX90 = (y * xRatio).toInt().clamp(0, srcW - 1);
        final preSrcY0 = !isAnyRotation ? (y * yRatio).toInt().clamp(0, srcH - 1) : 0;
        final preRowOffset0 = preSrcY0 * yRowStride;
        final preUvOffset0 = (preSrcY0 >> 1) * uvRowStride;

        for (int x = 0; x < targetW; x++) {
          final int srcX;
          final int srcY;
          final int yOffset;
          final int uvOffset;

          if (isRotated90) {
            srcX = preSrcX90;
            srcY = ((targetW - 1 - x) * yRatio).toInt().clamp(0, srcH - 1);
            yOffset = srcY * yRowStride;
            uvOffset = (srcY >> 1) * uvRowStride;
          } else if (!isAnyRotation) {
            srcX = (x * xRatio).toInt().clamp(0, srcW - 1);
            srcY = preSrcY0;
            yOffset = preRowOffset0;
            uvOffset = preUvOffset0;
          } else if (isRotated270) {
            srcX = ((targetH - 1 - y) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = (x * yRatio).toInt().clamp(0, srcH - 1);
            yOffset = srcY * yRowStride;
            uvOffset = (srcY >> 1) * uvRowStride;
          } else {
            srcX = ((targetW - 1 - x) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = ((targetH - 1 - y) * yRatio).toInt().clamp(0, srcH - 1);
            yOffset = srcY * yRowStride;
            uvOffset = (srcY >> 1) * uvRowStride;
          }

          final uvIndex = uvOffset + (srcX >> 1) * uvPixelStride;

          final yVal = yPlaneBytes[yOffset + srcX];
          final uVal = uBytes[uvIndex];
          final vVal = vBytes[uvIndex];

          final c = yVal - 16;
          final d = uVal - 128;
          final e = vVal - 128;

          final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255) / 255.0;
          final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255) / 255.0;
          final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255) / 255.0;

          if (isNCHW) {
            final pixelIndex = yRowIndex + x;
            out[pixelIndex] = r;
            out[channelSize + pixelIndex] = g;
            out[(channelSize * 2) + pixelIndex] = b;
          } else {
            final pixelIndex = (yRowIndex + x) * 3;
            out[pixelIndex] = r;
            out[pixelIndex + 1] = g;
            out[pixelIndex + 2] = b;
          }
        }
      }
    } else if (bgraBytes != null) {
      final bgra = bgraBytes;

      for (int y = 0; y < targetH; y++) {
        final yRowIndex = y * targetW;
        final preSrcX90 = (y * xRatio).toInt().clamp(0, srcW - 1);
        final preSrcY0 = !isAnyRotation ? (y * yRatio).toInt().clamp(0, srcH - 1) : 0;
        final preRowOffset0 = preSrcY0 * yRowStride;

        for (int x = 0; x < targetW; x++) {
          final int srcX;
          final int srcY;
          final int rowOffset;

          if (isRotated90) {
            srcX = preSrcX90;
            srcY = ((targetW - 1 - x) * yRatio).toInt().clamp(0, srcH - 1);
            rowOffset = srcY * yRowStride;
          } else if (!isAnyRotation) {
            srcX = (x * xRatio).toInt().clamp(0, srcW - 1);
            srcY = preSrcY0;
            rowOffset = preRowOffset0;
          } else if (isRotated270) {
            srcX = ((targetH - 1 - y) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = (x * yRatio).toInt().clamp(0, srcH - 1);
            rowOffset = srcY * yRowStride;
          } else {
            srcX = ((targetW - 1 - x) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = ((targetH - 1 - y) * yRatio).toInt().clamp(0, srcH - 1);
            rowOffset = srcY * yRowStride;
          }

          final pixelOffset = rowOffset + (srcX * 4);

          if (pixelOffset + 2 < bgra.length) {
            final b = bgra[pixelOffset] / 255.0;
            final g = bgra[pixelOffset + 1] / 255.0;
            final r = bgra[pixelOffset + 2] / 255.0;

            if (isNCHW) {
              final pixelIndex = yRowIndex + x;
              out[pixelIndex] = r;
              out[channelSize + pixelIndex] = g;
              out[(channelSize * 2) + pixelIndex] = b;
            } else {
              final pixelIndex = (yRowIndex + x) * 3;
              out[pixelIndex] = r;
              out[pixelIndex + 1] = g;
              out[pixelIndex + 2] = b;
            }
          }
        }
      }
    }

    return out;
  }

  /// Converts raw frame planes directly to a quantized Int8List buffer.
  /// Used for full integer INT8 quantized TFLite models.
  /// Quantization formula: q = round(val / scale) + zeroPoint
  static Int8List frameToInt8Buffer({
    required Uint8List yPlaneBytes,
    Uint8List? uPlaneBytes,
    Uint8List? vPlaneBytes,
    Uint8List? bgraBytes,
    required int srcW,
    required int srcH,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required bool isYuv,
    required int targetW,
    required int targetH,
    required bool isNCHW,
    int rotationDegrees = 0,
    double scale = 1.0 / 255.0,
    int zeroPoint = 0,
    Int8List? reusableBuffer,
  }) {
    final totalElements = targetW * targetH * 3;
    final out = (reusableBuffer != null && reusableBuffer.length == totalElements)
        ? reusableBuffer
        : Int8List(totalElements);

    final isRotated90 = rotationDegrees == 90;
    final isRotated270 = rotationDegrees == 270;
    final isRotated180 = rotationDegrees == 180;
    final isAnyRotation = isRotated90 || isRotated270 || isRotated180;

    final double xRatio;
    final double yRatio;
    if (isRotated90 || isRotated270) {
      xRatio = srcW / targetH;
      yRatio = srcH / targetW;
    } else {
      xRatio = srcW / targetW;
      yRatio = srcH / targetH;
    }
    final channelSize = targetW * targetH;
    final invScale = scale > 0 ? (1.0 / scale) : 255.0;

    int quantize(double floatVal) {
      final q = (floatVal * invScale + zeroPoint).round();
      return q.clamp(-128, 127);
    }

    if (isYuv && uPlaneBytes != null && vPlaneBytes != null) {
      final uBytes = uPlaneBytes;
      final vBytes = vPlaneBytes;

      for (int y = 0; y < targetH; y++) {
        final yRowIndex = y * targetW;
        final preSrcX90 = (y * xRatio).toInt().clamp(0, srcW - 1);
        final preSrcY0 = !isAnyRotation ? (y * yRatio).toInt().clamp(0, srcH - 1) : 0;
        final preRowOffset0 = preSrcY0 * yRowStride;
        final preUvOffset0 = (preSrcY0 >> 1) * uvRowStride;

        for (int x = 0; x < targetW; x++) {
          final int srcX;
          final int srcY;
          final int yOffset;
          final int uvOffset;

          if (isRotated90) {
            srcX = preSrcX90;
            srcY = ((targetW - 1 - x) * yRatio).toInt().clamp(0, srcH - 1);
            yOffset = srcY * yRowStride;
            uvOffset = (srcY >> 1) * uvRowStride;
          } else if (!isAnyRotation) {
            srcX = (x * xRatio).toInt().clamp(0, srcW - 1);
            srcY = preSrcY0;
            yOffset = preRowOffset0;
            uvOffset = preUvOffset0;
          } else if (isRotated270) {
            srcX = ((targetH - 1 - y) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = (x * yRatio).toInt().clamp(0, srcH - 1);
            yOffset = srcY * yRowStride;
            uvOffset = (srcY >> 1) * uvRowStride;
          } else {
            srcX = ((targetW - 1 - x) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = ((targetH - 1 - y) * yRatio).toInt().clamp(0, srcH - 1);
            yOffset = srcY * yRowStride;
            uvOffset = (srcY >> 1) * uvRowStride;
          }

          final uvIndex = uvOffset + (srcX >> 1) * uvPixelStride;

          final yVal = yPlaneBytes[yOffset + srcX];
          final uVal = uBytes[uvIndex];
          final vVal = vBytes[uvIndex];

          final c = yVal - 16;
          final d = uVal - 128;
          final e = vVal - 128;

          final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255) / 255.0;
          final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255) / 255.0;
          final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255) / 255.0;

          final qr = quantize(r);
          final qg = quantize(g);
          final qb = quantize(b);

          if (isNCHW) {
            final pixelIndex = yRowIndex + x;
            out[pixelIndex] = qr;
            out[channelSize + pixelIndex] = qg;
            out[(channelSize * 2) + pixelIndex] = qb;
          } else {
            final pixelIndex = (yRowIndex + x) * 3;
            out[pixelIndex] = qr;
            out[pixelIndex + 1] = qg;
            out[pixelIndex + 2] = qb;
          }
        }
      }
    } else if (bgraBytes != null) {
      final bgra = bgraBytes;

      for (int y = 0; y < targetH; y++) {
        final yRowIndex = y * targetW;
        final preSrcX90 = (y * xRatio).toInt().clamp(0, srcW - 1);
        final preSrcY0 = !isAnyRotation ? (y * yRatio).toInt().clamp(0, srcH - 1) : 0;
        final preRowOffset0 = preSrcY0 * yRowStride;

        for (int x = 0; x < targetW; x++) {
          final int srcX;
          final int srcY;
          final int rowOffset;

          if (isRotated90) {
            srcX = preSrcX90;
            srcY = ((targetW - 1 - x) * yRatio).toInt().clamp(0, srcH - 1);
            rowOffset = srcY * yRowStride;
          } else if (!isAnyRotation) {
            srcX = (x * xRatio).toInt().clamp(0, srcW - 1);
            srcY = preSrcY0;
            rowOffset = preRowOffset0;
          } else if (isRotated270) {
            srcX = ((targetH - 1 - y) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = (x * yRatio).toInt().clamp(0, srcH - 1);
            rowOffset = srcY * yRowStride;
          } else {
            srcX = ((targetW - 1 - x) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = ((targetH - 1 - y) * yRatio).toInt().clamp(0, srcH - 1);
            rowOffset = srcY * yRowStride;
          }

          final pixelOffset = rowOffset + (srcX * 4);

          if (pixelOffset + 2 < bgra.length) {
            final b = bgra[pixelOffset] / 255.0;
            final g = bgra[pixelOffset + 1] / 255.0;
            final r = bgra[pixelOffset + 2] / 255.0;

            final qr = quantize(r);
            final qg = quantize(g);
            final qb = quantize(b);

            if (isNCHW) {
              final pixelIndex = yRowIndex + x;
              out[pixelIndex] = qr;
              out[channelSize + pixelIndex] = qg;
              out[(channelSize * 2) + pixelIndex] = qb;
            } else {
              final pixelIndex = (yRowIndex + x) * 3;
              out[pixelIndex] = qr;
              out[pixelIndex + 1] = qg;
              out[pixelIndex + 2] = qb;
            }
          }
        }
      }
    }

    return out;
  }

  /// Converts raw frame planes directly to a quantized Uint8List buffer.
  /// Used for UINT8 quantized TFLite models.
  static Uint8List frameToUint8Buffer({
    required Uint8List yPlaneBytes,
    Uint8List? uPlaneBytes,
    Uint8List? vPlaneBytes,
    Uint8List? bgraBytes,
    required int srcW,
    required int srcH,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required bool isYuv,
    required int targetW,
    required int targetH,
    required bool isNCHW,
    int rotationDegrees = 0,
    double scale = 1.0 / 255.0,
    int zeroPoint = 0,
    Uint8List? reusableBuffer,
  }) {
    final totalElements = targetW * targetH * 3;
    final out = (reusableBuffer != null && reusableBuffer.length == totalElements)
        ? reusableBuffer
        : Uint8List(totalElements);

    final isRotated90 = rotationDegrees == 90;
    final isRotated270 = rotationDegrees == 270;
    final isRotated180 = rotationDegrees == 180;
    final isAnyRotation = isRotated90 || isRotated270 || isRotated180;

    final double xRatio;
    final double yRatio;
    if (isRotated90 || isRotated270) {
      xRatio = srcW / targetH;
      yRatio = srcH / targetW;
    } else {
      xRatio = srcW / targetW;
      yRatio = srcH / targetH;
    }
    final channelSize = targetW * targetH;
    final invScale = scale > 0 ? (1.0 / scale) : 255.0;

    int quantize(double floatVal) {
      final q = (floatVal * invScale + zeroPoint).round();
      return q.clamp(0, 255);
    }

    if (isYuv && uPlaneBytes != null && vPlaneBytes != null) {
      final uBytes = uPlaneBytes;
      final vBytes = vPlaneBytes;

      for (int y = 0; y < targetH; y++) {
        final yRowIndex = y * targetW;
        final preSrcX90 = (y * xRatio).toInt().clamp(0, srcW - 1);
        final preSrcY0 = !isAnyRotation ? (y * yRatio).toInt().clamp(0, srcH - 1) : 0;
        final preRowOffset0 = preSrcY0 * yRowStride;
        final preUvOffset0 = (preSrcY0 >> 1) * uvRowStride;

        for (int x = 0; x < targetW; x++) {
          final int srcX;
          final int srcY;
          final int yOffset;
          final int uvOffset;

          if (isRotated90) {
            srcX = preSrcX90;
            srcY = ((targetW - 1 - x) * yRatio).toInt().clamp(0, srcH - 1);
            yOffset = srcY * yRowStride;
            uvOffset = (srcY >> 1) * uvRowStride;
          } else if (!isAnyRotation) {
            srcX = (x * xRatio).toInt().clamp(0, srcW - 1);
            srcY = preSrcY0;
            yOffset = preRowOffset0;
            uvOffset = preUvOffset0;
          } else if (isRotated270) {
            srcX = ((targetH - 1 - y) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = (x * yRatio).toInt().clamp(0, srcH - 1);
            yOffset = srcY * yRowStride;
            uvOffset = (srcY >> 1) * uvRowStride;
          } else {
            srcX = ((targetW - 1 - x) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = ((targetH - 1 - y) * yRatio).toInt().clamp(0, srcH - 1);
            yOffset = srcY * yRowStride;
            uvOffset = (srcY >> 1) * uvRowStride;
          }

          final uvIndex = uvOffset + (srcX >> 1) * uvPixelStride;

          final yVal = yPlaneBytes[yOffset + srcX];
          final uVal = uBytes[uvIndex];
          final vVal = vBytes[uvIndex];

          final c = yVal - 16;
          final d = uVal - 128;
          final e = vVal - 128;

          final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255) / 255.0;
          final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255) / 255.0;
          final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255) / 255.0;

          final qr = quantize(r);
          final qg = quantize(g);
          final qb = quantize(b);

          if (isNCHW) {
            final pixelIndex = yRowIndex + x;
            out[pixelIndex] = qr;
            out[channelSize + pixelIndex] = qg;
            out[(channelSize * 2) + pixelIndex] = qb;
          } else {
            final pixelIndex = (yRowIndex + x) * 3;
            out[pixelIndex] = qr;
            out[pixelIndex + 1] = qg;
            out[pixelIndex + 2] = qb;
          }
        }
      }
    } else if (bgraBytes != null) {
      final bgra = bgraBytes;

      for (int y = 0; y < targetH; y++) {
        final yRowIndex = y * targetW;
        final preSrcX90 = (y * xRatio).toInt().clamp(0, srcW - 1);
        final preSrcY0 = !isAnyRotation ? (y * yRatio).toInt().clamp(0, srcH - 1) : 0;
        final preRowOffset0 = preSrcY0 * yRowStride;

        for (int x = 0; x < targetW; x++) {
          final int srcX;
          final int srcY;
          final int rowOffset;

          if (isRotated90) {
            srcX = preSrcX90;
            srcY = ((targetW - 1 - x) * yRatio).toInt().clamp(0, srcH - 1);
            rowOffset = srcY * yRowStride;
          } else if (!isAnyRotation) {
            srcX = (x * xRatio).toInt().clamp(0, srcW - 1);
            srcY = preSrcY0;
            rowOffset = preRowOffset0;
          } else if (isRotated270) {
            srcX = ((targetH - 1 - y) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = (x * yRatio).toInt().clamp(0, srcH - 1);
            rowOffset = srcY * yRowStride;
          } else {
            srcX = ((targetW - 1 - x) * xRatio).toInt().clamp(0, srcW - 1);
            srcY = ((targetH - 1 - y) * yRatio).toInt().clamp(0, srcH - 1);
            rowOffset = srcY * yRowStride;
          }

          final pixelOffset = rowOffset + (srcX * 4);

          if (pixelOffset + 2 < bgra.length) {
            final b = bgra[pixelOffset] / 255.0;
            final g = bgra[pixelOffset + 1] / 255.0;
            final r = bgra[pixelOffset + 2] / 255.0;

            final qr = quantize(r);
            final qg = quantize(g);
            final qb = quantize(b);

            if (isNCHW) {
              final pixelIndex = yRowIndex + x;
              out[pixelIndex] = qr;
              out[channelSize + pixelIndex] = qg;
              out[(channelSize * 2) + pixelIndex] = qb;
            } else {
              final pixelIndex = (yRowIndex + x) * 3;
              out[pixelIndex] = qr;
              out[pixelIndex + 1] = qg;
              out[pixelIndex + 2] = qb;
            }
          }
        }
      }
    }

    return out;
  }

  /// Converts the raw camera frame planes directly into an upright JPEG buffer.
  /// Runs inside the background isolate to prevent UI frame drops.
  static Uint8List? frameToUprightJpeg({
    required Uint8List yPlaneBytes,
    Uint8List? uPlaneBytes,
    Uint8List? vPlaneBytes,
    Uint8List? bgraBytes,
    required int srcW,
    required int srcH,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required bool isYuv,
    int rotationDegrees = 0,
    int quality = 90,
  }) {
    final isRotated = rotationDegrees == 90 || rotationDegrees == 270;
    final outW = isRotated ? srcH : srcW;
    final outH = isRotated ? srcW : srcH;

    final image = img.Image(width: outW, height: outH);

    if (isYuv && uPlaneBytes != null && vPlaneBytes != null) {
      final uBytes = uPlaneBytes;
      final vBytes = vPlaneBytes;

      for (int y = 0; y < outH; y++) {
        for (int x = 0; x < outW; x++) {
          final int srcX;
          final int srcY;
          if (rotationDegrees == 90) {
            srcX = y;
            srcY = outW - 1 - x;
          } else if (rotationDegrees == 270) {
            srcX = outH - 1 - y;
            srcY = x;
          } else if (rotationDegrees == 180) {
            srcX = outW - 1 - x;
            srcY = outH - 1 - y;
          } else {
            srcX = x;
            srcY = y;
          }

          final safeSrcX = srcX.clamp(0, srcW - 1);
          final safeSrcY = srcY.clamp(0, srcH - 1);

          final yOffset = safeSrcY * yRowStride;
          final uvOffset = (safeSrcY >> 1) * uvRowStride;
          final uvIndex = uvOffset + (safeSrcX >> 1) * uvPixelStride;

          final yVal = yPlaneBytes[yOffset + safeSrcX];
          final uVal = uBytes[uvIndex];
          final vVal = vBytes[uvIndex];

          final c = yVal - 16;
          final d = uVal - 128;
          final e = vVal - 128;

          final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
          final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
          final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);

          image.setPixelRgb(x, y, r, g, b);
        }
      }
    } else if (bgraBytes != null) {
      final bgra = bgraBytes;
      for (int y = 0; y < outH; y++) {
        for (int x = 0; x < outW; x++) {
          final int srcX;
          final int srcY;
          if (rotationDegrees == 90) {
            srcX = y;
            srcY = outW - 1 - x;
          } else if (rotationDegrees == 270) {
            srcX = outH - 1 - y;
            srcY = x;
          } else if (rotationDegrees == 180) {
            srcX = outW - 1 - x;
            srcY = outH - 1 - y;
          } else {
            srcX = x;
            srcY = y;
          }

          final safeSrcX = srcX.clamp(0, srcW - 1);
          final safeSrcY = srcY.clamp(0, srcH - 1);

          final pixelOffset = (safeSrcY * yRowStride) + (safeSrcX * 4);
          if (pixelOffset + 2 < bgra.length) {
            final b = bgra[pixelOffset];
            final g = bgra[pixelOffset + 1];
            final r = bgra[pixelOffset + 2];
            image.setPixelRgb(x, y, r, g, b);
          }
        }
      }
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  /// Converts a flat typed buffer into nested List structure required by interpreter
  static dynamic bufferToNestedTensor({
    required TypedData buffer,
    required int targetW,
    required int targetH,
    required bool isNCHW,
  }) {
    final channelSize = targetW * targetH;

    if (buffer is Float32List) {
      if (isNCHW) {
        final rChannel = List.generate(
          targetH,
          (y) => List.generate(targetW, (x) => buffer[(y * targetW) + x]),
        );
        final gChannel = List.generate(
          targetH,
          (y) => List.generate(targetW, (x) => buffer[channelSize + (y * targetW) + x]),
        );
        final bChannel = List.generate(
          targetH,
          (y) => List.generate(targetW, (x) => buffer[(channelSize * 2) + (y * targetW) + x]),
        );

        return [
          [rChannel, gChannel, bChannel],
        ];
      } else {
        return [
          List.generate(
            targetH,
            (y) => List.generate(targetW, (x) {
              final idx = ((y * targetW) + x) * 3;
              return [buffer[idx], buffer[idx + 1], buffer[idx + 2]];
            }),
          ),
        ];
      }
    } else if (buffer is Int8List) {
      if (isNCHW) {
        final rChannel = List.generate(
          targetH,
          (y) => List.generate(targetW, (x) => buffer[(y * targetW) + x]),
        );
        final gChannel = List.generate(
          targetH,
          (y) => List.generate(targetW, (x) => buffer[channelSize + (y * targetW) + x]),
        );
        final bChannel = List.generate(
          targetH,
          (y) => List.generate(targetW, (x) => buffer[(channelSize * 2) + (y * targetW) + x]),
        );

        return [
          [rChannel, gChannel, bChannel],
        ];
      } else {
        return [
          List.generate(
            targetH,
            (y) => List.generate(targetW, (x) {
              final idx = ((y * targetW) + x) * 3;
              return [buffer[idx], buffer[idx + 1], buffer[idx + 2]];
            }),
          ),
        ];
      }
    } else if (buffer is Uint8List) {
      if (isNCHW) {
        final rChannel = List.generate(
          targetH,
          (y) => List.generate(targetW, (x) => buffer[(y * targetW) + x]),
        );
        final gChannel = List.generate(
          targetH,
          (y) => List.generate(targetW, (x) => buffer[channelSize + (y * targetW) + x]),
        );
        final bChannel = List.generate(
          targetH,
          (y) => List.generate(targetW, (x) => buffer[(channelSize * 2) + (y * targetW) + x]),
        );

        return [
          [rChannel, gChannel, bChannel],
        ];
      } else {
        return [
          List.generate(
            targetH,
            (y) => List.generate(targetW, (x) {
              final idx = ((y * targetW) + x) * 3;
              return [buffer[idx], buffer[idx + 1], buffer[idx + 2]];
            }),
          ),
        ];
      }
    }

    return null;
  }

  /// High-speed Laplacian variance calculation computed on the camera luminance (Y) plane.
  /// Measures image sharpness / motion blur in ~1.5ms.
  /// Returns variance σ²(∇²I). Values > 80-100 indicate high sharpness / no blur.
  static double computeLaplacianVariance({
    required Uint8List yPlaneBytes,
    required int srcW,
    required int srcH,
    required int yRowStride,
    int sampleStep = 4, // Strided sampling for O(N/16) speedup
  }) {
    double sum = 0.0;
    double sumSq = 0.0;
    int count = 0;

    for (int y = sampleStep; y < srcH - sampleStep; y += sampleStep) {
      final rowOffset = y * yRowStride;
      final prevRowOffset = (y - sampleStep) * yRowStride;
      final nextRowOffset = (y + sampleStep) * yRowStride;

      for (int x = sampleStep; x < srcW - sampleStep; x += sampleStep) {
        final center = yPlaneBytes[rowOffset + x];
        final left = yPlaneBytes[rowOffset + (x - sampleStep)];
        final right = yPlaneBytes[rowOffset + (x + sampleStep)];
        final up = yPlaneBytes[prevRowOffset + x];
        final down = yPlaneBytes[nextRowOffset + x];

        // Discrete Laplacian kernel
        final laplacian = (up + down + left + right) - (center * 4);
        final val = laplacian.toDouble();

        sum += val;
        sumSq += val * val;
        count++;
      }
    }

    if (count == 0) return 0.0;
    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    return variance > 0 ? variance : 0.0;
  }
}
