import 'dart:typed_data';

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
    Float32List? reusableBuffer,
  }) {
    final totalFloats = targetW * targetH * 3;
    final out = (reusableBuffer != null && reusableBuffer.length == totalFloats)
        ? reusableBuffer
        : Float32List(totalFloats);

    final xRatio = srcW / targetW;
    final yRatio = srcH / targetH;
    final channelSize = targetW * targetH;

    if (isYuv && uPlaneBytes != null && vPlaneBytes != null) {
      final uBytes = uPlaneBytes;
      final vBytes = vPlaneBytes;

      for (int y = 0; y < targetH; y++) {
        final srcY = (y * yRatio).toInt().clamp(0, srcH - 1);
        final yOffset = srcY * yRowStride;
        final uvOffset = (srcY >> 1) * uvRowStride;
        final yRowIndex = y * targetW;

        for (int x = 0; x < targetW; x++) {
          final srcX = (x * xRatio).toInt().clamp(0, srcW - 1);
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
        final srcY = (y * yRatio).toInt().clamp(0, srcH - 1);
        final rowOffset = srcY * yRowStride;
        final yRowIndex = y * targetW;

        for (int x = 0; x < targetW; x++) {
          final srcX = (x * xRatio).toInt().clamp(0, srcW - 1);
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

  /// Converts a flat Float32List buffer into nested List structure if required by interpreter
  static dynamic bufferToNestedTensor({
    required Float32List buffer,
    required int targetW,
    required int targetH,
    required bool isNCHW,
  }) {
    final channelSize = targetW * targetH;

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
}
