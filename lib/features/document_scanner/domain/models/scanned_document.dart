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
  final int pageIndex;
  final DocumentFilter filter;
  final CropQuadCorners cropCorners;
  final int rotationDegrees;

  const ScannedPage({
    required this.id,
    required this.imagePath,
    required this.pageIndex,
    this.filter = DocumentFilter.original,
    this.cropCorners = const CropQuadCorners(),
    this.rotationDegrees = 0,
  });

  ScannedPage copyWith({
    String? id,
    String? imagePath,
    int? pageIndex,
    DocumentFilter? filter,
    CropQuadCorners? cropCorners,
    int? rotationDegrees,
  }) {
    return ScannedPage(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
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
      pageIndex: map['pageIndex'] as int? ?? 0,
      filter: DocumentFilter.values.firstWhere(
        (f) => f.name == map['filter'],
        orElse: () => DocumentFilter.original,
      ),
      cropCorners: map['cropCorners'] != null
          ? CropQuadCorners.fromMap(Map<String, dynamic>.from(map['cropCorners'] as Map))
          : const CropQuadCorners(),
      rotationDegrees: map['rotationDegrees'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, imagePath, pageIndex, filter, cropCorners, rotationDegrees];
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
