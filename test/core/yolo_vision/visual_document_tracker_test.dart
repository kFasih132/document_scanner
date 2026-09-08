import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:document_scanner/core/yolo_vision/models/oriented_detection_box.dart';
import 'package:document_scanner/core/yolo_vision/models/point_2d.dart';
import 'package:document_scanner/core/yolo_vision/services/visual_document_tracker.dart';
import 'package:document_scanner/features/document_scanner/domain/models/scanned_document.dart';

void main() {
  group('VisualDocumentTracker Unit Tests', () {
    late VisualDocumentTracker tracker;

    setUp(() {
      tracker = VisualDocumentTracker();
    });

    test('Viewfinder to Sensor coordinate roundtrip across sensor rotations', () {
      const rotations = [0, 90, 180, 270];
      const testPoints = [
        Offset(0.15, 0.25),
        Offset(0.85, 0.20),
        Offset(0.80, 0.75),
        Offset(0.20, 0.80),
      ];

      for (final rot in rotations) {
        for (final pt in testPoints) {
          final sensorPt = VisualDocumentTracker.viewfinderToSensorPixel(
            pt,
            rot,
            1920,
            1080,
          );
          final restoredVf = VisualDocumentTracker.sensorPixelToViewfinder(
            sensorPt,
            rot,
            1920,
            1080,
          );

          expect(restoredVf.dx, closeTo(pt.dx, 0.002),
              reason: 'dx failed at rotation $rot');
          expect(restoredVf.dy, closeTo(pt.dy, 0.002),
              reason: 'dy failed at rotation $rot');
        }
      }
    });

    test('Initializes tracking and extracts valid reference patches', () {
      const width = 640;
      const height = 480;
      final bytes = Uint8List(width * height);

      // Create synthetic high-contrast corners on a simulated document
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          // Inner document region has brighter intensity
          if (x >= 100 && x <= 500 && y >= 80 && y <= 400) {
            bytes[y * width + x] = 220;
          } else {
            bytes[y * width + x] = 40;
          }
        }
      }

      // 4 normalized corners corresponding to the synthetic document (at 0 degrees rotation)
      const corners = CropQuadCorners(
        topLeft: Offset(100 / 640, 80 / 480),
        topRight: Offset(500 / 640, 80 / 480),
        bottomRight: Offset(500 / 640, 400 / 480),
        bottomLeft: Offset(100 / 640, 400 / 480),
      );

      tracker.initializeTracking(
        corners: corners,
        luminanceBytes: bytes,
        width: width,
        height: height,
        bytesPerRow: width,
        rotationDegrees: 0,
      );

      expect(tracker.isTracking, isTrue);
      expect(tracker.currentCorners, equals(corners));
    });

    test('Tracks small translation shifts smoothly across frames', () {
      const width = 640;
      const height = 480;
      Uint8List makeBuffer(int shiftX, int shiftY) {
        final buffer = Uint8List(width * height);
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final docX = x - shiftX;
            final docY = y - shiftY;
            if (docX >= 120 && docX <= 480 && docY >= 100 && docY <= 380) {
              buffer[y * width + x] = 230;
            } else {
              buffer[y * width + x] = 30;
            }
          }
        }
        return buffer;
      }

      final frame1 = makeBuffer(0, 0);
      const initialCorners = CropQuadCorners(
        topLeft: Offset(120 / 640, 100 / 480),
        topRight: Offset(480 / 640, 100 / 480),
        bottomRight: Offset(480 / 640, 380 / 480),
        bottomLeft: Offset(120 / 640, 380 / 480),
      );

      tracker.initializeTracking(
        corners: initialCorners,
        luminanceBytes: frame1,
        width: width,
        height: height,
        bytesPerRow: width,
        rotationDegrees: 0,
      );

      expect(tracker.isTracking, isTrue);

      // Frame 2: Document shifts by +4 pixels horizontally and +3 pixels vertically
      final frame2 = makeBuffer(4, 3);
      final result = tracker.trackFrame(
        luminanceBytes: frame2,
        width: width,
        height: height,
        bytesPerRow: width,
        rotationDegrees: 0,
      );

      expect(result.isTrackingValid, isTrue);
      expect(result.confidence, greaterThan(0.7));

      // Expected new topLeft is (124/640, 103/480)
      expect(result.corners.topLeft.dx, closeTo(124 / 640, 0.01));
      expect(result.corners.topLeft.dy, closeTo(103 / 480, 0.01));
    });

    test('Reconciles with ML detection and eliminates drift', () {
      const width = 640;
      const height = 480;
      final bytes = Uint8List(width * height);
      bytes.fillRange(0, bytes.length, 128);

      const initialCorners = CropQuadCorners(
        topLeft: Offset(0.20, 0.20),
        topRight: Offset(0.80, 0.20),
        bottomRight: Offset(0.80, 0.80),
        bottomLeft: Offset(0.20, 0.80),
      );

      tracker.initializeTracking(
        corners: initialCorners,
        luminanceBytes: bytes,
        width: width,
        height: height,
        bytesPerRow: width,
        rotationDegrees: 0,
      );

      // ML returns ground-truth with a small drift correction
      const mlGroundTruth = CropQuadCorners(
        topLeft: Offset(0.22, 0.21),
        topRight: Offset(0.81, 0.21),
        bottomRight: Offset(0.79, 0.79),
        bottomLeft: Offset(0.21, 0.81),
      );

      tracker.reconcileWithMlDetection(
        mlCorners: mlGroundTruth,
        luminanceBytes: bytes,
        width: width,
        height: height,
        bytesPerRow: width,
        rotationDegrees: 0,
      );

      expect(tracker.isTracking, isTrue);
      // Blended corners should move towards ML ground truth
      expect(tracker.currentCorners!.topLeft.dx, closeTo(0.214, 0.01));
    });

    test('Rejects non-convex / self-intersecting polygon', () {
      const width = 640;
      const height = 480;
      final bytes = Uint8List(width * height);

      // Hourglass / bow-tie self-intersecting quad
      const twistedCorners = CropQuadCorners(
        topLeft: Offset(0.2, 0.2),
        topRight: Offset(0.8, 0.8), // Crossed!
        bottomRight: Offset(0.8, 0.2),
        bottomLeft: Offset(0.2, 0.8),
      );

      tracker.initializeTracking(
        corners: twistedCorners,
        luminanceBytes: bytes,
        width: width,
        height: height,
        bytesPerRow: width,
        rotationDegrees: 0,
      );

      // Must be rejected
      expect(tracker.isTracking, isFalse);
    });

    test('CropQuadCorners.fromPoints canonically orders unordered points', () {
      // Unordered points: [Bottom-Right, Top-Left, Bottom-Left, Top-Right]
      final points = [
        const Offset(0.9, 0.85),
        const Offset(0.1, 0.15),
        const Offset(0.12, 0.88),
        const Offset(0.88, 0.12),
      ];

      final corners = CropQuadCorners.fromPoints(points);

      expect(corners.topLeft, equals(const Offset(0.1, 0.15)));
      expect(corners.topRight, equals(const Offset(0.88, 0.12)));
      expect(corners.bottomRight, equals(const Offset(0.9, 0.85)));
      expect(corners.bottomLeft, equals(const Offset(0.12, 0.88)));
    });

    test('OrientedDetectionBox rotates points and preserves canonical corner order', () {
      final box = OrientedDetectionBox.fromPoints(
        label: 'document',
        confidence: 0.95,
        classIndex: 0,
        points: const [
          Point2D(x: 0.1, y: 0.2), // Top-Left
          Point2D(x: 0.9, y: 0.2), // Top-Right
          Point2D(x: 0.9, y: 0.8), // Bottom-Right
          Point2D(x: 0.1, y: 0.8), // Bottom-Left
        ],
      );

      // Rotate 90 degrees
      final rotated = box.rotate(90);

      // In rotated space, p1 MUST still be the visual Top-Left!
      expect(rotated.p1.x, lessThan(rotated.center.x));
      expect(rotated.p1.y, lessThan(rotated.center.y));

      // p2 MUST be visual Top-Right
      expect(rotated.p2.x, greaterThan(rotated.center.x));
      expect(rotated.p2.y, lessThan(rotated.center.y));

      // p3 MUST be visual Bottom-Right
      expect(rotated.p3.x, greaterThan(rotated.center.x));
      expect(rotated.p3.y, greaterThan(rotated.center.y));

      // p4 MUST be visual Bottom-Left
      expect(rotated.p4.x, lessThan(rotated.center.x));
      expect(rotated.p4.y, greaterThan(rotated.center.y));
    });
  });
}
