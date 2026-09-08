import 'dart:math' as math;
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

enum ScanMode {
  document('Document', Icons.description_outlined),
  idCard('ID Card', Icons.badge_outlined),
  batch('Batch Scan', Icons.photo_library_outlined),
  passport('Passport', Icons.menu_book_outlined);

  final String label;
  final IconData icon;
  const ScanMode(this.label, this.icon);
}

enum DocumentFilter {
  original('Original', Icons.image_outlined),
  magicColor('Enhanced', Icons.auto_fix_high_outlined),
  blackAndWhite('B & W', Icons.filter_b_and_w_outlined),
  grayscale('Grayscale', Icons.tonality_outlined);

  final String label;
  final IconData icon;
  const DocumentFilter(this.label, this.icon);
}

enum CornerType {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
}

class CropQuadCorners extends Equatable {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const CropQuadCorners({
    this.topLeft = const Offset(0.08, 0.12),
    this.topRight = const Offset(0.92, 0.12),
    this.bottomRight = const Offset(0.92, 0.88),
    this.bottomLeft = const Offset(0.08, 0.88),
  });

  /// Canonicalizes 4 arbitrary points into:
  /// topLeft, topRight, bottomRight, bottomLeft.
  factory CropQuadCorners.fromPoints(List<Offset> points) {
    assert(points.length == 4);

    final cx = (points[0].dx + points[1].dx + points[2].dx + points[3].dx) / 4.0;
    final cy = (points[0].dy + points[1].dy + points[2].dy + points[3].dy) / 4.0;

    const double baseAngle = -3.0 * math.pi / 4.0;
    const double twoPi = 2.0 * math.pi;

    final sorted = points.map((p) {
      final dx = p.dx - cx;
      final dy = p.dy - cy;
      double angle = math.atan2(dy, dx) - baseAngle;
      while (angle < 0.0) {
        angle += twoPi;
      }
      while (angle >= twoPi) {
        angle -= twoPi;
      }
      return (p, angle);
    }).toList();

    sorted.sort((a, b) => a.$2.compareTo(b.$2));

    return CropQuadCorners(
      topLeft: sorted[0].$1,
      topRight: sorted[1].$1,
      bottomRight: sorted[2].$1,
      bottomLeft: sorted[3].$1,
    );
  }

  /// Calculates the centroid (geometric center) of the 4 quadrilateral vertices
  Offset get center => Offset(
        (topLeft.dx + topRight.dx + bottomRight.dx + bottomLeft.dx) / 4.0,
        (topLeft.dy + topRight.dy + bottomRight.dy + bottomLeft.dy) / 4.0,
      );

  /// Computes the area of the quadrilateral using the Shoelace formula
  double get polygonArea {
    final s1 = (topLeft.dx * topRight.dy) +
        (topRight.dx * bottomRight.dy) +
        (bottomRight.dx * bottomLeft.dy) +
        (bottomLeft.dx * topLeft.dy);
    final s2 = (topLeft.dy * topRight.dx) +
        (topRight.dy * bottomRight.dx) +
        (bottomRight.dy * bottomLeft.dx) +
        (bottomLeft.dy * topLeft.dx);
    return 0.5 * (s1 - s2).abs();
  }

  CropQuadCorners copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
  }) {
    return CropQuadCorners(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'topLeft': {'dx': topLeft.dx, 'dy': topLeft.dy},
      'topRight': {'dx': topRight.dx, 'dy': topRight.dy},
      'bottomRight': {'dx': bottomRight.dx, 'dy': bottomRight.dy},
      'bottomLeft': {'dx': bottomLeft.dx, 'dy': bottomLeft.dy},
    };
  }

  factory CropQuadCorners.fromMap(Map<String, dynamic> map) {
    Offset parseOffset(dynamic v, Offset fallback) {
      if (v is Map) {
        final dx = (v['dx'] as num?)?.toDouble() ?? fallback.dx;
        final dy = (v['dy'] as num?)?.toDouble() ?? fallback.dy;
        return Offset(dx, dy);
      }
      return fallback;
    }

    return CropQuadCorners(
      topLeft: parseOffset(map['topLeft'], const Offset(0.08, 0.12)),
      topRight: parseOffset(map['topRight'], const Offset(0.92, 0.12)),
      bottomRight: parseOffset(map['bottomRight'], const Offset(0.92, 0.88)),
      bottomLeft: parseOffset(map['bottomLeft'], const Offset(0.08, 0.88)),
    );
  }

  @override
  List<Object?> get props => [topLeft, topRight, bottomRight, bottomLeft];
}

class ScannedPage extends Equatable {
  final String id;
  final String imagePath;
  final String? originalImagePath;
  final int pageIndex;
  final DocumentFilter filter;
  final CropQuadCorners cropCorners;
  final int rotationDegrees;

  const ScannedPage({
    required this.id,
    required this.imagePath,
    this.originalImagePath,
    required this.pageIndex,
    this.filter = DocumentFilter.original,
    this.cropCorners = const CropQuadCorners(),
    this.rotationDegrees = 0,
  });

  ScannedPage copyWith({
    String? id,
    String? imagePath,
    String? originalImagePath,
    int? pageIndex,
    DocumentFilter? filter,
    CropQuadCorners? cropCorners,
    int? rotationDegrees,
  }) {
    return ScannedPage(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      pageIndex: pageIndex ?? this.pageIndex,
      filter: filter ?? this.filter,
      cropCorners: cropCorners ?? this.cropCorners,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imagePath': imagePath,
      'originalImagePath': originalImagePath,
      'pageIndex': pageIndex,
      'filter': filter.name,
      'cropCorners': cropCorners.toMap(),
      'rotationDegrees': rotationDegrees,
    };
  }

  factory ScannedPage.fromMap(Map<String, dynamic> map) {
    return ScannedPage(
      id: map['id'] as String? ?? '',
      imagePath: map['imagePath'] as String? ?? '',
      originalImagePath: map['originalImagePath'] as String?,
      pageIndex: map['pageIndex'] as int? ?? 0,
      filter: DocumentFilter.values.firstWhere(
        (f) => f.name == map['filter'],
        orElse: () => DocumentFilter.original,
      ),
      cropCorners: map['cropCorners'] != null
          ? CropQuadCorners.fromMap(map['cropCorners'] as Map<String, dynamic>)
          : const CropQuadCorners(),
      rotationDegrees: map['rotationDegrees'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        id,
        imagePath,
        originalImagePath,
        pageIndex,
        filter,
        cropCorners,
        rotationDegrees,
      ];
}

class ScannedDocument extends Equatable {
  final String id;
  final String title;
  final DateTime createdAt;
  final List<ScannedPage> pages;
  final ScanMode scanMode;
  final String? pdfPath;

  const ScannedDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.pages,
    this.scanMode = ScanMode.document,
    this.pdfPath,
  });

  int get pageCount => pages.length;

  /// Generates a unique, timestamped default document title
  /// Format: Scan_D_M_YYYY_HHmmss (e.g. Scan_8_9_2026_120150)
  static String generateDefaultTitle([DateTime? time]) {
    final now = time ?? DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    return 'Scan_${now.day}_${now.month}_${now.year}_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
  }

  ScannedDocument copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    List<ScannedPage>? pages,
    ScanMode? scanMode,
    String? pdfPath,
    bool clearPdfPath = false,
  }) {
    return ScannedDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      pages: pages ?? this.pages,
      scanMode: scanMode ?? this.scanMode,
      pdfPath: clearPdfPath ? null : (pdfPath ?? this.pdfPath),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'pages': pages.map((p) => p.toMap()).toList(),
      'scanMode': scanMode.name,
      'pdfPath': pdfPath,
    };
  }

  factory ScannedDocument.fromMap(Map<String, dynamic> map) {
    return ScannedDocument(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      pages: (map['pages'] as List<dynamic>?)
              ?.map((p) => ScannedPage.fromMap(Map<String, dynamic>.from(p as Map)))
              .toList() ??
          const [],
      scanMode: ScanMode.values.firstWhere(
        (m) => m.name == map['scanMode'],
        orElse: () => ScanMode.document,
      ),
      pdfPath: map['pdfPath'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, title, createdAt, pages, scanMode, pdfPath];
}
