import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/scanned_document.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../screens/document_preview_screen.dart';

/// Modal bottom sheet providing actions for a saved [ScannedDocument]:
/// - Share PDF
/// - Export / Save PDF locally
/// - Open & Edit document
/// - Delete document
class DocumentOptionsSheet extends StatelessWidget {
  final ScannedDocument document;

  const DocumentOptionsSheet({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: AppSpacing.roundedFull,
                ),
              ),
            ),

            // Header with thumbnail info
            Row(
              children: [
                Container(
                  width: 44,
                  height: 54,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: AppSpacing.roundedSm,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.picture_as_pdf_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'} • ${document.createdAt.day}/${document.createdAt.month}/${document.createdAt.year}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(),

            // Action: Share PDF
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share PDF'),
              subtitle: const Text('Export & send via WhatsApp, Drive, Mail...'),
              shape: const RoundedRectangleBorder(borderRadius: AppSpacing.roundedMd),
              onTap: () {
                Navigator.pop(context);
                context.read<ScannerBloc>().add(SharePdfEvent(document: document));
              },
            ),

            // Action: Export / Save PDF locally
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('Save PDF Locally'),
              subtitle: Text(
                document.pdfPath != null
                    ? 'Saved at: ${document.pdfPath}'
                    : 'Generate and store PDF in app storage',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              shape: const RoundedRectangleBorder(borderRadius: AppSpacing.roundedMd),
              onTap: () {
                Navigator.pop(context);
                context.read<ScannerBloc>().add(ExportPdfEvent(document));
              },
            ),

            // Action: Open in Preview / Editor
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Open & Edit Pages'),
              subtitle: const Text('Apply filters, crop, rotate or add pages'),
              shape: const RoundedRectangleBorder(borderRadius: AppSpacing.roundedMd),
              onTap: () {
                Navigator.pop(context);
                context.read<ScannerBloc>().add(OpenDocumentForEditingEvent(document));
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DocumentPreviewScreen(document: document),
                  ),
                );
              },
            ),

            // Action: Delete
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
              title: Text(
                'Delete Document',
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Permanently remove all scanned pages'),
              shape: const RoundedRectangleBorder(borderRadius: AppSpacing.roundedMd),
              onTap: () {
                final bloc = context.read<ScannerBloc>();
                _confirmDelete(context, bloc);
              },
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext sheetContext, ScannerBloc bloc) {
    showDialog(
      context: sheetContext,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Document?'),
          content: Text('Are you sure you want to permanently delete "${document.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () {
                bloc.add(DeleteDocumentEvent(document.id));
                Navigator.pop(dialogContext);
                Navigator.pop(sheetContext);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
