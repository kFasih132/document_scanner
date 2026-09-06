import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/scanned_document.dart';

/// Service for managing persistent local storage of scanned documents,
/// their captured page images, and metadata index.
class LocalDocumentStorageService {
  static const String _storageFolderName = 'doc_scanner_storage';
  static const String _indexFileName = 'documents_index.json';

  Future<Directory> _getBaseDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final baseDir = Directory('${appDir.path}/$_storageFolderName');
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }

  Future<File> _getIndexFile() async {
    final baseDir = await _getBaseDirectory();
    return File('${baseDir.path}/$_indexFileName');
  }

  /// Loads all saved documents from the persistent local storage index.
  Future<List<ScannedDocument>> loadAllDocuments() async {
    try {
      final indexFile = await _getIndexFile();
      if (!await indexFile.exists()) {
        return [];
      }

      final content = await indexFile.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList
          .map((item) => ScannedDocument.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('Error loading saved documents: $e');
      return [];
    }
  }

  /// Saves or updates a [ScannedDocument] locally.
  /// Copies all captured images from temporary cache into persistent storage.
  Future<ScannedDocument> saveDocument(ScannedDocument doc) async {
    try {
      final baseDir = await _getBaseDirectory();
      final docImagesDir = Directory('${baseDir.path}/documents/${doc.id}');
      if (!await docImagesDir.exists()) {
        await docImagesDir.create(recursive: true);
      }

      // Copy page images to persistent storage if they are not already stored there
      final List<ScannedPage> persistedPages = [];
      for (int i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        final sourceFile = File(page.imagePath);

        if (await sourceFile.exists()) {
          // If already in the persistent document directory, keep as is
          if (page.imagePath.startsWith(docImagesDir.path)) {
            persistedPages.add(page.copyWith(pageIndex: i));
          } else {
            final targetPath = '${docImagesDir.path}/page_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final copiedFile = await sourceFile.copy(targetPath);
            persistedPages.add(page.copyWith(
              imagePath: copiedFile.path,
              pageIndex: i,
            ));
          }
        } else {
          // Keep reference if simulated/asset path
          persistedPages.add(page.copyWith(pageIndex: i));
        }
      }

      final updatedDoc = doc.copyWith(pages: persistedPages);

      // Update index
      final existingDocs = await loadAllDocuments();
      final existingIndex = existingDocs.indexWhere((d) => d.id == updatedDoc.id);

      if (existingIndex != -1) {
        existingDocs[existingIndex] = updatedDoc;
      } else {
        existingDocs.insert(0, updatedDoc);
      }

      await _writeIndex(existingDocs);
      return updatedDoc;
    } catch (e) {
      debugPrint('Error saving document locally: $e');
      rethrow;
    }
  }

  /// Deletes a document, its persisted page images, and its generated PDF.
  Future<void> deleteDocument(String documentId) async {
    try {
      final baseDir = await _getBaseDirectory();
      final docImagesDir = Directory('${baseDir.path}/documents/$documentId');
      if (await docImagesDir.exists()) {
        await docImagesDir.delete(recursive: true);
      }

      final existingDocs = await loadAllDocuments();
      final docToDelete = existingDocs.where((d) => d.id == documentId).firstOrNull;
      if (docToDelete != null && docToDelete.pdfPath != null) {
        final pdfFile = File(docToDelete.pdfPath!);
        if (await pdfFile.exists()) {
          await pdfFile.delete();
        }
      }

      final updatedDocs = existingDocs.where((d) => d.id != documentId).toList();
      await _writeIndex(updatedDocs);
    } catch (e) {
      debugPrint('Error deleting document: $e');
      rethrow;
    }
  }

  Future<void> _writeIndex(List<ScannedDocument> docs) async {
    final indexFile = await _getIndexFile();
    final jsonList = docs.map((d) => d.toMap()).toList();
    await indexFile.writeAsString(jsonEncode(jsonList));
  }
}
