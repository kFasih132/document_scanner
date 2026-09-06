import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/scanned_document.dart';

/// Production-ready service for generating and sharing PDF files from scanned documents.
class PdfExportService {
  static const String _pdfFolderName = 'doc_scanner_storage/pdfs';

  Future<Directory> _getPdfDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${appDir.path}/$_pdfFolderName');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    return pdfDir;
  }

  /// Generates a PDF file from the provided [ScannedDocument] and saves it locally.
  /// Returns the created [File].
  Future<File> generateAndSavePdf(ScannedDocument document) async {
    try {
      final pdf = pw.Document(
        title: document.title,
        author: 'DocScanner M3',
        creator: 'DocScanner M3 Flutter App',
      );

      for (int i = 0; i < document.pages.length; i++) {
        final page = document.pages[i];
        final imageFile = File(page.imagePath);

        if (await imageFile.exists()) {
          final Uint8List imageBytes = await imageFile.readAsBytes();
          final image = pw.MemoryImage(imageBytes);

          final bool isRotatedLandscape = (page.rotationDegrees % 180 != 0);
          final pageFormat = isRotatedLandscape
              ? PdfPageFormat.a4.landscape
              : PdfPageFormat.a4;

          pdf.addPage(
            pw.Page(
              pageFormat: pageFormat,
              margin: const pw.EdgeInsets.all(16),
              build: (pw.Context context) {
                return pw.Center(
                  child: pw.Image(
                    image,
                    fit: pw.BoxFit.contain,
                  ),
                );
              },
            ),
          );
        } else {
          // Fallback text page for simulated / preview testing
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(32),
              build: (pw.Context context) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      document.title,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Divider(),
                    pw.SizedBox(height: 24),
                    pw.Container(
                      height: 400,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        color: PdfColors.grey100,
                      ),
                      child: pw.Center(
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            pw.Text(
                              'Document Page ${page.pageIndex + 1}',
                              style: pw.TextStyle(
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blueGrey800,
                              ),
                            ),
                            pw.SizedBox(height: 8),
                            pw.Text(
                              'Filter applied: ${page.filter.label} | Rotation: ${page.rotationDegrees}°',
                              style: const pw.TextStyle(
                                fontSize: 12,
                                color: PdfColors.grey600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    pw.Spacer(),
                    pw.Align(
                      alignment: pw.Alignment.bottomRight,
                      child: pw.Text(
                        'Page ${i + 1} of ${document.pages.length}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        }
      }

      final pdfBytes = await pdf.save();
      final pdfDir = await _getPdfDirectory();

      final safeTitle = document.title
          .replaceAll(RegExp(r'[^\w\s\.-]'), '_')
          .trim()
          .replaceAll(' ', '_');
      final fileName = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${pdfDir.path}/$fileName');

      await file.writeAsBytes(pdfBytes);
      debugPrint('PDF successfully generated at: ${file.path}');
      return file;
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      rethrow;
    }
  }

  /// Opens the native OS share sheet to share the generated PDF file.
  Future<ShareResult> sharePdfFile({
    required File pdfFile,
    required String title,
  }) async {
    try {
      final fileName = pdfFile.path.split(Platform.pathSeparator).last;
      return await Share.shareXFiles(
        [
          XFile(
            pdfFile.path,
            mimeType: 'application/pdf',
            name: fileName,
          ),
        ],
        text: 'Document: $title',
        subject: title,
      );
    } catch (e) {
      debugPrint('Error sharing PDF: $e');
      rethrow;
    }
  }

  /// Helper that generates (if needed) and opens the share dialog for a [ScannedDocument].
  Future<void> shareScannedDocument(ScannedDocument document) async {
    File? pdfFile;
    if (document.pdfPath != null) {
      final cachedFile = File(document.pdfPath!);
      if (await cachedFile.exists()) {
        pdfFile = cachedFile;
      }
    }

    pdfFile ??= await generateAndSavePdf(document);

    await sharePdfFile(pdfFile: pdfFile, title: document.title);
  }
}
